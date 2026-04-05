# Unearth Radio — Product Requirements Document

> **Status:** Draft v1.0
> **Last Updated:** 2026-04-03
> **Author:** Luuk Witteman

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Vision & Goals](#2-vision--goals)
3. [Target Audience](#3-target-audience)
4. [Feature Requirements](#4-feature-requirements)
5. [Technical Architecture](#5-technical-architecture)
6. [Open Questions](#6-open-questions)
7. [Design Direction](#7-design-direction)
8. [Previous Implementation Reference](#8-previous-implementation-reference)

---

## 1. Product Overview

**Unearth Radio** is a radio discovery app that allows users to find radio stations all across the globe by various tags, mostly genres. The goal is for users to discover curated radio playlists of their favorite music genres in places they would've never thought to look.

The app combines a modern radio listening experience with gamification to keep users engaged and sharing with friends. Users can tune into stations worldwide, recognize songs playing on those stations via Shazam integration, save discoveries to personal playlists, and earn points for exploring the furthest corners of the radio spectrum.

---

## 2. Vision & Goals

- **Discover the unexpected** — Help users find music from radio stations worldwide, especially in places they'd never think to look
- **Gamify exploration** — Drive engagement through a points-based system that rewards geographic distance, station obscurity, and social sharing
- **Bridge radio and playlists** — Shazam integration lets users recognize songs on live radio and save them to personal playlists, bridging the ephemeral nature of radio with the permanence of streaming libraries
- **Social discovery** — Enable users to share their radio discoveries with friends and compete on leaderboards
- **Modern, grounded aesthetic** — A pastel earthy color palette that feels warm, inviting, and distinct from the typical dark-mode music app

---

## 3. Target Audience

| Segment | Description |
|---|---|
| **Music explorers** | Enthusiasts who actively seek out new music beyond algorithmic recommendations — they want serendipity, not suggestions |
| **Gamification-driven users** | Users motivated by points, streaks, leaderboards, and progression systems |
| **Radio lovers** | People who already listen to radio and want a better discovery/browsing experience |

---

## 4. Feature Requirements

### P0 — MVP

These features define the minimum viable product required for launch.

| Feature | Description |
|---|---|
| **Social SSO Authentication** | Sign in via Google SSO or Magic Link (passwordless email). Frictionless onboarding with minimal implementation effort. |
| **Global Station Discovery** | Browse and search radio stations worldwide by genre, tags, and country. Map-based or list-based exploration. Powered by RadioBrowser API data. |
| **Radio Player** | Stream radio stations in-app with standard playback controls (play/pause, volume). Background audio support. Display current station metadata (name, country, genre, bitrate). |
| **Song Recognition** | While a station is playing, tap to recognize the current song via AudD music recognition API. Returns track title, artist, album art, and streaming platform links. |
| **Basic Gamification** | Earn points for discovering new stations and recognizing songs. Simple point counter visible in profile. Foundation for the full scoring system in P1. |

### P1 — Post-MVP

Features that deepen engagement and add social mechanics. Prioritized by development order.

#### Phase 1 — Discovery & Visualization

| Feature | Description |
|---|---|
| **Station Globe / Map** | Display all stations (with or without active filters) on an interactive 3D globe or 2D map. Users can discover stations geographically, tap on markers to preview/play stations, and explore station density by region, genre, or country. Pan/zoom to explore regions. Filter overlay for genres, countries, or obscurity level. |
| **YouTube Music Deep Links** | From recognized songs, open the track directly in YouTube Music via deep link or web URL. AudD returns a YouTube URL in recognition results — surface this alongside the existing Spotify deep link. No API auth required. |

#### Phase 2 — Gamification & Scoring

| Feature | Description |
|---|---|
| **Advanced Scoring System** | Points scale with geographic distance from the user's location to the station. Points increase for obscure stations (low vote count, low click count). Bonus points for sharing and voting. Requires Stitch designs for score displays and point animations. |
| **Listening Dashboard** | Personal stats: total stations discovered, songs recognized, time listened, countries explored, top genres. Visual charts and summaries. |
| **Leaderboards** | Friends leaderboard and global leaderboard. Ranked by total points. Weekly and all-time views. |

#### Phase 3 — Social Features

| Feature | Description |
|---|---|
| **Friend System** | Add friends via username or link. View friends' recent discoveries. Social graph for leaderboard scoping. |
| **Station Sharing** | Share a station with a friend in-app. Shared stations appear as notifications/recommendations. Deep links for sharing outside the app. |
| **Station Voting** | Upvote/downvote stations. Votes feed into the obscurity scoring algorithm. Synced back to RadioBrowser where possible. |

### P2 — Future

Long-term features for retention and platform expansion.

| Feature | Description |
|---|---|
| **Curated Radio Playlists** | Editorially curated or algorithmically generated playlists of stations by genre/mood/vibe (e.g., "Late Night Jazz," "Sunday Morning Soul"). |
| **Playlist Export** | Export playlists of recognized songs to Apple Music or YouTube Music via their respective APIs. |
| **Station Recommendations** | Personalized station recommendations based on listening history, genre preferences, and collaborative filtering. |
| **Push Notifications** | Notifications for friend activity (shared stations, leaderboard changes), new stations in favorite genres. |
| **Offline Access** | Cache recognized song metadata and playlist data for offline viewing. |

---

## 5. Technical Architecture

### 5.1 System Overview

```
┌─────────────┐       ┌──────────────────────────────────┐
│             │       │           Supabase                │
│   Flutter   │◄─────►│  • Auth (Google/Magic Link)       │
│   Client    │  REST │  • PostgreSQL + PostGIS           │
│  (iOS/      │   +   │  • Row Level Security             │
│   Android/  │  WS   │  • Realtime Subscriptions         │
│   Web)      │       │  • Edge Functions                 │
│             │       │  • Storage (album art cache)      │
└──────┬──────┘       └──────────┬───────────────────────┘
       │                         │
       │ recognition             │ store results
       │ request                 │
       │                         │
       │               ┌─────────▼─────────┐
       └──────────────►│  Recognition       │
                       │  Worker            │
                       │  (Python/Dart)     │
                       │                    │
                       │  • ffmpeg capture  │
                       │  • Shazam API call │
                       │  • Store in DB     │
                       └────────────────────┘
```

### 5.2 Frontend — Flutter

- **Framework:** Flutter (Dart) — cross-platform for iOS, Android, and web from a single codebase
- **State management:** Riverpod (with riverpod_generator for compile-safe providers)
- **Audio playback:** Platform audio plugin for background streaming
- **Key screens:** Station browser, radio player, song recognition, playlists, profile/dashboard, leaderboards

### 5.3 Backend — Supabase

| Capability | Usage |
|---|---|
| **Authentication** | Google SSO (native support) + Magic Link. |
| **PostgreSQL** | Primary data store for users, stations, playlists, songs, points, friendships, votes. Row Level Security (RLS) on all tables. |
| **PostGIS** | Geographic queries for distance-based scoring and "stations near me" features. |
| **Realtime** | Client subscribes to `recognition_results` table — receives instant notification when song recognition completes. No polling needed. |
| **Edge Functions** | Lightweight serverless Deno functions for point calculations, leaderboard aggregation, and other business logic that shouldn't live in the client. |
| **Storage** | Cache album art and station logos for faster load times. |

### 5.4 Song Recognition Pipeline

#### Flow

```
1. User taps "Recognize" while station is playing
2. Client sends request to backend:
   {station_url, duration_seconds, user_id, request_id}
3. Request is enqueued via Supabase Queues (PGMQ)
4. Recognition Worker picks up the request:
   a. ffmpeg captures N seconds of audio from the station stream
   b. Audio is sent to AudD music recognition API
   c. Result (track info or "not found") is stored in Supabase DB
5. Client receives result via Supabase Realtime subscription
6. User sees recognized song with option to save to playlist
```

#### Worker Design

- **Stateless:** Each request is independent — no shared state between recognitions
- **Vertically scalable:** Scale by adding more worker instances
- **Language:** Python (proven with ffmpeg in previous implementation) or Dart (for stack consistency)
- **Input:** `{station_url, duration_seconds, user_id, request_id}`
- **Process:** ffmpeg audio stream capture → AudD API call → store result in Supabase
- **Output:** Row in `recognition_results` table, triggering Realtime notification

#### Recognition Result Caching

Recognition results are cached per station and timestamp to avoid redundant API calls. If multiple users are listening to the same station and tap "Recognize" around the same time, only one API request is made — subsequent users receive the cached result instantly.

**How it works:**

1. When a recognition request comes in, the worker first checks for an existing result for the same `station_url` within a recent time window (e.g., last 2–3 minutes)
2. If a cached result exists → return it immediately, no AudD API call needed
3. If no cache hit → proceed with ffmpeg capture + AudD API call, store result with station + timestamp
4. Cache key: `(station_uuid, timestamp_bucket)` — where timestamp is bucketed to the nearest ~2–3 minute window

**Benefits:**
- **Cost savings** — Popular stations with many concurrent listeners generate far fewer API calls
- **Faster results** — Cache hits return instantly (no ffmpeg capture or API call delay)
- **Scales with popularity** — The more users listen to a station, the higher the cache hit rate, inverting the cost curve
- **Natural fit** — Radio is a broadcast medium; everyone listening to the same station hears the same song at the same time

#### Shazam API → AudD Music Recognition API

> **Note:** The previous implementation used `shazamio`, a reverse-engineered Python library for Shazam. This was fragile and unreliable. The new implementation uses **AudD** (audd.io), a commercial music recognition API with an 80M+ track database, simple token authentication, and transparent per-request pricing. ACRCloud (150M+ tracks) is the designated fallback if AudD's database coverage proves insufficient.

AudD API response includes:
- Track title, artist/subtitle
- Album name and release date
- Label
- ISRC (International Standard Recording Code)
- Timecode (position in the song where the fragment matches)
- Song link (lis.tn)
- Deep links: Spotify, Apple Music, Deezer, Napster (via `return` parameter)

### 5.5 Now Playing Strategy

Radio stations display what's currently playing via two mechanisms, applied in order:

#### Tier 1 — ICY Metadata (free, client-side, ~40–50% of stations)

Most professional internet radio stations broadcast using Icecast or Shoutcast streaming software, which embeds song metadata directly in the HTTP audio stream as **ICY headers**. The Flutter audio player requests this metadata by sending `Icy-MetaData: 1` in the HTTP request header. The server responds with:

- `icy-name` — station name
- `icy-genre` — genre
- `icy-metaint` — byte interval at which metadata blocks appear in the stream
- Inline `StreamTitle` blocks within the audio data, updating in real-time as songs change

**How the client uses it:**

1. When a user starts playing a station, the audio player reads ICY headers from the stream
2. If `icy-metaint` is present, the player parses inline `StreamTitle` updates as they arrive
3. The now-playing display updates automatically without any API calls or backend involvement
4. ICY results are **display-only** — they show artist and title as raw text (e.g., `"Artist - Title"`) but are not enriched with ISRC, album art, or streaming platform links

**Coverage notes:**

- RadioBrowser's `has_extended_info` flag marks ~614 stations (~1.1%) as having fully parseable structured metadata, but raw ICY headers are available on a significantly broader set — approximately 40–50% of stations based on sampling
- HLS streams (chunked HTTP) do not support ICY metadata; those stations fall directly to Tier 2
- The `has_extended_info` field is synced from RadioBrowser and stored in the local stations table, allowing the client to know in advance which stations are likely to have ICY metadata

#### Tier 2 — AudD User-Initiated Fingerprinting (fallback, ~$0.005/request)

For stations without ICY metadata (or when the user wants enriched, structured data), the user taps a **"Identify"** button. This triggers the full recognition pipeline:

```
User taps "Identify"
    │
    ▼
Recognition request enqueued (PGMQ)
    │
    ▼
Worker: ffmpeg captures ~10s of audio from stream
    │
    ▼
AudD API: fingerprint audio → returns structured song data
    │
    ▼
Result stored in DB → Supabase Realtime pushes to client
    │
    ▼
Client displays: title, artist, album art, ISRC, Spotify/Apple Music links
```

AudD results are **fully enriched** — suitable for saving to playlists, linking to Spotify, and earning points.

#### Combined UX Flow

```
Station starts playing
    │
    ├─ ICY metadata available?
    │       │
    │       YES → Display "Now Playing: Artist - Title" automatically
    │               User can still tap "Identify" to get enriched data
    │               (album art, Spotify link, save to playlist, earn points)
    │
    └─ No ICY metadata
            │
            └─ Show "Identify" button
                    │
                    User taps → AudD fingerprinting pipeline
```

#### Why Not Continuous Stream Monitoring?

Two commercial products offer continuous stream monitoring (always-on fingerprinting for every station):

- **AudD Stream Monitoring** — $45/stream/month
- **WARM** — B2B airplay tracker (song→station direction, not station→song)

At $45/stream/month across 53,000+ RadioBrowser stations, continuous monitoring costs **~$2.4M/month** — entirely impractical. Neither service is designed for a per-user "now playing" use case; they target broadcast analytics and royalty tracking.

#### Schema Implications

ICY metadata is consumed entirely client-side and does not need to be persisted. The existing schema accommodates this strategy without changes:

- `stations.has_extended_info` — boolean flag synced from RadioBrowser; client uses this to predict ICY availability
- `recognition_requests` — used only for user-initiated AudD fingerprinting (Tier 2)
- ICY "now playing" text is transient display state managed in the Flutter UI layer

### 5.6 Data Sources

#### RadioBrowser API

- **Type:** Free, open-source, community-maintained API
- **Base URL:** `https://de1.api.radio-browser.info` (multiple mirrors available)
- **Data provided per station:**

| Field | Description |
|---|---|
| `stationuuid` | Unique station identifier |
| `name` | Station name |
| `url` / `url_resolved` | Stream URL (original and resolved) |
| `country` / `countrycode` | Station country |
| `geo_lat` / `geo_long` | Geographic coordinates |
| `tags` | Comma-separated genre/style tags |
| `votes` | Community vote count |
| `codec` / `bitrate` | Audio codec and bitrate |
| `clickcount` / `clicktrend` | Popularity metrics |
| `language` | Broadcast language |

#### Station Catalog Strategy

Rather than querying RadioBrowser on every user search, consider a **periodic sync** approach:

1. **Daily cron job** syncs station catalog from RadioBrowser into local Supabase Postgres
2. **Benefits:**
   - Faster searches via local Postgres indexes + full-text search
   - PostGIS-powered geographic queries for distance calculations
   - Enrichment with app-specific data (user votes, obscurity scores, discovery counts)
   - Pre-computed obscurity scores for gamification (based on vote count, click count, country)
   - Independence from RadioBrowser API availability
3. **Trade-off:** Data is up to 24h stale (acceptable for station metadata)

### 5.7 Gamification Scoring (P1)

Points are calculated based on multiple factors:

| Factor | Description | Example |
|---|---|---|
| **Geographic Distance** | Points scale with distance between user's location and station's location | Listening to a station 10,000 km away earns more than one 100 km away |
| **Station Obscurity** | Stations with fewer votes/clicks earn more points | An obscure station in Senegal with 3 votes earns more than BBC Radio 1 |
| **Sharing** | Bonus points for sharing stations with friends | Share a discovery → earn points |
| **Voting** | Points for voting on stations | Upvote or downvote → small point reward for participation |
| **Song Recognition** | Points for successfully recognizing songs | Each Shazam hit earns base points |

Point calculations run in **Supabase Edge Functions** to prevent client-side manipulation.

---

## 6. Open Questions — All Resolved ✅

> All architecture and product decisions have been resolved. Decisions are documented below for reference.

### ~~6.1 Queue Technology for Recognition Pipeline~~ ✅ RESOLVED

**Decision: Supabase Queues (PGMQ)**

Supabase Queues is a Postgres-native durable message queue built on the `pgmq` extension. It provides exactly-once delivery within a visibility timeout, built-in retry handling, and backpressure control — with zero additional infrastructure beyond the Supabase project.

**Why PGMQ over the alternatives:**

| Requirement | PGMQ | Kafka | BullMQ + Redis | Realtime + Worker |
|---|---|---|---|---|
| Delivery guarantee | Exactly-once (visibility timeout) | Exactly-once (with config) | At-least-once | None (missed events are lost) |
| Retry handling | Built-in (message re-appears after VT) | Built-in | Built-in | Manual (poll for stale rows) |
| Backpressure | Built-in (`qty` parameter) | Built-in | Built-in | None |
| Additional infrastructure | None (Postgres extension) | Kafka cluster or Upstash | Redis server | None |
| Dart/Flutter SDK support | Native (`supabase.schema('pgmq_public').rpc(...)`) | Third-party | N/A (server-side only) | Native |
| Message archiving | Built-in | Topic retention | Manual | N/A |
| Operational complexity | Zero | High | Medium | Low but fragile |

**Recognition pipeline flow with PGMQ:**

```
1. Flutter client enqueues recognition request:
   supabase.schema('pgmq_public').rpc('send', {
     queue_name: 'song_recognition',
     message: {station_url, duration_seconds, user_id, request_id}
   })

2. Recognition Worker polls the queue:
   pgmq.read('song_recognition', vt: 60, qty: 1)

3. Worker processes: ffmpeg capture → Shazam API → store result in DB

4. Worker acknowledges success:
   pgmq.delete('song_recognition', msg_id)

5. On failure: message becomes visible again after 60s visibility
   timeout → automatically retried by next worker poll

6. Client receives result via Supabase Realtime subscription
   on the recognition_requests table (status change → 'completed')
```

### ~~6.2 Single vs. Dual Queue~~ ✅ RESOLVED

**Decision: Single queue, single step.**

The worker reads from the PGMQ `song_recognition` queue, performs all processing (ffmpeg capture → Shazam API → store result in Supabase), and deletes the message. No second queue is needed because:

- The worker already has a Supabase client and writes results directly to the DB
- Result delivery to the Flutter client is handled by Supabase Realtime subscriptions on the `recognition_requests` table — not a second queue
- A second queue would only be warranted if multiple independent downstream consumers needed to react to results (e.g., a separate push notification service). This can be added later via Postgres triggers if needed.

### ~~6.3 Station Catalog: On-Demand vs. Periodic Sync~~ ✅ RESOLVED

**Decision: Periodic sync with incremental updates via `lastchangeuuid`.**

The RadioBrowser API station catalog is synced into local Supabase Postgres on a daily schedule. After the initial full import, subsequent syncs use RadioBrowser's `/json/stations/changed` endpoint with the `lastchangeuuid` parameter to fetch only stations that changed since the last sync — making daily syncs fast and lightweight.

**Sync strategy details:**

| Aspect | Approach |
|---|---|
| **Initial import** | Full catalog fetch via `/json/stations` with offset/limit pagination (default limit 100,000). Filter to `lastcheckok=1` to exclude broken stations. |
| **Incremental sync** | Daily cron calls `/json/stations/changed?lastchangeuuid={uuid}` — returns only stations modified since last sync. Store the latest `changeuuid` after each sync run. |
| **Server discovery** | DNS lookup of `all.api.radio-browser.info` returns all available mirrors. Randomize server selection and failover to next on error. |
| **User-Agent** | Required by RadioBrowser API — use descriptive header: `UnearthRadio/1.0 (contact@unearthradio.com)` |
| **Click counting** | Call `/json/url/{stationuuid}` when a user starts playing a station. This is a community courtesy to contribute usage data back to RadioBrowser. |
| **Upsert strategy** | Upsert on `stationuuid` — insert new stations, update changed fields, soft-delete stations no longer in the catalog. |
| **Staleness** | Data is at most ~24h stale. Acceptable for station metadata (names, URLs, tags rarely change). |

**Why periodic sync over on-demand:**

1. **Performance** — Local Postgres indexes + full-text search is orders of magnitude faster than proxying every search to RadioBrowser
2. **PostGIS queries** — Enables geographic distance calculations for gamification scoring and "stations near me" features
3. **Enrichment** — Decorate stations with app-specific data: user votes, obscurity scores, discovery counts, play counts
4. **Pre-computed scores** — Calculate and cache obscurity scores based on vote count, click count, and geographic distribution
5. **Reliability** — App doesn't go down if RadioBrowser API is temporarily unavailable
6. **Advanced search** — Full control over search UX: fuzzy matching, combined filters, relevance ranking

**Key RadioBrowser API fields synced:**

`stationuuid`, `name`, `url`, `url_resolved`, `homepage`, `favicon`, `tags`, `countrycode`, `country`, `state`, `geo_lat`, `geo_long`, `votes`, `clickcount`, `clicktrend`, `codec`, `bitrate`, `hls`, `lastcheckok`, `language`, `languagecodes`, `has_extended_info`, `ssl_error`, `changeuuid`

### ~~6.4 Realtime vs. Polling for Recognition Results~~ ✅ RESOLVED

**Decision: Supabase Realtime with timeout fallback.**

The Flutter client subscribes to the `recognition_requests` table filtered by `request_id` via Supabase Realtime. The moment the recognition worker writes the result and updates the row status to `completed`, the client receives an instant push notification over the existing WebSocket connection.

**Why Realtime over polling:**

| Criteria | Realtime (chosen) | Polling |
|---|---|---|
| **Latency** | Instant — result appears the moment the worker writes it | Delayed by poll interval (1–5s) |
| **Server load** | One persistent WebSocket (already open for other Supabase features) | Repeated HTTP requests every N seconds |
| **UX** | Smooth — recognized song just "appears" | Slight delay, feels less responsive |
| **Battery/network** | Efficient — single persistent connection | Wasteful — repeated requests during wait |
| **Complexity** | Low — built into Supabase with native Dart SDK | Low — simple timer + HTTP call |

**Timeout fallback:** If no Realtime event arrives within 30 seconds, the client falls back to a single HTTP fetch of the `recognition_requests` row. This covers edge cases like dropped WebSocket connections or Realtime service interruptions without requiring a full polling loop.

### ~~6.5 Song Recognition API~~ ✅ RESOLVED

**Decision: AudD as primary recognition API, ACRCloud as fallback.**

There is no publicly available official Shazam API (Apple acquired Shazam in 2018 and shut down third-party access). The two leading commercial alternatives were evaluated:

| Criteria | AudD (chosen) | ACRCloud (fallback) |
|---|---|---|
| **Database size** | 80M+ tracks | 150M+ tracks |
| **Authentication** | Simple API token | HMAC signature (more complex) |
| **Pricing transparency** | Fully public | "Contact Sales" only |
| **Pricing (pay-as-you-go)** | $5 per 1,000 requests | Unknown (estimated ~$5–10/1K) |
| **Volume pricing** | 100K/$450, 200K/$800, 500K/$1,800 | Unknown |
| **Free tier** | 300 free requests | 14-day trial |
| **Response time** | < 2 seconds | < 2 seconds |
| **Max input** | 10MB / 25 seconds | Similar |
| **Response data** | Title, artist, album, ISRC, label, timecode, Spotify/Apple Music/Deezer links | Title, artist, album, ISRC, UPC, Spotify/Apple Music/Deezer/YouTube links |
| **Notable clients** | Sony, Warner Music, Universal Music | Deezer, Anghami, Believe |
| **Unique features** | WebSocket async, unlimited-length enterprise endpoint | Humming recognition, cover song detection, offline SDKs |

**Why AudD as primary:**
1. **Transparent pricing** — public rates that are easy to budget for an indie app
2. **Simple integration** — plain API token vs. HMAC signature construction
3. **80M tracks is sufficient** — more than covers mainstream and semi-mainstream radio content
4. **Major label validation** — all three major labels (Sony, Warner, Universal) use AudD
5. **Fits our pipeline exactly** — ffmpeg captures ≤25s of audio, POST to AudD, get JSON result

**Fallback to ACRCloud if:** AudD's database proves insufficient for very obscure international radio stations. ACRCloud's 150M track database with cover song detection would be the upgrade path.

**Note:** shazam-api.com was investigated and ruled out — it is not affiliated with Apple/Shazam, and is a niche copyright-tracking tool for music producers, not a general-purpose recognition API.

#### Monetization Strategy: Freemium Song Recognition

Song recognition has a direct per-request API cost, making it a natural monetization lever. The planned model:

| Tier | Song Recognitions | Price |
|---|---|---|
| **Free** | Limited free recognitions per account (e.g. 10–20/month) | $0 |
| **Paid (Unearth Pro)** | Unlimited recognitions | TBD (monthly subscription) |

- Free users get enough recognitions to experience the core feature and get hooked
- Power users who want unlimited "Shazam on every station" pay a subscription
- Exact pricing, free tier limits, and subscription price to be determined based on AudD cost analysis and market positioning
- This model ensures API costs are covered and creates a sustainable revenue stream

### ~~6.6 Spotify Integration & Auth Strategy~~ ❌ WON'T IMPLEMENT

**Decision: Spotify OAuth / deep API integration is dropped.**

Spotify's Extended Quota Mode (required to lift the 5-user developer limit) requires a legally registered business with 250,000+ MAUs. This is not a realistic milestone for Unearth Radio. Building the integration and being permanently capped at 5 users is not viable.

**What remains:**
- **Spotify deep links (P0 — all users):** AudD recognition results include a `spotify_uri`. This is stored in `recognized_songs.spotify_uri` and opens the Spotify app directly via `url_launcher`. No OAuth, no API calls, no quota mode required. This feature is already implemented and stays.

**What is cut:**
- Spotify OAuth2 / SSO
- Save to Liked Songs
- Export playlists to Spotify
- The `spotify/` Flutter feature folder planned in `spotify_api_integration.md`

See `spotify_api_integration.md` for the full research archive (marked won't implement).

### ~~6.7 State Management (Flutter)~~ ✅ RESOLVED

**Decision: Riverpod.**

Riverpod is the modern standard for state management in new Flutter projects. It provides compile-safe dependency injection, excellent testability (no BuildContext required), and low boilerplate with code generation (`riverpod_generator`).

**Why Riverpod for Unearth Radio:**

1. **Developer familiarity** — Most experience on the team is with Riverpod
2. **Async-first** — `AsyncValue`, `FutureProvider`, and `StreamProvider` map naturally to Supabase queries, Realtime subscriptions, and recognition result streams
3. **Greenfield project** — No legacy state management to migrate from
4. **Low boilerplate** — With `riverpod_generator` and `riverpod_annotation`, providers are concise and type-safe
5. **Testability** — Providers can be overridden in tests without widget trees, making unit testing straightforward

**Key packages:**
- `flutter_riverpod` — Core Riverpod for Flutter
- `riverpod_annotation` + `riverpod_generator` — Code generation for compile-safe providers
- `build_runner` — Code generation runner

---

## 7. Design Direction

### Aesthetic

- **Pastel earthy color palette** — warm, grounded, and modern
- Distinct from typical dark-mode music apps (Spotify, Apple Music)
- Think: terracotta, sage, sand, muted gold, warm cream, dusty rose
- Clean typography with generous whitespace

### UI Patterns

- **Radio player:** Full-screen player view with album art (when available), station info, playback controls, and a prominent "Recognize" button
- **Station browser:** Filterable list or map view with genre chips, country filters, and search
- **Dashboard:** Visual stats cards, charts for listening history, badge/achievement display
- **Sharing:** Share cards with station info and deep link — designed for social media sharing

### Platform

- Mobile-first design (iOS/Android via Flutter)
- Web as secondary platform
- Responsive layouts that adapt to screen size

---

## 8. Previous Implementation Reference

The `radio-app/` directory contains a previous backend prototype that informs this new implementation.

### Previous Architecture

```
Gateway (Fastify, port 8000)
  └── Proxy routes to downstream services
        ├── Balancer (Fastify, port 3000)
        │     └── RadioBrowser API queries via radio-browser-api npm package
        └── ML-Listener (FastAPI/Python, port 3006)
              └── POST /recognize {url, time}
                    ├── ffmpeg-python: capture N seconds of radio stream
                    ├── shazamio: recognize captured audio
                    └── Store result in Firebase RTDB
```

### Previous Stack

| Component | Technology |
|---|---|
| Monorepo | Turborepo + Yarn workspaces |
| Gateway | Fastify (TypeScript) |
| Station Search | Fastify + `radio-browser-api` npm package |
| Song Recognition | FastAPI (Python) + `shazamio` + `ffmpeg-python` |
| Message Queue | RabbitMQ (planned, partially wired) |
| Database | Firebase Realtime Database |
| Logging | Winston |

### Key Learnings

1. **Service separation works** — Gateway → Balancer → ML-Listener was a clean separation of concerns
2. **Recognition flow is proven** — ffmpeg stream capture → Shazam recognition is a viable pipeline
3. **`shazamio` is fragile** — Reverse-engineered library; replaced by AudD commercial API (see §6.5)
4. **Missing critical pieces** — No auth, no frontend, no gamification, no real database
5. **RabbitMQ was over-engineered** — Queue was planned but the simple request/response flow worked for prototype scale
6. **Firebase RTDB was a quick hack** — Fine for prototyping but not suitable for relational data, RLS, or geographic queries

### What Carries Forward

- The ffmpeg audio capture approach for grabbing radio streams
- RadioBrowser API as the station data source
- The concept of a dedicated recognition worker service
- Separation of station search and song recognition concerns

### What Changes

| Previous | New |
|---|---|
| Node.js + Python backend | Supabase (managed) + Worker service |
| Firebase RTDB | PostgreSQL via Supabase |
| `shazamio` (reverse-engineered) | AudD music recognition API (see §6.5) |
| RabbitMQ | Supabase Queues / PGMQ (see §6.1) |
| No auth | Google SSO + Magic Link |
| No frontend | Flutter (iOS/Android/Web) |
| No gamification | Points, leaderboards, scoring |

---

*This is a living document. All open questions have been resolved. Next step: database migrations.*
