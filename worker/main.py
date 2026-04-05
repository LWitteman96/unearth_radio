"""
Unearth Radio — Recognition Worker

Queue consumer that processes song recognition requests from the PGMQ
``song_recognition`` queue.

Lifecycle of a single job
─────────────────────────
1. Poll the ``song_recognition`` PGMQ queue for pending recognition jobs
   (visibility timeout = 60 s so a crashed worker won't lose the message).
2. Capture ~10 seconds of audio from the station's stream URL via ffmpeg
   (``ffmpeg -i <stream_url> -t 10 -f mp3 -ab 128k pipe:1``).
3. Send the captured audio to the **AudD** API for fingerprint recognition.
   If AudD fails or returns no match, fall back to **ACRCloud**.
4. Write the recognition result to ``recognized_songs`` and update the
   corresponding ``recognition_requests.status`` (completed / no_match / failed).
5. Award points by inserting into ``point_events`` table.

Retry behaviour
───────────────
Messages that fail are *not* deleted from the queue — they automatically
re-appear after the visibility timeout expires, giving the worker another
chance.  After repeated failures the status is set to ``'failed'``.

Environment variables
─────────────────────
- SUPABASE_URL / SUPABASE_SERVICE_KEY — Supabase project credentials
- AUDD_API_TOKEN                     — AudD recognition API key
- ACRCLOUD_HOST / ACRCLOUD_KEY / ACRCLOUD_SECRET — ACRCloud fallback creds

PGMQ RPC naming note
─────────────────────
Supabase PGMQ exposes queue operations as PostgREST RPC calls. The function
names depend on the installed PGMQ extension version:
  - Newer: ``pgmq_read`` / ``pgmq_delete``  (schema-qualified internally)
  - Older: ``pgmq.read`` / ``pgmq.delete``  (dot-separated schema.function)
The worker tries ``pgmq_read`` first; if you need the alternative, change
the RPC name string below.
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import io
import logging
import os
import subprocess
import time
import uuid
from datetime import datetime, timezone
from typing import Any

import requests
from supabase import create_client, Client

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("recognition_worker")

TERMINAL_REQUEST_STATUSES = {"completed", "no_match", "failed"}
POINT_EVENT_TYPE_DISCOVERY = "discovery"
POINTS_PER_RECOGNITION = 5


# ---------------------------------------------------------------------------
# Supabase client
# ---------------------------------------------------------------------------


def get_supabase() -> Client:
    """Create a Supabase service-role client from environment variables."""
    url = os.environ["SUPABASE_URL"]
    key = os.environ["SUPABASE_SERVICE_KEY"]
    return create_client(url, key)


# ---------------------------------------------------------------------------
# Audio capture
# ---------------------------------------------------------------------------


def capture_audio(stream_url: str, duration: int = 10) -> bytes:
    """Capture audio from a radio stream using ffmpeg subprocess.

    Uses ffmpeg directly via subprocess (not ffmpeg-python bindings) so that
    the raw mp3 bytes can be piped back without writing a temp file.

    Args:
        stream_url: HTTP/HTTPS URL of the radio stream.
        duration:   How many seconds of audio to capture.

    Returns:
        Raw mp3 bytes.

    Raises:
        RuntimeError: If ffmpeg exits with a non-zero return code.
        subprocess.TimeoutExpired: If ffmpeg hangs beyond the allowed window.
    """
    cmd = [
        "ffmpeg",
        "-i",
        stream_url,
        "-t",
        str(duration),
        "-f",
        "mp3",
        "-ab",
        "128k",
        "-vn",  # no video
        "pipe:1",  # write to stdout
        "-y",  # overwrite (unused for pipe, but harmless)
        "-loglevel",
        "error",
    ]
    result = subprocess.run(cmd, capture_output=True, timeout=duration + 15)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {result.stderr.decode()}")
    return result.stdout


# ---------------------------------------------------------------------------
# AudD recognition (primary)
# ---------------------------------------------------------------------------


def recognize_audd(audio_bytes: bytes) -> dict[str, Any] | None:
    """Send audio to AudD API. Returns a normalised result dict or None.

    AudD returns ``{"status": "success", "result": {...}}`` on a match, or
    ``{"status": "success", "result": null}`` when nothing is recognised.

    Args:
        audio_bytes: Raw mp3 audio data.

    Returns:
        Dict with title/artist/album/spotify_uri/apple_music_url/album_art_url,
        or None if no match was found.
    """
    token = os.environ.get("AUDD_API_TOKEN", "")
    response = requests.post(
        "https://api.audd.io/",
        data={"api_token": token, "return": "spotify,apple_music"},
        files={"file": ("audio.mp3", io.BytesIO(audio_bytes), "audio/mpeg")},
        timeout=30,
    )
    response.raise_for_status()
    data = response.json()

    if data.get("status") != "success" or data.get("result") is None:
        return None

    result = data["result"]
    spotify = result.get("spotify") or {}
    apple = result.get("apple_music") or {}
    spotify_images: list[dict] = spotify.get("album", {}).get("images", [])

    return {
        "title": result.get("title"),
        "artist": result.get("artist"),
        "album": result.get("album"),
        "audd_song_link": result.get("song_link") or "",
        "spotify_uri": spotify.get("uri"),
        "apple_music_url": apple.get("url"),
        "album_art_url": spotify_images[0].get("url") if spotify_images else None,
    }


# ---------------------------------------------------------------------------
# ACRCloud recognition (fallback)
# ---------------------------------------------------------------------------


def recognize_acrcloud(audio_bytes: bytes) -> dict[str, Any] | None:
    """Send audio to ACRCloud API as a fallback. Returns a normalised result dict or None.

    ACRCloud uses HMAC-SHA1 request signing. Returns status code 0 on match.

    Args:
        audio_bytes: Raw mp3 audio data.

    Returns:
        Dict with title/artist/album (spotify_uri/apple_music_url/album_art_url are None
        because ACRCloud doesn't return streaming platform links by default), or None.
    """
    host = os.environ.get("ACRCLOUD_HOST", "")
    access_key = os.environ.get("ACRCLOUD_KEY", "")
    access_secret = os.environ.get("ACRCLOUD_SECRET", "")

    if not host or not access_key or not access_secret:
        logger.warning("ACRCloud credentials not configured — skipping fallback")
        return None

    http_method = "POST"
    http_uri = "/v1/identify"
    data_type = "audio"
    signature_version = "1"
    timestamp = str(time.time())

    # Build the string-to-sign per ACRCloud specification
    string_to_sign = "\n".join(
        [
            http_method,
            http_uri,
            access_key,
            data_type,
            signature_version,
            timestamp,
        ]
    )

    # HMAC-SHA1 signature — correct Python API: hmac.new(key, msg, digestmod)
    sign = base64.b64encode(
        hmac.new(
            access_secret.encode("utf-8"),
            string_to_sign.encode("utf-8"),
            digestmod=hashlib.sha1,
        ).digest()
    ).decode("utf-8")

    response = requests.post(
        f"https://{host}/v1/identify",
        files={"sample": ("audio.mp3", io.BytesIO(audio_bytes), "audio/mpeg")},
        data={
            "access_key": access_key,
            "sample_bytes": len(audio_bytes),
            "timestamp": timestamp,
            "signature": sign,
            "data_type": data_type,
            "signature_version": signature_version,
        },
        timeout=30,
    )
    response.raise_for_status()
    data = response.json()

    # ACRCloud returns status.code == 0 for a successful match
    if data.get("status", {}).get("code") != 0:
        return None

    music_list: list[dict] = data.get("metadata", {}).get("music", [])
    if not music_list:
        return None

    music = music_list[0]
    artists: list[dict] = music.get("artists", [])

    return {
        "title": music.get("title"),
        "artist": artists[0].get("name") if artists else None,
        "album": music.get("album", {}).get("name"),
        # ACRCloud doesn't return streaming platform URIs without extra config
        "spotify_uri": None,
        "apple_music_url": None,
        "album_art_url": None,
    }


# ---------------------------------------------------------------------------
# Message processor
# ---------------------------------------------------------------------------


def _now_iso() -> str:
    """Return the current UTC time as an ISO-8601 string with Z suffix."""
    return datetime.now(timezone.utc).isoformat()


def is_terminal_request_status(status: str | None) -> bool:
    """Return whether a recognition request status should not be reprocessed."""
    return status in TERMINAL_REQUEST_STATUSES


def process_message(supabase: Client, message: dict[str, Any]) -> None:
    """Process a single PGMQ message end-to-end.

    This function is intentionally synchronous so it can be safely run in a
    thread-pool executor from the asyncio poll loop, keeping the event loop
    unblocked during long ffmpeg / HTTP calls.

    Args:
        supabase: Supabase service-role client.
        message:  The ``message`` payload extracted from the PGMQ row.
    """
    request_id: str = message.get("request_id")
    station_id: str = message.get("station_id")
    stream_url: str = message.get("stream_url")

    if not request_id or not station_id or not stream_url:
        logger.warning("Malformed message payload, skipping: %s", message)
        return

    logger.info(
        "Processing recognition request %s for station %s", request_id, station_id
    )

    # Check current status first so stale requeued messages do not clobber
    # terminal states such as completed/no_match/failed.
    status_resp = (
        supabase.table("recognition_requests")
        .select("status")
        .eq("id", request_id)
        .single()
        .execute()
    )
    current_status = status_resp.data.get("status") if status_resp.data else None
    if is_terminal_request_status(current_status):
        logger.info(
            "Request %s already in terminal state '%s' — skipping (stale message)",
            request_id,
            current_status,
        )
        return

    # Mark as processing so the Flutter app can show a spinner.
    supabase.table("recognition_requests").update(
        {
            "status": "processing",
        }
    ).eq("id", request_id).execute()

    try:
        # ------------------------------------------------------------------
        # Step 1: Capture audio
        # ------------------------------------------------------------------
        logger.info("Capturing audio from %s", stream_url)
        audio_bytes = capture_audio(stream_url, duration=10)
        logger.info("Captured %d bytes of audio", len(audio_bytes))

        # ------------------------------------------------------------------
        # Step 2: Try AudD (primary)
        # ------------------------------------------------------------------
        result: dict[str, Any] | None = None
        try:
            result = recognize_audd(audio_bytes)
            if result:
                logger.info(
                    "AudD matched: %s by %s", result.get("title"), result.get("artist")
                )
        except Exception as exc:
            logger.warning("AudD failed: %s", exc)

        # ------------------------------------------------------------------
        # Step 3: ACRCloud fallback (disabled — AudD-only testing)
        # ------------------------------------------------------------------
        # Uncomment to re-enable ACRCloud as a fallback:
        # if result is None:
        #     try:
        #         result = recognize_acrcloud(audio_bytes)
        #         if result:
        #             logger.info(
        #                 "ACRCloud matched: %s by %s", result.get("title"), result.get("artist")
        #             )
        #     except Exception as exc:
        #         logger.warning("ACRCloud failed: %s", exc)

        # ------------------------------------------------------------------
        # Step 4a: No match
        # ------------------------------------------------------------------
        if result is None:
            logger.info("No match for request %s", request_id)
            supabase.table("recognition_requests").update(
                {
                    "status": "no_match",
                    "completed_at": _now_iso(),
                }
            ).eq("id", request_id).execute()
            return

        # ------------------------------------------------------------------
        # Step 4b: Match found — fetch user_id then write recognized_songs
        # ------------------------------------------------------------------
        req_response = (
            supabase.table("recognition_requests")
            .select("user_id")
            .eq("id", request_id)
            .single()
            .execute()
        )
        user_id: str = req_response.data["user_id"]

        song_row = {
            "request_id": request_id,
            "station_id": station_id,
            "title": result["title"],
            "artist": result["artist"],
            "album": result.get("album"),
            "album_art_url": result.get("album_art_url"),
            "audd_song_link": result.get("audd_song_link") or "",
            "spotify_uri": result.get("spotify_uri"),
            "apple_music_url": result.get("apple_music_url"),
        }
        try:
            supabase.table("recognized_songs").insert(song_row).execute()
        except Exception as insert_exc:
            # 23505 = unique_violation — song was already inserted by a prior attempt.
            # Treat this as idempotent success so the PGMQ message gets deleted.
            err_str = str(insert_exc)
            if "23505" in err_str or "duplicate key" in err_str.lower():
                logger.warning(
                    "recognized_songs row for request %s already exists — treating as success",
                    request_id,
                )
            else:
                raise

        # Update request to completed
        supabase.table("recognition_requests").update(
            {
                "status": "completed",
                "completed_at": _now_iso(),
            }
        ).eq("id", request_id).execute()

        # ------------------------------------------------------------------
        # Step 5: Award gamification points (direct DB insert, service role)
        # ------------------------------------------------------------------
        supabase.table("point_events").insert(
            {
                "id": str(uuid.uuid4()),
                "user_id": user_id,
                "event_type": POINT_EVENT_TYPE_DISCOVERY,
                "points": POINTS_PER_RECOGNITION,
                "reference_id": request_id,
                "metadata": {"station_id": station_id, "source": "recognition_worker"},
            }
        ).execute()

        logger.info(
            "Recognition complete for request %s: '%s' by %s",
            request_id,
            result["title"],
            result["artist"],
        )

    except Exception as exc:
        logger.error("Recognition failed for request %s: %s", request_id, exc)
        supabase.table("recognition_requests").update(
            {
                "status": "failed",
                "error_message": str(exc),
                "completed_at": _now_iso(),
            }
        ).eq("id", request_id).execute()
        # Re-raise so the poll loop knows not to delete the PGMQ message.
        raise


# ---------------------------------------------------------------------------
# Async poll loop
# ---------------------------------------------------------------------------


async def poll_loop(supabase: Client, poll_interval: float = 2.0) -> None:
    """Continuously poll the PGMQ ``song_recognition`` queue and dispatch jobs.

    Blocking work (ffmpeg + HTTP calls) is offloaded to a thread-pool executor
    so the event loop stays responsive.

    PGMQ RPC names used:
    - ``pgmq_read``   — read up to N messages with a visibility timeout
    - ``pgmq_delete`` — acknowledge a processed message

    If your Supabase installation uses schema-prefixed names (older PGMQ
    versions), change these to ``"pgmq.read"`` / ``"pgmq.delete"``.

    Args:
        supabase:      Supabase service-role client.
        poll_interval: Seconds to sleep between empty-queue polls.
    """
    logger.info("Recognition worker started, polling every %.1fs", poll_interval)
    loop = asyncio.get_event_loop()

    while True:
        try:
            response = supabase.rpc(
                "pgmq_read",
                {"queue_name": "song_recognition", "vt": 60, "qty": 1},
            ).execute()

            messages: list[dict] = response.data or []
            if not messages:
                await asyncio.sleep(poll_interval)
                continue

            for msg in messages:
                msg_id: int = msg["msg_id"]
                payload: dict[str, Any] = msg["message"]

                try:
                    # Run the blocking processor in the default thread pool
                    await loop.run_in_executor(None, process_message, supabase, payload)
                    # Only delete from the queue after successful processing
                    supabase.rpc(
                        "pgmq_delete",
                        {"queue_name": "song_recognition", "msg_id": msg_id},
                    ).execute()
                    logger.info(
                        "Deleted PGMQ message %d after successful processing", msg_id
                    )
                except Exception as exc:
                    # Leave the message in the queue — it will reappear after
                    # the 60-second visibility timeout for a retry.
                    logger.error(
                        "Failed to process msg %d: %s — will retry after VT",
                        msg_id,
                        exc,
                    )

        except Exception as exc:
            logger.error("Poll loop error: %s", exc)
            await asyncio.sleep(poll_interval)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    """Entry-point for the recognition worker."""
    supabase = get_supabase()
    asyncio.run(poll_loop(supabase))


if __name__ == "__main__":
    main()
