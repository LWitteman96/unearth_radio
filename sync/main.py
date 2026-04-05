"""
Unearth Radio — Station Sync Job

Periodic sync job that imports radio station data from the RadioBrowser
community API into the Supabase ``public.stations`` table.

Sync algorithm
──────────────
1. **Discover mirrors** — perform a DNS lookup on
   ``all.api.radio-browser.info`` to get the list of active RadioBrowser
   API mirror servers, then pick one at random.

2. **First run (full import)** — if no ``lastchangeuuid`` is stored yet,
   perform a paginated full import of every station where
   ``lastcheckok=true``.

3. **Subsequent runs (incremental diff)** — fetch only the stations that
   changed since the last sync via
   ``/json/stations/changed?lastchangeuuid={uuid}``.

4. **Upsert** — insert-or-update rows into ``public.stations`` using
   ``rb_id`` (RadioBrowser ``stationuuid``) as the conflict key.

5. **Recompute obscurity** — for every changed station, recalculate
   ``obscurity_score`` (exponential decay based on votes and click count)
   so gamification point values stay current.

6. **Populate geo column** — convert ``geo_lat`` / ``geo_lng`` into a
   PostGIS ``geography(Point, 4326)`` value using WKT
   (``SRID=4326;POINT(lng lat)``).

7. **Store changeuuid** — persist the latest ``changeuuid`` from the
   response so the next run can resume from where this one left off.

Environment variables
─────────────────────
- SUPABASE_URL / SUPABASE_SERVICE_KEY — Supabase project credentials
"""

from __future__ import annotations

import logging
import math
import os
import random
import sys
import time
from typing import Any

import dns.resolver  # dnspython
import requests
from supabase import create_client, Client

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DNS_HOST = "all.api.radio-browser.info"
PAGE_SIZE = 10000  # RadioBrowser page size for full import
BATCH_SIZE = 500  # Supabase upsert batch size
CONFIG_KEY = "last_changeuuid"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------


def compute_obscurity(vote_count: int, click_count: int) -> float:
    """Compute an obscurity score for a station.

    Score is 1.0 for a station with 0 votes+clicks; approaches 0 as
    popularity grows. Uses inverse log scale so even moderately popular
    stations score meaningfully above 0.
    """
    total = max(0, vote_count) + max(0, click_count)
    return 1.0 / (1.0 + math.log1p(total))


def discover_mirror() -> str:
    """Resolve RadioBrowser mirrors via DNS and return a base URL using the hostname."""
    import socket
    answers = dns.resolver.resolve(DNS_HOST, "A")
    ips = [r.address for r in answers]
    random.shuffle(ips)
    for ip in ips:
        try:
            hostname = socket.gethostbyaddr(ip)[0]
            return f"https://{hostname}"
        except socket.herror:
            continue
    # Fallback: use the DNS name directly (round-robins to a mirror)
    return f"https://all.api.radio-browser.info"


def build_wkt(lat: Any, lng: Any) -> str | None:
    """Build a PostGIS WKT point string from latitude and longitude.

    Returns None if coordinates are missing, non-numeric, or both zero
    (which RadioBrowser uses to indicate no geo data).
    """
    try:
        lat_f, lng_f = float(lat), float(lng)
        if lat_f == 0.0 and lng_f == 0.0:
            return None
        return f"SRID=4326;POINT({lng_f} {lat_f})"
    except (TypeError, ValueError):
        return None


def map_station(s: dict[str, Any]) -> dict[str, Any]:
    """Map a RadioBrowser station dict to a ``public.stations`` row."""
    tags_raw = s.get("tags", "") or ""
    tags = [t.strip() for t in tags_raw.split(",") if t.strip()]

    lang_raw = s.get("language", "") or ""
    language = [l.strip() for l in lang_raw.split(",") if l.strip()]

    lat = s.get("geo_lat")
    lng = s.get("geo_long")
    wkt = build_wkt(lat, lng)

    votes = int(s.get("votes") or 0)
    click_count = int(s.get("clickcount") or 0)

    row: dict[str, Any] = {
        "rb_id": s["stationuuid"],
        "name": (s.get("name") or "").strip() or "Unnamed",
        "url": s.get("url") or "",
        "url_resolved": s.get("url_resolved"),
        "country_code": s.get("countrycode"),
        "geo_lat": float(lat) if lat else None,
        "geo_lng": float(lng) if lng else None,
        "tags": tags,
        "language": language,
        "codec": s.get("codec"),
        "bitrate": int(s.get("bitrate") or 0) or None,
        "last_check_ok": bool(int(s.get("lastcheckok") or 0)),
        "votes": votes,
        "click_count": click_count,
        "favicon": s.get("favicon"),
        "homepage": s.get("homepage"),
        "obscurity_score": compute_obscurity(votes, click_count),
    }
    if wkt:
        row["geo"] = wkt
    return row


# ---------------------------------------------------------------------------
# Supabase persistence helpers
# ---------------------------------------------------------------------------


