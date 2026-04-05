# Unearth Radio

<p align="center">
  <a href="https://flutter.dev">
    <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat&logo=flutter" alt="Flutter">
  </a>
  <a href="https://supabase.com">
    <img src="https://img.shields.io/badge/Supabase-2.25.0-3FCF8E?style=flat&logo=supabase" alt="Supabase">
  </a>
  <a href="https://www.python.org/">
    <img src="https://img.shields.io/badge/Python-3.11+-3776AB?style=flat&logo=python" alt="Python">
  </a>
  <a href="https://www.docker.com/">
    <img src="https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker" alt="Docker">
  </a>
  <a href="https://github.com/luukwitteman/radio/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT">
  </a>
</p>

> Discover radio stations worldwide. Recognize songs playing on any station. Earn points for exploration.

Unearth Radio is a cross-platform mobile application that transforms how you explore global radio. Browse thousands of stations by genre, listen with background playback, identify songs via audio fingerprinting, and compete on leaderboards through a gamified discovery system.

## 📸 Screenshots

<p align="center">
  <em>Explore the app in action — login, station discovery, live player, song recognition, map view, and profile with leaderboard</em>
</p>

| | | |
|:---:|:---:|:---:|
| <img src="screenshots/login_magic_link.png" width="200"/> | <img src="screenshots/explore.png" width="200"/> | <img src="screenshots/map.png" width="200"/> |
| **Login** | **Explore** | **Map** |
| <img src="screenshots/player.png" width="200"/> | <img src="screenshots/playback_controls.png" width="200"/> | <img src="screenshots/recognize_song1.png" width="200"/> |
| **Player** | **Controls** | **Recognize 1** |
| <img src="screenshots/recognize_song2.png" width="200"/> | <img src="screenshots/profile_and_stats.png" width="200"/> | <img src="screenshots/leaderboard.png" width="200"/> |
| **Recognize 2** | **Profile** | **Leaderboard** |

---

## 🎯 Key Features

| Feature | Description |
|---------|-------------|
| **Global Station Discovery** | Browse 50,000+ radio stations worldwide, filtered by genre, country, and obscurity score |
| **Live Radio Streaming** | Stream stations with background playback and ICY metadata for real-time "now playing" |
| **Song Recognition** | Tap to identify songs playing on any station via AudD music fingerprinting API |
| **Gamification** | Earn points for geographic distance, station obscurity, and song recognition |
| **Leaderboards** | Compete with friends and globally on weekly and all-time leaderboards |
| **YouTube Music Links** | Open recognized songs directly in YouTube Music via deep links |

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EXTERNAL SERVICES                              │
│  RadioBrowser API          AudD API              ACRCloud (fallback)       │
│  (station catalog)        (song recognition)    (recognition fallback)    │
└───────────┬────────────────────┬───────────────────────┬───────────────────┘
            │ daily sync         │ fingerprint request    │
            │                    │                        │
┌───────────▼──────┐   ┌─────────▼────────────────────────▼─────────────────┐
│                  │   │                                                      │
│   Sync Worker    │   │           Recognition Worker                        │
│   (Python/UV)    │   │           (Python/UV)                               │
│                  │   │                                                      │
│  • DNS discovery │   │  • Polls PGMQ queue                                │
│  • Incremental   │   │  • ffmpeg stream capture                           │
│    diff sync     │   │  • AudD API call                                   │
│  • PostGIS geo   │   │  • Result caching (3min)                           │
└───────────┬──────┘   └──────────────────────┬────────────────────────────┘
            │                                  │
            │ writes                           │ reads queue / writes results
            │                                  │
┌───────────▼──────────────────────────────────▼────────────────────────────┐
│                                                                           │
│                             SUPABASE                                      │
│                                                                           │
│  ┌─────────────┐  ┌────────────┐  ┌───────────┐  ┌────────────────────┐│
│  │    Auth     │  │ PostgreSQL │  │  Realtime │  │  Edge Functions    ││
│  │ Google SSO  │  │ + PostGIS  │  │ (WebSocket│  │  (Deno/TypeScript)  ││
│  │ Magic Link  │  │ + PGMQ     │  │  push)    │  │  point scoring      ││
│  └─────────────┘  └────────────┘  └───────────┘  └────────────────────┘│
│                                                                           │
│  ┌─────────────┐  ┌────────────┐  ┌───────────┐                         │
│  │   Storage   │  │  PGMQ      │  │    RLS    │                         │
│  │  album art  │  │  queues    │  │  policies │                         │
│  └─────────────┘  └────────────┘  └───────────┘                         │
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
                        │  just_audio + audio_service   │
                        │  Supabase Dart SDK             │
                        │                               │
                        └───────────────────────────────┘
