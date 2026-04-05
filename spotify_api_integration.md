# Unearth Radio — Spotify API Integration

> ⚠️ **WON'T IMPLEMENT** — Spotify Extended Quota Mode (required to lift the 5-user developer cap) requires 250,000+ MAUs and a legally registered business. This integration is permanently shelved. Spotify **deep links** (open in Spotify app, no OAuth) remain implemented. See PRD.md §6.6 for the decision record.

> **Status:** ~~Research & Planning~~ — Archived / Won't Implement (2026-04-03)
> **Last Updated:** 2026-04-03
> **Author:** Luuk Witteman
> **Scope:** P1 (Unearth Pro paid tier) — not MVP

---

## Table of Contents

1. [Overview & Scope](#1-overview--scope)
2. [February 2026 API Changes — Critical Reading](#2-february-2026-api-changes--critical-reading)
3. [Auth Flow — Supabase + Spotify OAuth2](#3-auth-flow--supabase--spotify-oauth2)
4. [OAuth Scopes](#4-oauth-scopes)
5. [API Endpoints (Feb 2026 Compliant)](#5-api-endpoints-feb-2026-compliant)
6. [Token Management Architecture](#6-token-management-architecture)
7. [Database Schema Additions](#7-database-schema-additions)
8. [Flutter Architecture](#8-flutter-architecture)
9. [UX Flows](#9-ux-flows)
10. [Paywalling Strategy](#10-paywalling-strategy)
11. [Rate Limits & Quotas](#11-rate-limits--quotas)
12. [Security Notes](#12-security-notes)
13. [Developer Setup Checklist](#13-developer-setup-checklist)
14. [Implementation Roadmap](#14-implementation-roadmap)
15. [Open Questions](#15-open-questions)
16. [References](#16-references)

---

## 1. Overview & Scope

### What This Doc Covers

Planning and reference for integrating the Spotify Web API into Unearth Radio. The integration has three tiers:

| Tier | Feature | Auth Required | Users |
|---|---|---|---|
| **P0 (done)** | "Open in Spotify" deep link | None | All (free + Pro) |
| **P1 (this doc)** | Connect account, save to library, add to playlists | Spotify OAuth2 | Unearth Pro only |
| **P2** | Playlist export (bulk sync) | Spotify OAuth2 | Unearth Pro only |

### Deep Links — Already Working (P0)

AudD recognition results include a `spotify_uri` field. This is stored in `recognized_songs.spotify_uri` and used to open the Spotify app directly from `recognized_song_card.dart` via `url_launcher`. **No OAuth needed.** This doc is exclusively about the authenticated P1/P2 features.

### Current State of the Spotify Developer App

- App created **after February 11, 2026** → starts in the new restricted **Development Mode**
- Configured for **Web API only**
- Max 5 allowlisted users until Extended Quota Mode is approved
- App owner must have Spotify Premium for the app to function in Development Mode

---

## 2. February 2026 API Changes — Critical Reading

This app was created after the Spotify API changes that took effect February 11, 2026. The old documentation and most Stack Overflow answers are **wrong**. Use only the endpoints listed in this doc.

### Breaking Changes

| Old Endpoint / Field | New Endpoint / Field | Notes |
|---|---|---|
| `GET /playlists/{id}/tracks` | `GET /playlists/{id}/items` | Renamed |
| `tracks` field in playlist response | `items` | Renamed |
| `PUT /me/tracks` | `PUT /me/library` | Uses Spotify URIs, not track IDs |
| `DELETE /me/tracks` | `DELETE /me/library` | Same change |
| `GET /me/tracks/contains?ids=...` | `GET /me/library/contains?uris=...` | URIs, not IDs |
| `POST /users/{id}/playlists` | `POST /me/playlists` | User-scoped endpoint removed |
| `GET /tracks`, `GET /albums` (batch) | Fetch individually | Batch endpoints removed |
| `available_markets` in track | Removed | — |
| `popularity` in track | Removed | — |
| `linked_from` in track | Removed | — |
| `external_ids` (ISRC) | **Reinstated** March 2026 | ISRC is back — safe to use |

### Development Mode Restrictions

- **Max 5 users** — each must be manually allowlisted in the Spotify Developer Dashboard under App Settings → Users Management
- App owner must have Spotify Premium
- Search results capped at **10 per page** (vs. 50 in Extended Quota Mode)
- Lower rate limits than production

### Extended Quota Mode (Required for Public Launch)

Extended Quota Mode lifts all user count and rate limit restrictions.

> **Warning:** As of May 2025, Spotify only accepts Extended Quota applications from **legally registered businesses** with **250k+ MAUs**, an active service, and a presence in key Spotify markets. Individuals cannot apply. Plan for this well before public launch.

This means the Spotify integration will be **invite/allowlist-only during beta** (≤5 test users), then requires a business registration and 250k MAU milestone to open to the public.

---

## 3. Auth Flow — Supabase + Spotify OAuth2

Supabase natively supports Spotify as a social OAuth provider. No custom OAuth2 implementation is needed in Flutter.

### Configuration

**Step 1 — Supabase Dashboard:**

1. Authentication → Providers → Spotify
2. Enable Spotify
3. Enter Client ID + Client Secret from the Spotify Developer Dashboard
4. Copy the callback URL shown: `https://{project-ref}.supabase.co/auth/v1/callback`

**Step 2 — Spotify Developer Dashboard:**

Add all required Redirect URIs to App Settings:

```
https://{project-ref}.supabase.co/auth/v1/callback   ← Supabase cloud
http://localhost:55321/auth/v1/callback                ← Local Supabase (port 55321)
io.unearth.radio://auth-callback                       ← Flutter mobile deep link
```

**Step 3 — Local Supabase config (`supabase/config.toml`):**

```toml
[auth.external.spotify]
enabled = true
client_id = "env(SPOTIFY_CLIENT_ID)"
secret = "env(SPOTIFY_SECRET)"
```

Add to `.env.local`:

```
SPOTIFY_CLIENT_ID=your_client_id
SPOTIFY_SECRET=your_client_secret
```

### Flutter Sign-In

```dart
// spotify_auth_provider.dart
await supabase.auth.signInWithOAuth(
  OAuthProvider.spotify,
  redirectTo: kIsWeb ? null : 'io.unearth.radio://auth-callback',
  authScreenLaunchMode: kIsWeb
      ? LaunchMode.platformDefault
      : LaunchMode.externalApplication,
  scopes: [
    'user-read-email',
    'user-read-private',
    'playlist-modify-public',
    'playlist-modify-private',
    'playlist-read-private',
    'user-library-modify',
    'user-library-read',
  ].join(' '),
);
```

### Accessing Tokens After Sign-In

```dart
final session = supabase.auth.currentSession;
final spotifyAccessToken = session?.providerToken;       // ~1 hour TTL
final spotifyRefreshToken = session?.providerRefreshToken; // long-lived
```

> **Critical:** Supabase does **not** auto-refresh Spotify provider tokens. The access token expires in ~1 hour and must be refreshed manually. See [§6 Token Management](#6-token-management-architecture).

---

## 4. OAuth Scopes

Request all scopes at initial sign-in. Do not request incrementally — it creates a worse UX than a single consent screen.

| Scope | Purpose | Feature |
|---|---|---|
| `user-read-email` | Auth / user identification | Sign-in |
| `user-read-private` | Subscription type check | Sign-in |
| `playlist-modify-public` | Create / add to public playlists | Playlist export |
| `playlist-modify-private` | Create / add to private playlists | Playlist export |
| `playlist-read-private` | List user's private playlists | Playlist picker UI |
| `user-library-modify` | Save to Liked Songs | "Like on Spotify" |
| `user-library-read` | Check if track already saved | Heart icon state |

---

## 5. API Endpoints (Feb 2026 Compliant)

All requests require: `Authorization: Bearer {access_token}`

Base URL: `https://api.spotify.com/v1`

### Get Current User Profile

```
GET /me
Scopes: user-read-email, user-read-private
```

Returns: `id`, `display_name`, `email`, `images`

> Note: `country`, `product` (premium/free), and `followers` are removed in Feb 2026 for Development Mode apps.

### List User's Playlists

```
GET /me/playlists?limit=10&offset=0
Scopes: playlist-read-private
```

Returns paginated list. Max **10 per page** in Development Mode. Response uses `items` field.

```dart
// Paginate through all playlists
int offset = 0;
const limit = 10;
List<SpotifyPlaylist> all = [];

while (true) {
  final resp = await spotifyService.getUserPlaylists(limit: limit, offset: offset);
  all.addAll(resp.items);
  if (resp.items.length < limit) break;
  offset += limit;
}
```

### Create Playlist

```
POST /me/playlists
Scopes: playlist-modify-private OR playlist-modify-public
```

```json
{
  "name": "Unearth Radio Discoveries",
  "public": false,
  "description": "Songs discovered on Unearth Radio"
}
```

Returns: new playlist object with `id`.

### Add Items to Playlist

```
POST /playlists/{playlist_id}/items
Scopes: playlist-modify-public OR playlist-modify-private
```

```json
{
  "uris": ["spotify:track:4iV5W9uYEdYUVa79Axb7Rh"],
  "position": 0
}
```

- Max **100 URIs per request** — batch if exporting a large playlist
- Returns: `{"snapshot_id": "..."}`

### Save Track to Liked Songs

```
PUT /me/library
Scope: user-library-modify
```

```json
{
  "uris": ["spotify:track:4iV5W9uYEdYUVa79Axb7Rh"]
}
```

Accepts any Spotify URI (track, album, artist, show, episode).

### Check If Track Is Saved

```
GET /me/library/contains?uris=spotify:track:4iV5W9uYEdYUVa79Axb7Rh
Scope: user-library-read
```

Returns: `[true]` or `[false]`

### Deep Link (No Auth — Already Working)

```dart
// Uses spotify_uri from recognized_songs table
final uri = recognizedSong.spotifyUri; // e.g. "spotify:track:4iV5W9uYEdYUVa79Axb7Rh"
final webFallback = 'https://open.spotify.com/track/${trackId}';

if (await canLaunchUrl(Uri.parse(uri))) {
  await launchUrl(Uri.parse(uri));
} else {
  await launchUrl(Uri.parse(webFallback));
}
```

Available to **all users** — free and Pro. No OAuth required.

---

## 6. Token Management Architecture

### The Problem

- Spotify access tokens expire in ~1 hour
- Supabase does not auto-refresh provider tokens
- The `client_secret` must **never** appear in Flutter app code

### Solution: Supabase Edge Function

```
Flutter detects token is expiring (< 5 min remaining)
  │
  └─ POST /functions/v1/spotify-token-refresh
       (authenticated via Supabase JWT)
         │
         └─ Edge Function reads stored refresh_token from DB
               │
               └─ POST https://accounts.spotify.com/api/token
                    (client_id + client_secret in Authorization header)
                         │
                         └─ Store new access_token + expiry in DB
                               │
                               └─ Return fresh access_token to Flutter
```

Edge Function environment variables:

```
SPOTIFY_CLIENT_ID=...
SPOTIFY_CLIENT_SECRET=...
```

### Token Validity Check (Flutter)

```dart
// spotify_token_manager.dart
Future<String> getFreshToken() async {
  final profile = await ref.read(userProfileProvider.future);
  final expiresAt = profile.spotifyTokenExpiresAt;

  // Refresh if within 5 minutes of expiry
  if (expiresAt == null || 
      expiresAt.difference(DateTime.now().toUtc()).inMinutes < 5) {
    return await _refreshViaEdgeFunction();
  }

  return profile.spotifyAccessToken!;
}
```

---

## 7. Database Schema Additions

One new migration needed. Add to `user_profiles` (adjust if the table is `users`):

```sql
-- supabase/migrations/NNNN_spotify_integration.sql

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS spotify_user_id          text,
  ADD COLUMN IF NOT EXISTS spotify_connected        boolean  DEFAULT false,
  ADD COLUMN IF NOT EXISTS spotify_access_token     text,     -- store encrypted
  ADD COLUMN IF NOT EXISTS spotify_refresh_token    text,     -- store encrypted
  ADD COLUMN IF NOT EXISTS spotify_token_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS spotify_scopes           text;     -- space-separated granted scopes

ALTER TABLE playlists
  ADD COLUMN IF NOT EXISTS spotify_playlist_id  text,         -- set after export
  ADD COLUMN IF NOT EXISTS spotify_synced_at    timestamptz;  -- last export/sync time
```

> Note: `recognized_songs.spotify_uri` already exists (populated by AudD). No changes needed there.

### RLS Considerations

- `spotify_access_token` and `spotify_refresh_token` must **not** be exposed via any public SELECT policy
- The Edge Function reads these columns using `service_role` (bypasses RLS)
- Flutter reads only `spotify_connected` and `spotify_token_expires_at` directly — never the raw tokens

---

## 8. Flutter Architecture

### New Files

```
app/lib/src/features/spotify/
  services/
    spotify_service.dart          ← HTTP client for Spotify Web API
    spotify_token_manager.dart    ← Token expiry check + refresh via Edge Function
  providers/
    spotify_auth_provider.dart    ← Connection state, connect, disconnect
    spotify_playlist_provider.dart ← User's Spotify playlists (for picker UI)
  models/
    spotify_playlist.dart         ← Data class: id, name, public, trackCount
    spotify_track.dart            ← Data class (minimal — uri, name, artist)
  widgets/
    connect_spotify_button.dart   ← CTA to link Spotify account
    spotify_playlist_picker.dart  ← Bottom sheet: pick existing or create new playlist
    add_to_spotify_button.dart    ← Compact action button for recognized_song_card
```

### `spotify_service.dart` — Interface

```dart
class SpotifyService {
  // Liked Songs
  Future<void> saveToLibrary(String spotifyUri);
  Future<bool> isInLibrary(String spotifyUri);

  // Playlists
  Future<List<SpotifyPlaylist>> getUserPlaylists({int limit = 10, int offset = 0});
  Future<SpotifyPlaylist> createPlaylist({required String name, bool public = false, String? description});
  Future<void> addToPlaylist({required String playlistId, required List<String> uris});

  // Profile
  Future<SpotifyUser> getCurrentUser();
}
```

### `spotify_auth_provider.dart` — State

```dart
@riverpod
class SpotifyAuthNotifier extends _$SpotifyAuthNotifier {
  @override
  AsyncValue<SpotifyConnectionState> build() => const AsyncValue.data(
    SpotifyConnectionState.disconnected,
  );

  Future<void> connect() async { /* signInWithOAuth + store tokens */ }
  Future<void> disconnect() async { /* clear tokens from DB, set connected=false */ }
}
```

### Integration Points in Existing Screens

#### `recognized_song_card.dart`

Add a "Save to Spotify" action:

```
spotify_uri present?
  │
  ├─ YES → show "Open in Spotify" button (always, no auth)
  │
  └─ User taps "Save to Spotify" (Pro gated)
        │
        ├─ Not Pro → show upgrade prompt
        ├─ Pro, not connected → show ConnectSpotifyButton
        └─ Pro + connected
              ├─ "Add to Liked Songs" → spotifyService.saveToLibrary(uri)
              └─ "Add to Playlist" → SpotifyPlaylistPicker bottom sheet
```

#### `playlist_detail_screen.dart`

Add "Export to Spotify" action in the app bar or FAB:

```
User taps "Export to Spotify"
  │
  ├─ Not connected → connect prompt
  │
  └─ Connected
        ├─ Already exported? → "Update Playlist" (sync new songs only)
        └─ Not exported → SpotifyPlaylistPicker
              └─ On confirm → batch add all songs (100 URIs/request)
                    └─ Store spotify_playlist_id on playlist row
```

#### `profile_screen.dart`

Add a "Connected Accounts" card with Spotify status and connect/disconnect button.

---

## 9. UX Flows

### Flow 1: Song Recognition → Save to Spotify

```
User recognizes song (RecognizedSongCard shown)
  │
  ├─ "Open in Spotify" button (always shown — deep link, no auth)
  │
  └─ "Save to Spotify" button (Pro feature)
        │
        ├─ Free user
        │     └─ Pro upgrade sheet ("Unlock Unearth Pro")
        │
        ├─ Pro, Spotify not connected
        │     └─ "Connect your Spotify account" prompt
        │           └─ ConnectSpotifyButton → OAuth flow
        │
        └─ Pro + Spotify connected
              │
              ├─ "Liked Songs"
              │     └─ PUT /me/library → success snackbar
              │
              └─ "Add to Playlist"
                    └─ SpotifyPlaylistPicker bottom sheet
                          ├─ Pick existing playlist
                          │     └─ POST /playlists/{id}/items
                          └─ Create new
                                └─ POST /me/playlists → POST /playlists/{id}/items
```

### Flow 2: Playlist Export (Bulk)

```
User opens playlist_detail_screen
  │
  └─ Taps "Export to Spotify" (Pro feature)
        │
        ├─ Not connected → connect prompt
        │
        └─ Connected
              │
              ├─ playlist.spotify_playlist_id set?
              │     YES → "Update Spotify Playlist"
              │             → find new songs since last sync
              │             → POST /playlists/{id}/items (new songs only)
              │             → update spotify_synced_at
              │
              └─ NO → SpotifyPlaylistPicker
                    ├─ Pick existing Spotify playlist
                    └─ Create new
                          └─ POST /me/playlists
                                └─ Batch all songs → POST /playlists/{id}/items
                                      (100 URIs per request — loop if > 100 songs)
                                            └─ Store spotify_playlist_id on playlist row
```

### Flow 3: Connect / Disconnect

```
Profile screen → Connected Accounts → "Connect Spotify"
  │
  └─ signInWithOAuth(spotify, scopes: ...)
        │
        └─ Supabase PKCE redirect → Spotify consent → callback
              │
              └─ session.providerToken + session.providerRefreshToken
                    │
                    └─ Edge Function stores tokens in user_profiles
                          └─ set spotify_connected = true
                                └─ Invalidate spotifyAuthProvider

"Disconnect Spotify"
  │
  └─ Clear tokens from user_profiles (server-side)
        └─ set spotify_connected = false
              └─ Note: Spotify-side playlists are NOT deleted
```

---

## 10. Paywalling Strategy

| Feature | Free | Unearth Pro |
|---|---|---|
| "Open in Spotify" deep link | ✅ | ✅ |
| Connect Spotify account | ❌ | ✅ |
| Save to Liked Songs | ❌ | ✅ |
| Add to Spotify playlist | ❌ | ✅ |
| Export Unearth playlist to Spotify | ❌ | ✅ |
| Unlimited song recognitions | ❌ | ✅ |

### Paywall Check Pattern

```dart
// In any Spotify-gated widget
final user = ref.watch(userProvider);
final isPro = user.isPro; // TBD — depends on subscription implementation (see Open Questions)

if (!isPro) {
  return SpotifyFeatureLockedWidget(); // Shows lock icon + "Unearth Pro" label
}
```

`ConnectSpotifyButton` renders differently based on Pro status:

```
isPro = false → greyed out button with lock icon and "Unearth Pro" label
isPro = true, not connected → active CTA "Connect Spotify"
isPro = true, connected → "Connected as {display_name}" with disconnect option
```

---

## 11. Rate Limits & Quotas

| Concern | Mitigation |
|---|---|
| Token refresh hammering | Only refresh when within 5 minutes of expiry; cache token in provider |
| Playlist list re-fetching | Cache user's Spotify playlist list; invalidate only after export/create |
| Bulk playlist export | Batch URIs in groups of 100 (Spotify max per request); add 200ms delay between batches |
| Development mode rate limits | Lower than production — do not stress-test in dev mode |
| `liked` state polling | Check `GET /me/library/contains` only once per song card render; do not poll |

---

## 12. Security Notes

- **Never embed `client_secret` in Flutter** — always use the Supabase Edge Function for token refresh
- Spotify access and refresh tokens in the DB should be encrypted at rest (Supabase Vault / `pgsodium`) — address this before public launch; acceptable to defer for beta
- RLS policies must prevent any SELECT on `spotify_access_token` / `spotify_refresh_token` from `authenticated` role queries
- Spotify policy: do not use Spotify URIs to redirect users to competing services
- Spotify policy: `preview_url` (30s audio previews) is deprecated and policy-restricted — do not implement
- Spotify policy: do not display Spotify content (track names, album art served from Spotify CDN) as a standalone service without proper attribution

---

## 13. Developer Setup Checklist

### Spotify Developer Dashboard

- [x] App created at https://developer.spotify.com/dashboard (Web API, Development Mode)
- [ ] Add Supabase callback URL: `https://{project-ref}.supabase.co/auth/v1/callback`
- [ ] Add local callback URL: `http://localhost:55321/auth/v1/callback`
- [ ] Add Flutter mobile deep link: `io.unearth.radio://auth-callback`
- [ ] Note Client ID and Client Secret
- [ ] Add up to 5 test users: App Settings → Users Management → Add User
- [ ] Verify app owner has Spotify Premium (required for Development Mode)

### Supabase Configuration

- [ ] Dashboard → Authentication → Providers → Enable Spotify
- [ ] Enter Client ID + Client Secret
- [ ] Add Edge Function environment variables: `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`

### Local Supabase (port 55321)

- [ ] Add to `supabase/config.toml`:

```toml
[auth.external.spotify]
enabled = true
client_id = "env(SPOTIFY_CLIENT_ID)"
secret = "env(SPOTIFY_SECRET)"
```

- [ ] Add to `.env.local`:

```
SPOTIFY_CLIENT_ID=your_client_id
SPOTIFY_SECRET=your_client_secret
```

### Flutter App

- [ ] Add `app_links` or `uni_links` package for deep link handling (if not already in use for magic link auth)
- [ ] Verify `io.unearth.radio` scheme is registered in `AndroidManifest.xml` and iOS `Info.plist`

---

## 14. Implementation Roadmap

### Phase 1 — Foundation

1. **DB migration** — Add Spotify columns to `user_profiles` + `playlists`
2. **Edge Function** — `spotify-token-refresh` (reads refresh token from DB, calls Spotify token endpoint, stores new access token)
3. **`spotify_token_manager.dart`** — Token validity check + refresh trigger
4. **`spotify_service.dart`** — HTTP client wrapping all endpoints in §5
5. **`spotify_auth_provider.dart`** — Connection state, connect, disconnect

### Phase 2 — UI

6. **`connect_spotify_button.dart`** — Renders correctly for free / Pro-not-connected / Pro-connected states
7. **`add_to_spotify_button.dart`** — Integrate into `recognized_song_card.dart`
8. **`spotify_playlist_picker.dart`** — Bottom sheet: list existing playlists + "Create new" option
9. **Profile screen** — "Connected Accounts" section with Spotify status card

### Phase 3 — Playlist Export

10. **`spotify_playlist_provider.dart`** — Fetch + cache user's Spotify playlists
11. **`playlist_detail_screen.dart`** — "Export to Spotify" / "Update Spotify Playlist" button
12. Batch export logic (100 URIs per request, loop for larger playlists)
13. Export status tracking via `playlists.spotify_playlist_id` + `spotify_synced_at`

### Phase 4 — Production Readiness (Before Public Launch)

14. Apply for Extended Quota Mode (requires registered business + 250k MAUs)
15. Encrypt Spotify tokens at rest (Supabase Vault)
16. End-to-end token refresh testing (let token expire, verify seamless refresh)
17. Spotify policy compliance review

---

## 15. Open Questions

| # | Question | Impact |
|---|---|---|
| 1 | **Subscription gating** — How is Unearth Pro status tracked? `user_profiles` flag? `subscriptions` table? RevenueCat? This determines how `isPro` is checked in Flutter. | Required before any Pro-gated UI is built |
| 2 | **Token encryption** — Use Supabase Vault (`pgsodium`) for `spotify_access_token` / `spotify_refresh_token` columns from day one, or defer? | Defer to beta is acceptable; must be addressed before public launch |
| 3 | **Disconnect behaviour** — Confirmed: when a user disconnects Spotify, Spotify-side playlists are **not** deleted. Only our stored tokens are cleared. | Implementation detail — agreed |
| 4 | **Beta allowlist** — Which 5 users get allowlisted in Spotify Developer Dashboard for testing? | Blocks any testing of Pro features |
| 5 | **Extended Quota path** — At what stage do we apply? Spotify requires 250k MAUs + registered business. This must be part of the launch strategy. | Blocks public availability of Spotify features |
| 6 | **Incremental export sync** — When a user adds songs to an Unearth playlist after it's been exported, should "Update Spotify Playlist" add only new songs (requires tracking last sync offset) or do a full re-sync? | Affects `spotify_synced_at` schema design |

---

## 16. References

| Resource | URL |
|---|---|
| Spotify Web API Reference | https://developer.spotify.com/documentation/web-api |
| Spotify OAuth Scopes | https://developer.spotify.com/documentation/web-api/concepts/scopes |
| February 2026 Migration Guide | https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide |
| Spotify Quota Modes | https://developer.spotify.com/documentation/web-api/concepts/quota-modes |
| Authorization Code + PKCE Flow | https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow |
| Refreshing Access Tokens | https://developer.spotify.com/documentation/web-api/tutorials/refreshing-tokens |
| Supabase Spotify Auth Guide | https://supabase.com/docs/guides/auth/social-login/auth-spotify |
| Supabase Vault (token encryption) | https://supabase.com/docs/guides/database/vault |

---

*Research complete as of 2026-04-03. Begin implementation when Unearth Pro subscription mechanism is decided (Open Question #1).*