def get_last_changeuuid(client: Client) -> str | None:
    """Read the last synced changeuuid from the ``app_config`` table.

    Returns None if this is a first run (no stored value yet).
    """
    resp = client.table("app_config").select("value").eq("key", CONFIG_KEY).execute()
    if resp.data:
        return resp.data[0]["value"]
    return None


def store_changeuuid(client: Client, uuid: str) -> None:
    """Persist the latest changeuuid to ``app_config`` for the next run."""
    client.table("app_config").upsert({"key": CONFIG_KEY, "value": uuid}).execute()


def upsert_batch(client: Client, rows: list[dict[str, Any]]) -> None:
    """Upsert a batch of station rows into ``public.stations``.

    Uses ``rb_id`` as the conflict key so existing stations are updated
    rather than duplicated.
    """
    client.table("stations").upsert(rows, on_conflict="rb_id").execute()


# ---------------------------------------------------------------------------
# Sync modes
# ---------------------------------------------------------------------------


def full_import(client: Client, base_url: str) -> str | None:
    """Perform a full paginated import of all active RadioBrowser stations.

    Iterates through stations in pages of PAGE_SIZE until an empty page
    is returned. Each page is upserted in BATCH_SIZE chunks.

    Returns the latest changeuuid seen across all pages, or None if no
    stations were returned.
    """
    offset = 0
    last_uuid: str | None = None
    total = 0

    while True:
        url = f"{base_url}/json/stations"
        params = {
            "limit": PAGE_SIZE,
            "offset": offset,
            "lastcheckok": "true",
            "order": "stationuuid",
            "hidebroken": "true",
        }
        resp = requests.get(
            url,
            params=params,
            timeout=30,
            headers={"User-Agent": "Unearth-Radio-Sync/1.0"},
        )
        resp.raise_for_status()
        stations = resp.json()

        if not stations:
            break

        rows: list[dict[str, Any]] = []
        for s in stations:
            try:
                rows.append(map_station(s))
                if s.get("changeuuid"):
                    last_uuid = s["changeuuid"]
            except Exception as e:
                logger.warning("Skipping station %s: %s", s.get("stationuuid"), e)

        for i in range(0, len(rows), BATCH_SIZE):
            batch = rows[i : i + BATCH_SIZE]
            upsert_batch(client, batch)
            logger.info(
                "Full import: upserted %d stations (offset %d, batch %d)",
                len(batch),
                offset,
                i // BATCH_SIZE,
            )

        total += len(rows)
        logger.info("Full import: upserted %d stations (offset %d)", len(rows), offset)
        offset += PAGE_SIZE

        if len(stations) < PAGE_SIZE:
            # Last page — no more data
            break

        time.sleep(0.5)  # be polite to the RadioBrowser API

    logger.info("Full import complete: %d stations total", total)
    return last_uuid


def incremental_update(
    client: Client, base_url: str, last_changeuuid: str
) -> str | None:
    """Fetch and upsert only stations that changed since the last sync.

    Uses the RadioBrowser ``/json/stations/changed`` endpoint to retrieve
    a delta of changed stations since the stored changeuuid.

    Returns the new latest changeuuid if any changes were found, or None
    if there were no changes.
    """
    url = f"{base_url}/json/stations/changed"
    params = {"lastchangeuuid": last_changeuuid}
    resp = requests.get(
        url,
        params=params,
        timeout=30,
        headers={"User-Agent": "Unearth-Radio-Sync/1.0"},
    )
    resp.raise_for_status()
    stations = resp.json()

    if not stations:
        logger.info("Incremental: no changes since %s", last_changeuuid)
        return None

    rows: list[dict[str, Any]] = []
    new_uuid = last_changeuuid

    for s in stations:
        try:
            rows.append(map_station(s))
            if s.get("changeuuid"):
                new_uuid = s["changeuuid"]
        except Exception as e:
            logger.warning("Skipping station %s: %s", s.get("stationuuid"), e)

    for i in range(0, len(rows), BATCH_SIZE):
        batch = rows[i : i + BATCH_SIZE]
        upsert_batch(client, batch)
        logger.info(
            "Incremental update: upserted %d stations (offset %d)", len(batch), i
        )

    logger.info("Incremental update: upserted %d stations total", len(rows))
    return new_uuid


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    """Entry-point for the station sync job."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s — %(message)s",
    )

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")
    if not url or not key:
        logger.error("SUPABASE_URL and SUPABASE_SERVICE_KEY must be set")
        sys.exit(1)

    client = create_client(url, key)

    try:
        base_url = discover_mirror()
        logger.info("Using RadioBrowser mirror: %s", base_url)
    except Exception as e:
        logger.error("DNS discovery failed: %s", e)
        sys.exit(1)

    last_uuid = get_last_changeuuid(client)

    if last_uuid is None:
        logger.info("First run — performing full import")
        new_uuid = full_import(client, base_url)
    else:
        logger.info("Incremental run — last changeuuid: %s", last_uuid)
        new_uuid = incremental_update(client, base_url, last_uuid)

    if new_uuid:
        store_changeuuid(client, new_uuid)
        logger.info("Stored changeuuid: %s", new_uuid)

    logger.info("Sync complete")


if __name__ == "__main__":
    main()