```

### Component Summary

| Component | Technology | Responsibility |
|-----------|------------|----------------|
| **Flutter Client** | Flutter + Riverpod | UI, audio playback, ICY metadata, user interactions |
| **Backend** | Supabase | Auth, PostgreSQL, Realtime, Edge Functions, Storage |
| **Recognition Worker** | Python + ffmpeg | Audio capture, AudD API calls, result storage |
| **Sync Worker** | Python + UV | RadioBrowser → Postgres station catalog sync |

---

## 🛠️ Tech Stack

### Frontend
- **Flutter** 3.x — Cross-platform UI framework (iOS, Android, Web)
- **Riverpod** — Compile-safe state management with code generation
- **just_audio** + **audio_service** — Audio playback with background support
- **go_router** — Declarative routing

### Backend (Supabase)
- **PostgreSQL** — Primary datastore with PostGIS for geographic queries
- **PostGIS** — Spatial data for distance-based scoring
- **PGMQ** — Native Postgres message queue for recognition pipeline
- **Realtime** — WebSocket push for instant recognition results
- **Edge Functions** — Serverless Deno functions for point calculations
- **Auth** — Google SSO + Magic Link authentication

### Services
- **Python (UV)** — Worker services with modern Python tooling
- **ffmpeg** — Audio stream capture for song recognition
- **AudD API** — Music fingerprinting (80M+ track database)
- **RadioBrowser API** — Global radio station data source
- **Docker** — Containerized worker deployment

---

## 🚀 Getting Started

### Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| **Flutter** | 3.x | Mobile/web development |
| **Docker** | Latest | Running Supabase Local & workers |
| **Supabase CLI** | Latest | Local development environment |
| **Python** | 3.11+ | Worker service development |

### 1. Clone & Install Dependencies

```bash
git clone https://github.com/luukwitteman/radio.git
cd radio

# Flutter dependencies
cd app
flutter pub get
cd ..

# Python dependencies (for workers)
cd worker
uv sync
cd ..
```

### 2. Start Supabase Local

```bash
cd supabase
supabase start
```

This starts the following services:

| Service | Port | URL |
|---------|------|-----|
| **Studio** (DB GUI) | 55323 | http://localhost:55323 |
| **Database** | 55322 | postgresql://postgres:postgres@localhost:55322 |
| **Mailpit** (email testing) | 55324 | http://localhost:55324 |

### 3. Configure Environment

Create environment files with your local Supabase credentials:

```bash
# sync/.env
SUPABASE_URL=http://127.0.0.1:55321
SUPABASE_SERVICE_KEY=<your-service-role-key>

# worker/.env
SUPABASE_URL=http://127.0.0.1:55321
SUPABASE_SERVICE_KEY=<your-service-role-key>
AUDD_API_KEY=<your-audd-token>
```

> **Note:** Get your `SUPABASE_SERVICE_KEY` from `supabase status` after starting.

### 4. Run the Flutter App

```bash
cd app
flutter run
```

### 5. Run Workers (Optional — for local development)

```bash
# Sync stations from RadioBrowser
docker run --rm --env-file sync/.env unearth-sync

# Start recognition worker
docker run --rm --env-file worker/.env unearth-worker
```

---

## 📁 Project Structure

```
radio/
├── app/                      # Flutter application
│   ├── lib/
│   │   ├── core/            # Theme, router, Supabase client
│   │   ├── features/         # Auth, stations, player, recognition, profile
│   │   └── shared/           # Models, widgets
│   ├── test/                # Widget & unit tests
│   └── pubspec.yaml
│
├── supabase/                 # Supabase local configuration
│   ├── migrations/          # Database migrations
│   └── config/
│
├── worker/                   # Song recognition worker (Python/UV)
│   ├── main.py
│   ├── pyproject.toml
│   └── tests/
│
├── sync/                    # Station sync worker (Python/UV)
│   ├── main.py
│   ├── pyproject.toml
│   └── tests/
│
├── PRD.md                   # Product Requirements Document
├── ARCHITECTURE.md          # Architecture Design Document
└── README.md
```

---

## 🧪 Testing

```bash
# Run Flutter tests
cd app
flutter test

# Run worker tests
cd worker
python -m pytest

# Run sync tests
cd sync
python -m pytest
```

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Areas to Contribute

- 🎨 UI/UX improvements (Flutter widgets, animations)
- 🧩 New features (playlists, social sharing, station voting)
- 🐛 Bug fixes (ICY metadata parsing, audio streaming)
- 📚 Documentation (README updates, code comments)
- 🧪 Testing (unit tests, integration tests, E2E)

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- [RadioBrowser API](https://www.radio-browser.info/) — Community-driven radio station data
- [AudD](https://audd.io/) — Music recognition API
- [Supabase](https://supabase.com/) — Open-source Firebase alternative
- [Flutter](https://flutter.dev/) — Cross-platform UI framework