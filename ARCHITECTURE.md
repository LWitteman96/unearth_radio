# Unearth Radio — Architecture Design Document

> **Status:** Draft v1.0
> **Last Updated:** 2026-04-03
> **Author:** Luuk Witteman

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Component Breakdown](#2-component-breakdown)
3. [Data Flow Diagrams](#3-data-flow-diagrams)
4. [Flutter Client Architecture](#4-flutter-client-architecture)
5. [Supabase Backend Architecture](#5-supabase-backend-architecture)
6. [Recognition Worker](#6-recognition-worker)
7. [Station Sync Job](#7-station-sync-job)
8. [Security Model](#8-security-model)
9. [Scalability & Cost Model](#9-scalability--cost-model)
10. [Infrastructure & Deployment](#10-infrastructure--deployment)
11. [Key Design Decisions](#11-key-design-decisions)

---

## 1. System Overview

Unearth Radio is built on four runtime components:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          EXTERNAL SERVICES                               │
│  RadioBrowser API          AudD API            ACRCloud (fallback)       │
│  (station catalog)         (song recognition)  (recognition fallback)    │
└───────────┬────────────────────┬───────────────────────┬─────────────────┘
            │ daily sync         │ fingerprint request    │
            │                    │                        │
┌───────────▼──────┐   ┌─────────▼────────────────────────▼─────────────┐
│                  │   │                                                  │
│   Sync Worker    │   │            Recognition Worker                    │
│   (cron job)     │   │            (queue consumer)                      │
│                  │   │                                                  │
│  • DNS discovery │   │  • Polls PGMQ queue                              │
│  • Incremental   │   │  • ffmpeg stream capture                         │
│    diff via      │   │  • Cache check (2–3 min window)                  │
│    lastchangeuuid│   │  • AudD API call                                 │
│  • Upsert into   │   │  • Stores result → triggers Realtime             │
│    stations      │   │                                                  │
└───────────┬──────┘   └──────────────────────┬───────────────────────────┘
            │                                  │
            │ writes                           │ reads queue / writes results
            │                                  │
┌───────────▼──────────────────────────────────▼───────────────────────────┐
│                                                                           │
│                             SUPABASE                                      │
│                                                                           │
│  ┌─────────────┐  ┌────────────┐  ┌───────────┐  ┌────────────────────┐  │
│  │    Auth     │  │ PostgreSQL │  │  Realtime │  │  Edge Functions    │  │
│  │ Google SSO  │  │ + PostGIS  │  │ (WebSocket│  │  (Deno/TypeScript) │  │
│  │ Magic Link  │  │ + PGMQ     │  │  push)    │  │  point scoring     │  │
│  └─────────────┘  └────────────┘  └───────────┘  └────────────────────┘  │
│                                                                           │
│  ┌─────────────┐                                                          │
│  │   Storage   │                                                          │
│  │  album art  │                                                          │
│  │  station    │                                                          │
│  │  logos      │                                                          │
│  └─────────────┘                                                          │
│                                                                           │
└───────────────────────────────────────┬───────────────────────────────────┘
                                        │ REST + WebSocket
                                        │
                        ┌───────────────▼───────────────┐
                        │                               │
                        │       Flutter Client          │
                        │    (iOS / Android / Web)      │
                        │                               │
                        │  Riverpod state management    │
                        │  just_audio (ICY metadata)    │
                        │  Supabase Dart SDK            │
                        │                               │
                        └───────────────────────────────┘
```

### Component Roles at a Glance

| Component | Runtime | Responsibility |
|---|---|---|
| **Flutter Client** | iOS / Android / Web | UI, audio playback, ICY metadata, user interactions |
| **Supabase** | Managed cloud | Auth, database, Realtime push, Edge Functions, Storage |
| **Recognition Worker** | Docker container (any cloud) | ffmpeg audio capture, AudD API calls, result storage |
| **Sync Worker** | Docker container / cron | RadioBrowser → Postgres station catalog sync |

---

## 2. Component Breakdown

### 2.1 Flutter Client

The single codebase that runs on iOS, Android, and web. It is the only surface users directly interact with.

**Responsibilities:**
- Authenticate users via Supabase Auth (Google SSO, Magic Link)
- Browse and search the station catalog (queries Supabase Postgres directly via the Dart SDK)
- Stream radio audio (via `just_audio` or `audio_service`)
- Parse ICY metadata from the audio stream for automatic "now playing" display
- Enqueue song recognition requests into PGMQ via Supabase RPC
- Subscribe to `recognition_requests` via Supabase Realtime to receive results
- Manage playlists (CRUD on Supabase tables)
- Display gamification points, leaderboard, listening stats
- Open song deep links to Spotify / Apple Music / YouTube Music (no auth — deep link only)

**What it does NOT do:**
- Call AudD directly (only the worker does)
- Write to `stations` (sync worker only)
- Award points (Edge Functions only)

---

### 2.2 Supabase

The managed backend. Zero servers to operate.

| Service | Role |
|---|---|
| **Auth** | Issues JWTs for Google SSO and Magic Link. JWT is included in every Supabase request, enabling RLS enforcement. |
| **PostgreSQL + PostGIS** | Primary datastore. All tables, indexes, views, RLS policies, and PGMQ queues live here. |
| **PGMQ** | Postgres-native durable queue for the recognition pipeline. Flutter client enqueues; Recognition Worker dequeues. |
| **Realtime** | WebSocket-based change data capture. Flutter client subscribes to its own `recognition_requests` rows; gets push notification when `status` → `'completed'`. |
| **Edge Functions** | Deno (TypeScript) serverless functions. Invoked server-side for business logic that must not live in the client (point awarding, leaderboard rollups). |
| **Storage** | Object store for album art and station favicon caching, reducing external image load times. |

---

### 2.3 Recognition Worker

A stateless, containerised service that processes song recognition jobs from the PGMQ queue.

**Responsibilities:**
1. Poll `song_recognition` PGMQ queue for pending jobs
2. Check recognition result cache (recent result for same station within ~2–3 min window)
3. Capture ~10 seconds of audio from the station stream URL via `ffmpeg`
4. POST audio to AudD API; fall back to ACRCloud on failure
5. Write result to `recognized_songs` and update `recognition_requests.status`
6. Trigger point award via Supabase Edge Function
7. Acknowledge (delete) message from queue on success; let it expire on failure for retry

**Language:** Python (proven in prior implementation with `ffmpeg-python`)

**Deployment:** Single Docker container, horizontally scalable. Stateless — each instance independently polls the queue.

---

### 2.4 Sync Worker

A cron-scheduled job that keeps the local station catalog up to date with RadioBrowser.

**Responsibilities:**
1. Discover active RadioBrowser API mirrors via DNS lookup of `all.api.radio-browser.info`
2. On first run: paginated full import of all `lastcheckok=true` stations
3. On subsequent runs: incremental diff via `/json/stations/changed?lastchangeuuid={uuid}`
4. Upsert into `public.stations` on `rb_id` conflict
5. Recompute `obscurity_score` for changed stations
6. Populate `geo` (PostGIS) column from `geo_lat`/`geo_lng` on upsert
7. Store latest `changeuuid` for the next incremental sync

**Schedule:** Daily (24h cadence is acceptable — station metadata rarely changes hourly)

**Language:** Python or TypeScript (can be a Supabase Edge Function on a cron schedule, or a standalone Docker container)

---

## 3. Data Flow Diagrams

### 3.1 User Authentication

```
User opens app
    │
    ├─ "Sign in with Google"
    │       │
    │       ▼
    │   Supabase Auth → Google OAuth2
    │       │
    │       ▼
    │   JWT issued → stored in Flutter secure storage
    │       │
    │       ▼
    │   auth.users row created
    │       │
    │       ▼ (Postgres trigger: handle_new_auth_user)
    │   public.users row auto-created with display_name + avatar_url
    │
    └─ "Sign in with Email" (Magic Link)
            │
            ▼
        Supabase Auth sends magic link email
            │
            ▼
        User clicks link → JWT issued → same flow as above
```

---

### 3.2 Station Discovery & Playback

```
User opens Station Browser
    │
    ▼
Flutter → Supabase Postgres query
  SELECT * FROM stations
  WHERE tags @> '{rock}'          -- GIN index
    AND last_check_ok = true
  ORDER BY obscurity_score DESC   -- btree index
  LIMIT 50
    │
    ▼
Station list rendered in Flutter UI
    │
User taps a station
    │
    ▼
Flutter calls RadioBrowser click endpoint (courtesy)
  GET /json/url/{stationuuid}
    │
    ▼
just_audio begins streaming station URL
  HTTP request includes: Icy-MetaData: 1
    │
    ├─ Server returns icy-metaint header?
    │       │
    │       YES → ICY metadata parsed from stream
    │               StreamTitle updates shown automatically
    │               ("Now Playing: Artist - Title")
    │
    └─ No ICY metadata (or HLS stream)
            │
            └─ "Identify" button shown to user
```

---

### 3.3 Song Recognition Pipeline (Full)

```
┌────────────────────────────────────────────────────────────────────────┐
│  FLUTTER CLIENT                                                        │
│                                                                        │
│  User taps "Identify"                                                  │
│      │                                                                 │
│      ▼                                                                 │
│  Create recognition_requests row (status='pending')                    │
│      │                                                                 │
│      ▼                                                                 │
│  Subscribe to Realtime on that row's id                                │
│      │                                                                 │
│      ▼                                                                 │
│  Enqueue via PGMQ RPC:                                                 │
│    pgmq.send('song_recognition', {                                     │
│      request_id, station_id, station_url, user_id,                     │
│      duration_seconds: 10                                              │
│    })                                                                  │
│      │                                                                 │
│      ▼                                                                 │
│  Show loading spinner                                                  │
└────────────────────────────────┬───────────────────────────────────────┘
                                 │ PGMQ message visible
                                 │
┌────────────────────────────────▼───────────────────────────────────────┐
│  RECOGNITION WORKER                                                    │
│                                                                        │
│  Polls queue: pgmq.read('song_recognition', vt=60, qty=1)             │
│      │                                                                 │
│      ▼                                                                 │
│  Update recognition_requests.status = 'processing'                    │
│      │                                                                 │
│      ▼                                                                 │
│  Cache check: recent recognized_songs for same station_id              │
│  within last 2–3 minutes?                                              │
│      │                                                                 │
│      ├─ CACHE HIT → use existing recognized_songs row                  │
│      │       │                                                         │
│      │       ▼                                                         │
│      │   Update recognition_requests:                                  │
│      │     status='completed', completed_at=now()                     │
│      │     (link to cached recognized_songs row)                       │
│      │                                                                 │
│      └─ CACHE MISS → proceed with capture                             │
│              │                                                         │
│              ▼                                                         │
│          ffmpeg captures ~10s audio from station_url                   │
│              │                                                         │
│              ▼                                                         │
│          POST audio to AudD API                                        │
│              │                                                         │
│              ├─ AudD success → parse result                            │
│              │                                                         │
│              └─ AudD failure → retry with ACRCloud                     │
│                      │                                                 │
│              ┌───────▼──────────────────────────────────┐             │
│              │  result = { title, artist, album,         │             │
│              │    isrc, spotify_uri, apple_music_url,    │             │
│              │    album_art_url, raw_response, ... }     │             │
│              └───────┬──────────────────────────────────┘             │
│                      │                                                 │
│                      ▼                                                 │
│          INSERT into recognized_songs                                  │
│          UPDATE recognition_requests:                                  │
│            status='completed' | 'no_match' | 'failed'                 │
│            completed_at=now()                                          │
│                      │                                                 │
│                      ▼                                                 │
│          Call Edge Function: award_points({user_id, event_data})       │
│                      │                                                 │
│                      ▼                                                 │
│          pgmq.delete('song_recognition', msg_id) — acknowledge         │
└──────────────────────┬─────────────────────────────────────────────────┘
                       │ Postgres row updated → Realtime event fires
                       │
┌──────────────────────▼─────────────────────────────────────────────────┐
│  FLUTTER CLIENT                                                        │
│                                                                        │
│  Realtime push received (recognition_requests status changed)          │
│      │                                                                 │
│      ▼                                                                 │
│  Fetch recognized_songs row for this request_id                        │
│      │                                                                 │
│      ▼                                                                 │
│  Display: album art, title, artist, Spotify / Apple Music buttons      │
│           "Save to playlist" button                                    │
│           Points earned notification                                   │
└────────────────────────────────────────────────────────────────────────┘
```

---

### 3.4 Station Catalog Sync

```
Cron schedule fires (daily)
    │
    ▼
Sync Worker starts
    │
    ▼
DNS lookup: all.api.radio-browser.info
→ returns list of mirror IPs
→ randomise + pick first available
    │
    ▼
Load last stored changeuuid from Supabase
(or null on first run)
    │
    ├─ First run (no changeuuid)?
    │       │
    │       ▼
    │   Paginated full import:
    │   GET /json/stations?lastcheckok=1&limit=10000&offset={n}
    │   Repeat until all ~53k stations fetched
    │
    └─ Subsequent run
            │
            ▼
        Incremental diff:
        GET /json/stations/changed?lastchangeuuid={uuid}
        → only changed/new stations since last sync
            │
            ▼
        For each station:
          • Build geo = ST_MakePoint(geo_lng, geo_lat)
          • Compute obscurity_score
          • UPSERT on rb_id conflict
            │
            ▼
        Store latest changeuuid
            │
            ▼
        Sync complete — log stats (upserted, skipped, errors)
```

---

### 3.5 Point Awarding

```
Recognition Worker calls Edge Function after successful recognition:
  POST /functions/v1/award-points
  {
    user_id, event_type: 'discovery',
    station_id, recognized_song_id
  }
    │
    ▼
Edge Function (runs as service role — bypasses RLS):
    │
    ├─ Calculate base points (discovery: fixed value)
    ├─ Calculate distance bonus:
    │     ST_Distance(user.geo, station.geo) → km → points scale
    ├─ Calculate obscurity bonus:
    │     station.obscurity_score → multiplier
    │
    ▼
INSERT into point_events (user_id, event_type, points, metadata)
    │
    ▼ (Postgres trigger: sync_user_total_points)
UPDATE users SET total_points = total_points + {points}
    │
    ▼
Return awarded points to Worker → Worker relays to client
```

---

## 4. Flutter Client Architecture

### 4.1 Package Structure

```
lib/
├── main.dart                    # App entry point, ProviderScope
├── app.dart                     # MaterialApp, router setup
│
├── core/
│   ├── supabase/
│   │   └── supabase_client.dart # Singleton Supabase client init
│   ├── router/
│   │   └── app_router.dart      # go_router route definitions
│   ├── theme/
│   │   └── app_theme.dart       # Pastel earthy colour palette, typography
│   └── utils/
│       └── icy_metadata_parser.dart  # ICY StreamTitle parser utility
│
├── features/
│   ├── auth/
│   │   ├── providers/
│   │   │   └── auth_provider.dart
│   │   └── screens/
│   │       └── login_screen.dart
│   │
│   ├── stations/
│   │   ├── providers/
│   │   │   ├── station_list_provider.dart   # Paginated station query
│   │   │   └── station_detail_provider.dart
│   │   ├── screens/
│   │   │   ├── station_browser_screen.dart
│   │   │   └── station_detail_screen.dart
│   │   └── widgets/
│   │       └── station_card.dart
│   │
│   ├── player/
│   │   ├── providers/
│   │   │   ├── player_provider.dart         # just_audio wrapper + ICY
│   │   │   └── now_playing_provider.dart    # ICY StreamTitle state
│   │   └── screens/
│   │       └── player_screen.dart
│   │
│   ├── recognition/
│   │   ├── providers/
│   │   │   └── recognition_provider.dart    # PGMQ enqueue + Realtime sub
│   │   └── widgets/
│   │       └── identify_button.dart
│   │
│   ├── playlists/
│   │   ├── providers/
│   │   │   ├── playlist_list_provider.dart
│   │   │   └── playlist_detail_provider.dart
│   │   └── screens/
│   │       ├── playlists_screen.dart
│   │       └── playlist_detail_screen.dart
│   │
│   └── profile/
│       ├── providers/
│       │   ├── user_provider.dart
│       │   └── leaderboard_provider.dart
│       └── screens/
│           ├── profile_screen.dart
│           └── leaderboard_screen.dart
│
└── shared/
    ├── models/                  # Dart model classes (fromJson/toJson)
    │   ├── station.dart
    │   ├── recognized_song.dart
    │   ├── playlist.dart
    │   └── user.dart
    └── widgets/                 # Shared UI components
        ├── loading_spinner.dart
        └── error_view.dart
```

### 4.2 State Management — Riverpod

All async state is managed via Riverpod providers. Key patterns:

| Provider Type | Used For |
|---|---|
| `StreamProvider` | Supabase Realtime subscriptions (recognition results, auth state) |
| `FutureProvider` | One-off data fetches (station detail, playlist contents) |
| `AsyncNotifierProvider` | Paginated lists with load-more (station browser) |
| `NotifierProvider` | Synchronous local state (player state, UI toggles) |

**Example — Recognition flow:**

```dart
// recognition_provider.dart
@riverpod
class RecognitionNotifier extends _$RecognitionNotifier {
  @override
  AsyncValue<RecognizedSong?> build() => const AsyncValue.data(null);

  Future<void> identify(String stationId, String stationUrl) async {
    state = const AsyncValue.loading();

    // 1. Insert recognition_requests row
    final requestId = await _createRequest(stationId);

    // 2. Enqueue into PGMQ
    await _enqueue(requestId, stationId, stationUrl);

    // 3. Subscribe to Realtime for this request
    _subscribeToResult(requestId);
  }

  void _subscribeToResult(String requestId) {
    supabase
      .from('recognition_requests')
      .stream(primaryKey: ['id'])
      .eq('id', requestId)
      .listen((rows) async {
        if (rows.isEmpty) return;
        final row = rows.first;
        if (row['status'] == 'completed') {
          final song = await _fetchSong(requestId);
          state = AsyncValue.data(song);
        } else if (row['status'] == 'failed') {
          state = AsyncValue.error('Recognition failed', StackTrace.current);
        }
      });
  }
}
```

### 4.3 Audio & ICY Metadata

`just_audio` is the primary audio plugin. It supports ICY metadata natively on iOS and Android via the `IcyMetadata` class exposed through `AudioPlayer.icyMetadata`.

```dart
// now_playing_provider.dart (simplified)
@riverpod
Stream<String?> nowPlayingTitle(NowPlayingTitleRef ref) {
  final player = ref.watch(audioPlayerProvider);
  return player.icyMetadata
    .map((meta) => meta?.info?.title); // e.g. "Daft Punk - Get Lucky"
}
```

HLS stations return `null` for ICY metadata — the UI automatically shows the "Identify" button in that case.

---

## 5. Supabase Backend Architecture

### 5.1 Database Schema Summary

```
auth.users (Supabase managed)
    │ 1:1 (trigger)
    ▼
public.users ──────────────────────────────────────────────────────┐
    │                                                               │
    ├─ 1:N ──► playlists ──── M:N (playlist_songs) ──► recognized_songs
    │                                                       │
    ├─ 1:N ──► recognition_requests ──────── 1:1 ──────────┘
    │               │ (session_id FK)
    │               ▼
    ├─ 1:N ──► listening_sessions
    │
    ├─ 1:N ──► point_events
    │
    ├─ 1:N ──► station_votes ──────┐
    │                               │
    ├─ 1:N ──► station_shares ─────┤──► stations (synced from RadioBrowser)
    │                               │
    └─ M:N ──► friendships          │
                                    │
        recognition_requests ───────┘
        recognized_songs ───────────┘
        listening_sessions ─────────┘
```

### 5.2 Row Level Security Strategy

RLS is the primary access control layer. Every table has RLS enabled.

**Three role tiers:**

| Role | Who | Access |
|---|---|---|
| `anon` | Unauthenticated users | None (all tables require auth) |
| `authenticated` | Logged-in app users | Their own data + public data (via policies) |
| `service_role` | Workers, Edge Functions | Full access (bypasses RLS) |

**Critical patterns:**

- **Own-data access:** `auth.uid() = user_id` on select/update
- **Public read:** `is_public = true` on playlists, leaderboard view
- **Server-only writes:** `recognized_songs`, `point_events`, `stations` are insert/update restricted to `service_role` only
- **Bidirectional social:** `auth.uid() in (requester_id, addressee_id)` for friendships and shares

### 5.3 Edge Functions

Deno-based serverless functions for server-side business logic:

| Function | Trigger | Responsibility |
|---|---|---|
| `award-points` | Called by Recognition Worker | Calculate and insert `point_events`, update `users.total_points` |
| `leaderboard-rollup` | Cron (hourly) | Refresh materialised leaderboard data if needed |
| `station-click` | Called by Flutter client | Forward click to RadioBrowser `/json/url/{stationuuid}` (community courtesy) |

Edge Functions run with `service_role` credentials, allowing them to bypass RLS and write to restricted tables.

### 5.4 Realtime Subscriptions

The Flutter client opens one persistent WebSocket to Supabase for all Realtime subscriptions.

| Channel | Filter | Used For |
|---|---|---|
| `recognition_requests` | `id=eq.{requestId}` | Song recognition result delivery |

The `recognition_requests` table is added to the `supabase_realtime` Postgres publication in migration `0005`. Only rows relevant to the current user's pending requests are subscribed to — not a broadcast channel.

### 5.5 Storage Buckets

| Bucket | Contents | Access |
|---|---|---|
| `album-art` | AudD-returned album artwork, cached after first recognition | Public read, service_role write |
| `station-logos` | Station favicon images, cached from RadioBrowser | Public read, service_role write |

Images are cached on first encounter to reduce latency and external dependency.

---

## 6. Recognition Worker

### 6.1 Runtime & Dependencies

| Dependency | Version | Purpose |
|---|---|---|
| Python | 3.11+ | Runtime |
| `ffmpeg-python` | latest | Audio stream capture wrapper |
| `ffmpeg` | 6.x | Binary — capture radio audio |
| `httpx` | latest | Async HTTP client for AudD API calls |
| `supabase-py` | latest | Supabase client (queue + DB) |
| `python-dotenv` | latest | Environment config |

### 6.2 Worker Loop

```python
# Simplified worker loop pseudocode

async def run_worker():
    while True:
        # Poll queue (visibility timeout = 60s)
        messages = await pgmq.read('song_recognition', vt=60, qty=1)

        if not messages:
            await asyncio.sleep(2)   # Back off when queue is empty
            continue

        msg = messages[0]
        job = msg['message']

        try:
            await process_job(job)
            await pgmq.delete('song_recognition', msg['msg_id'])
        except Exception as e:
            # Do NOT delete — message re-appears after 60s VT for retry
            log.error(f"Job failed: {e}")

async def process_job(job):
    request_id = job['request_id']
    station_url = job['station_url']
    station_id  = job['station_id']
    user_id     = job['user_id']

    # 1. Mark as processing
    await update_status(request_id, 'processing')

    # 2. Cache check — recent result for same station?
    cached = await get_cached_result(station_id, window_minutes=3)
    if cached:
        await link_cached_result(request_id, cached['id'])
        await update_status(request_id, 'completed')
        await award_points(user_id, station_id, cached['id'])
        return

    # 3. Capture audio via ffmpeg
    audio_bytes = await capture_audio(station_url, duration_seconds=10)

    # 4. Recognise with AudD (fallback to ACRCloud)
    result = await recognise(audio_bytes)

    # 5. Store result
    if result:
        song_id = await insert_recognized_song(result, request_id, station_id)
        await update_status(request_id, 'completed', completed_at=now())
        await award_points(user_id, station_id, song_id)
    else:
        await update_status(request_id, 'no_match', completed_at=now())
```

### 6.3 ffmpeg Capture

```python
async def capture_audio(stream_url: str, duration_seconds: int = 10) -> bytes:
    """Capture N seconds of audio from a radio stream URL."""
    process = await asyncio.create_subprocess_exec(
        'ffmpeg',
        '-i', stream_url,
        '-t', str(duration_seconds),
        '-f', 'mp3',           # AudD accepts MP3
        '-ab', '128k',
        'pipe:1',              # Output to stdout
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    audio_bytes, _ = await asyncio.wait_for(
        process.communicate(),
        timeout=duration_seconds + 10   # Grace period for stream connect
    )
    return audio_bytes
```

### 6.4 AudD API Call

```python
async def call_audd(audio_bytes: bytes) -> dict | None:
    async with httpx.AsyncClient() as client:
        response = await client.post(
            'https://api.audd.io/',
            data={'api_token': AUDD_API_TOKEN, 'return': 'spotify,apple_music,deezer'},
            files={'file': ('audio.mp3', audio_bytes, 'audio/mpeg')},
            timeout=30,
        )
    data = response.json()
    if data.get('status') == 'success' and data.get('result'):
        return data['result']
    return None   # No match or error → triggers ACRCloud fallback
```

### 6.5 Cache Check

```python
async def get_cached_result(station_id: str, window_minutes: int = 3) -> dict | None:
    cutoff = datetime.utcnow() - timedelta(minutes=window_minutes)
    rows = await supabase.table('recognized_songs') \
        .select('*') \
        .eq('station_id', station_id) \
        .gte('recognized_at', cutoff.isoformat()) \
        .order('recognized_at', desc=True) \
        .limit(1) \
        .execute()
    return rows.data[0] if rows.data else None
```

### 6.6 Retry & Error Handling

| Scenario | Behaviour |
|---|---|
| ffmpeg fails to connect to stream | Exception raised → message NOT deleted → re-queued after 60s VT |
| AudD API timeout / error | Falls back to ACRCloud; if both fail → status `'failed'` |
| AudD returns no match | Status set to `'no_match'` (not an error) → message deleted |
| Worker crashes mid-job | Message visibility timeout expires (60s) → message re-queued automatically |
| Persistent failures | After N retries (tracked in `recognition_requests.error_message`), worker sets status `'failed'` |

---

## 7. Station Sync Job

### 7.1 Incremental Sync Algorithm

```python
async def sync_stations():
    # 1. Discover mirror
    servers = await dns_lookup('all.api.radio-browser.info')
    server = random.choice(servers)
    base_url = f'https://{server}'

    # 2. Load last changeuuid from Supabase
    last_uuid = await get_last_changeuuid()

    if last_uuid is None:
        # First run — full import
        await full_import(base_url)
    else:
        # Incremental diff
        await incremental_sync(base_url, last_uuid)

async def incremental_sync(base_url: str, last_uuid: str):
    url = f'{base_url}/json/stations/changed?lastchangeuuid={last_uuid}'
    stations = await fetch_json(url)

    for batch in chunked(stations, size=500):
        rows = [transform(s) for s in batch]
        await supabase.table('stations').upsert(rows, on_conflict='rb_id').execute()

    if stations:
        await store_last_changeuuid(stations[-1]['changeuuid'])
```

### 7.2 Obscurity Score Calculation

The `obscurity_score` is a normalised value between 0 and 1 where higher = more obscure (= more points for gamification).

```python
def compute_obscurity_score(station: dict) -> float:
    """
    Obscurity is inversely proportional to votes and click count.
    Stations with very few votes and clicks in low-population countries
    score highest.
    """
    votes      = max(station.get('votes', 0), 0)
    clicks     = max(station.get('click_count', 0), 0)

    # Exponential decay — drops quickly for popular stations
    vote_score  = math.exp(-votes / 100)     # 0 votes → 1.0, 100 votes → 0.37
    click_score = math.exp(-clicks / 1000)   # 0 clicks → 1.0, 1000 → 0.37

    return round((vote_score * 0.6 + click_score * 0.4), 4)
```

### 7.3 Geo Column Population

```python
def transform(station: dict) -> dict:
    lat = station.get('geo_lat')
    lng = station.get('geo_long')

    return {
        'rb_id':             station['stationuuid'],
        'name':              station['name'],
        'url':               station['url'],
        'url_resolved':      station.get('url_resolved'),
        'geo_lat':           lat,
        'geo_lng':           lng,
        # PostGIS WKT point — Supabase auto-parses this into geography type
        'geo':               f'SRID=4326;POINT({lng} {lat})' if lat and lng else None,
        'tags':              [t.strip() for t in station.get('tags', '').split(',') if t.strip()],
        'has_extended_info': station.get('has_extended_info', False),
        'hls':               bool(station.get('hls', 0)),
        'votes':             station.get('votes', 0),
        'click_count':       station.get('clickcount', 0),
        'click_trend':       station.get('clicktrend', 0),
        'codec':             station.get('codec'),
        'bitrate':           station.get('bitrate'),
        'obscurity_score':   compute_obscurity_score(station),
        'synced_at':         datetime.utcnow().isoformat(),
    }
```

---

## 8. Security Model

### 8.1 Authentication & JWT

Every request from the Flutter client to Supabase includes a JWT issued by Supabase Auth. The JWT contains `sub` (= `auth.uid()`), which all RLS policies use to scope data to the requesting user.

Workers and Edge Functions use the `service_role` key (a static secret) which bypasses RLS entirely. This key is **never exposed to the client**.

### 8.2 Secret Management

| Secret | Where Stored | Who Uses It |
|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Worker env vars (Docker secrets / cloud secret store) | Recognition Worker, Sync Worker |
| `AUDD_API_TOKEN` | Worker env vars | Recognition Worker |
| `ACRCLOUD_*` | Worker env vars | Recognition Worker (fallback) |
| `SUPABASE_ANON_KEY` | Flutter app bundle (public) | Flutter client — safe to expose |
| `SUPABASE_URL` | Flutter app bundle (public) | Flutter client — safe to expose |

The `anon` key is safe to ship in the client because RLS prevents it from accessing any data beyond what policies allow.

### 8.3 Client-Side Trust Boundary

The Flutter client is **untrusted**:
- Cannot write to `stations`, `recognized_songs`, or `point_events` (RLS blocks it)
- Cannot award its own points (Edge Functions run server-side)
- Cannot read other users' private data (RLS own-data policies)
- Cannot enqueue jobs on behalf of other users (`user_id` is validated via `auth.uid()` in the INSERT policy on `recognition_requests`)

---

## 9. Scalability & Cost Model

### 9.1 Traffic Assumptions (MVP)

| Metric | Assumption |
|---|---|
| MAU | 1,000–10,000 users |
| Daily active sessions | 200–2,000 |
| Recognitions per DAU | ~3 |
| Daily recognition requests | 600–6,000 |

### 9.2 AudD API Cost Projection

| Tier | Daily requests | Monthly requests | AudD cost/month |
|---|---|---|---|
| Early (1k MAU) | ~600 | ~18,000 | ~$90 |
| Growing (10k MAU) | ~3,000 | ~90,000 | ~$450 |
| Cache hit rate ~40% applied | — | ~54,000 effective | ~$270 |

The freemium cap (e.g. 20 free recognitions/user/month) puts a hard ceiling on API spend until paid subscribers cover the cost.

### 9.3 Supabase Cost Projection

Supabase Pro plan ($25/month) is sufficient for MVP:
- 8 GB database (stations ~53k rows ≈ 50 MB; all other tables combined are small at MVP scale)
- 50,000 MAU auth limit
- 500 GB bandwidth
- Realtime and Edge Functions included

### 9.4 Recognition Worker Scaling

The worker is stateless and horizontally scalable. PGMQ's visibility timeout prevents duplicate processing:

- **1 worker instance:** Handles ~30 recognitions/minute (10s capture + 2s AudD latency + overhead)
- **Scale trigger:** Queue depth > 20 messages → spin up additional worker instance
- **MVP:** 1 worker instance is more than sufficient

### 9.5 Station Sync Scaling

The sync job runs once daily and is not latency-sensitive. A single small container (0.25 vCPU, 512 MB RAM) handles the full incremental sync in under a minute.

---

## 10. Infrastructure & Deployment

### 10.1 Overview

```
┌─────────────────────────────────────────────────────────┐
│  Supabase Cloud (managed)                               │
│  • PostgreSQL + PostGIS + PGMQ + RLS                   │
│  • Auth                                                 │
│  • Realtime                                             │
│  • Edge Functions                                       │
│  • Storage                                              │
└─────────────────────────────────────────────────────────┘

┌──────────────────────────────┐  ┌──────────────────────┐
│  Recognition Worker          │  │  Sync Worker (cron)  │
│  Docker container            │  │  Docker container    │
│                              │  │  or Edge Function    │
│  Railway / Render / Fly.io   │  │  on Supabase cron    │
└──────────────────────────────┘  └──────────────────────┘

┌──────────────────────────────────────────────────────────┐
│  Flutter App                                             │
│  Distributed via App Store (iOS) + Google Play (Android) │
│  + web hosting (Vercel / Netlify) for web               │
└──────────────────────────────────────────────────────────┘
```

### 10.2 Worker Hosting Options

The Recognition Worker needs persistent execution (not serverless) because:
1. It runs a long-polling loop
2. It invokes `ffmpeg` as a subprocess
3. Cold starts would add unacceptable latency

**Recommended for MVP:** [Railway](https://railway.app) or [Render](https://render.com)

| Option | Pros | Cons |
|---|---|---|
| **Railway** | Simple Docker deploy, auto-scaling, reasonable pricing | Vendor lock-in |
| **Render** | Free tier available, simple Docker, persistent workers | Slower cold starts on free tier |
| **Fly.io** | Global edge deployment, good Docker support | Slightly more config |
| **AWS ECS / GCP Cloud Run** | Enterprise-grade, auto-scaling | Overkill for MVP |

### 10.3 Sync Worker Hosting Options

The Sync Worker runs once daily and exits. Two viable approaches:

**Option A — Supabase Edge Function with pg_cron:**
- Supabase supports `pg_cron` to schedule SQL or Edge Function calls
- Zero additional infrastructure
- Limitation: Edge Functions have a 150s execution timeout — fine for incremental syncs, may be tight for the initial full import

**Option B — Docker container on Railway/Render with a cron schedule:**
- No timeout constraints
- Required for the first full import of ~53k stations
- Can be the same image as the Recognition Worker with a different entrypoint

**Recommended:** Option B for the initial import, then switch to Option A (pg_cron + Edge Function) for daily incremental syncs.

### 10.4 Environment Variables

**Recognition Worker:**
```
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
AUDD_API_TOKEN=your-audd-token
ACRCLOUD_HOST=identify-eu-west-1.acrcloud.com
ACRCLOUD_ACCESS_KEY=...
ACRCLOUD_ACCESS_SECRET=...
RECOGNITION_QUEUE_NAME=song_recognition
RECOGNITION_QUEUE_VT=60
CACHE_WINDOW_MINUTES=3
LOG_LEVEL=INFO
```

**Sync Worker:**
```
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
RADIOBROWSER_USER_AGENT=UnearthRadio/1.0 (contact@unearthradio.com)
SYNC_BATCH_SIZE=500
LOG_LEVEL=INFO
```

**Flutter (compile-time, via `--dart-define` or `.env`):**
```
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
```

### 10.5 Deployment Checklist (MVP)

- [ ] Supabase project created, extensions enabled (PostGIS, pgmq)
- [ ] All 12 migrations applied via `supabase db push`
- [ ] Google OAuth app created in Google Cloud Console, client ID added to Supabase Auth
- [ ] AudD API token purchased and stored as worker secret
- [ ] Recognition Worker Docker image built and deployed
- [ ] Sync Worker run once manually for initial station import
- [ ] Sync Worker scheduled for daily cron
- [ ] Flutter app configured with `SUPABASE_URL` + `SUPABASE_ANON_KEY`
- [ ] App submitted to App Store / Google Play

---

## 11. Key Design Decisions

### 11.1 Why Supabase over Custom Backend

A custom backend (Node.js/Fastify, AWS, etc.) would require building and operating auth, RLS, Realtime, and a queue from scratch. Supabase provides all of these as a managed service, reducing operational overhead from weeks to hours. The previous prototype's separation-of-concerns (Gateway → Balancer → Worker) is preserved without the Node.js glue code.

### 11.2 Why PGMQ over External Queue

PGMQ lives in Postgres, which is already the primary datastore. No additional infrastructure (Redis, Kafka, RabbitMQ) is needed. The recognition pipeline's throughput requirements (hundreds of messages/day at MVP scale) are well within Postgres's capabilities. Migrating to a dedicated queue is straightforward if throughput ever demands it.

### 11.3 Why Stateless Worker over Edge Functions

Song recognition requires `ffmpeg` — a native binary — which cannot run inside Supabase Edge Functions (Deno runtime, no native binary support). A long-running containerised worker is the natural fit. Edge Functions are used for pure business logic (point awarding) where Deno's capabilities are sufficient.

### 11.4 Why ICY Metadata over Always-On Fingerprinting

Continuous stream monitoring (AudD Streams API at $45/stream/month, or similar services like WARM) is designed for broadcast analytics and airplay tracking — not per-user "now playing" display. At 53,000+ stations, continuous monitoring would cost ~$2.4M/month. ICY metadata is free, real-time, and available for ~40–50% of stations. AudD fingerprinting fills the gap on-demand at $0.005/request.

### 11.5 Why PostGIS over Application-Level Haversine

Distance-based gamification scoring is a core P1 feature. Computing `ST_Distance(user_geo, station_geo)` in a single SQL call scales to millions of stations without loading coordinates into memory. The GIST spatial index makes distance queries orders of magnitude faster than table scans with Haversine in application code.

### 11.6 Why Denormalised Song Storage

`recognized_songs` stores artist and album as plain text rather than normalising into separate `artists` and `albums` tables. AudD returns these as free-form strings with no canonical ID, making normalisation fragile (fuzzy matching, Unicode variants). The ISRC field serves as a reliable deduplication key when needed. Aggregation queries (`GROUP BY artist`) perform acceptably at MVP scale. Revisit if artist profile pages are built in P2+.

---

*This document reflects the full architecture as of v1.0. It should be updated when significant infrastructure or design decisions change.*
