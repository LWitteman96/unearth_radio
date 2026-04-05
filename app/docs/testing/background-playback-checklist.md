# Background Playback — Build Verification & Manual Testing Checklist

> **Subtask 08** — Validation artifact for the `audio_service` + `just_audio` background-playback
> integration (subtasks 01–07).

---

## Build Verification

### Commands run (in `app/`)

| # | Command | Outcome |
|---|---------|---------|
| 1 | `flutter analyze` | ✅ **No errors.** Warnings only (see below). |
| 2 | `flutter test test/unit/features/player/ --reporter expanded` | ✅ **64 / 64 tests passed.** |

### `flutter analyze` — warning summary

All issues found are **warnings** (severity `info` or `warning`) — no **errors** that block the build.

#### New warnings introduced by background-playback work

| File | Line | Code | Notes |
|------|------|------|-------|
| `lib/src/features/player/services/background_audio_bootstrap.dart` | 44 | `unnecessary_cast` | `AudioService.init<RadioAudioHandler>` already infers the concrete type; the `as RadioAudioHandler` cast is redundant. Non-blocking — follow-up cleanup item. |
| `test/unit/features/player/media_item_sync_test.dart` | 14 | `unused_import` | `package:audio_service/audio_service.dart` imported but not referenced directly in this test file. |
| `test/unit/features/player/player_provider_test.dart` | 22 | `unused_import` | `package:audio_service/audio_service.dart` imported but not used directly. |
| `test/unit/features/player/player_provider_test.dart` | 31 | `unused_shown_name` | `PlayerNotifier` in the `show` clause is not used in test assertions. |
| `test/unit/features/player/radio_audio_handler_test.dart` | 27 | `unused_import` | `dart:async` imported but not used directly. |

#### Pre-existing warnings (present before background-playback work)

- `withOpacity` deprecation (`deprecated_member_use`) across `player_screen.dart`,
  `station_detail_screen.dart`, `filter_hub_screen.dart`, `recognized_song_card.dart`,
  `identify_button.dart` — upgrade to `.withValues()` is a separate cleanup task.
- `unused_field` in `lib/src/core/theme/app_theme.dart` (`_surfaceVariant`, `_background`,
  `_onBackground`, `_darkSurfaceVariant`).
- `unnecessary_underscores` in `playlists_screen.dart`, `player_screen.dart`,
  `station_detail_screen.dart`.
- `no_leading_underscores_for_local_identifiers` in `player_screen.dart`.

### Unit test results

```
flutter test test/unit/features/player/ --reporter expanded
64 tests, 0 failures, 0 errors   ✅
```

Test files covered:

| File | Tests |
|------|-------|
| `radio_audio_handler_test.dart` | `RadioPlaybackSnapshot` pure-Dart value type; `buildMediaItem` handler-integration view |
| `media_item_sync_test.dart` | `buildMediaItem()` — ICY parsing, deduplication, artUri, field mapping |
| `player_provider_test.dart` | `PlayerState` constructor & `copyWith`; `PlayerNotifier` snapshot reactions via `FakeRadioAudioHandler` |

---

## Manual Testing Checklist

> These checks **must** be performed on real devices (physical hardware recommended). Emulators —
> especially Android ones — may not support HLS/ICY streams reliably.

### Android

- [ ] **Foreground playback** — App opens, tap a station, audio plays within the app.
- [ ] **Background playback** — Press the Home button while audio is playing; confirm audio
      continues uninterrupted.
- [ ] **Media notification — appears** — Pull down the notification shade; confirm a persistent
      notification is present showing the station name and play/pause controls.
- [ ] **Media notification — play/pause** — Tap the play/pause button in the notification; confirm
      audio responds immediately and the button icon toggles correctly.
- [ ] **Lock-screen controls — station name** — Lock the device while playing; confirm the
      lock-screen media card shows the correct station name.
- [ ] **Lock-screen controls — play/pause** — Tap play/pause on the lock screen; confirm audio
      responds and the icon toggles.
- [ ] **ICY metadata updates in notification** — When the station broadcasts a new "Artist - Title"
      ICY metadata string, confirm the notification (and lock screen) updates to show the new
      artist/title without requiring any user interaction.
- [ ] **Notification dismiss stops audio** — Swipe away (dismiss) the media notification; confirm
      audio stops cleanly and the app reflects a stopped state when opened.
- [ ] **Resume after Recents** — Switch to the Recents screen and return to the app; confirm
      playback state is preserved.

### iOS

- [ ] **Foreground playback** — App opens, tap a station, audio plays within the app.
- [ ] **Background playback** — Press the Home button while audio is playing; confirm audio
      continues uninterrupted.
- [ ] **Lock-screen Now Playing — station name** — Lock the device while playing; confirm the
      Now Playing widget on the lock screen shows the correct station name.
- [ ] **Control Center — station name & controls** — Swipe to Control Center while playing; confirm
      the media card shows the station name and working play/pause controls.
- [ ] **Control Center — play/pause** — Tap play/pause in Control Center; confirm audio responds
      and the button icon updates.
- [ ] **ICY metadata — lock screen / Control Center** — When a new "Artist - Title" ICY metadata
      string is received, confirm the lock screen and Control Center update to reflect the new
      artist/title.
- [ ] **Force-quit stops audio** — Swipe the app away from the App Switcher; confirm audio stops
      cleanly.
- [ ] **AirPlay (bonus)** — With AirPlay output selected, confirm audio routes correctly and
      controls remain functional.

---

## Known Limitations & Follow-up Items

| # | Platform | Issue | Severity | Follow-up |
|---|----------|-------|----------|-----------|
| 1 | Android | `just_audio` on some Android **emulators** may fail to play HLS/ICY streams. | Medium | Always validate background playback on a **real Android device**. |
| 2 | Android | The `unnecessary_cast` in `background_audio_bootstrap.dart` line 44 is non-blocking but should be cleaned up. | Low | Remove `as RadioAudioHandler`; rely on the generic type parameter inferred by `AudioService.init<RadioAudioHandler>`. |
| 3 | Both | Unused imports in test files (`audio_service`, `dart:async`, `PlayerNotifier` show clause) produce warnings but do not affect test correctness. | Low | Clean up in a separate lint-tidy pass. |
| 4 | Both | End-to-end device testing is required to verify platform media controls (lock screen, notification shade, Control Center). The automated unit tests in subtask 07 cover Dart logic only and **cannot** substitute for real-device validation. | High | Run this checklist on both a physical Android device and a physical iPhone before shipping. |
| 5 | iOS | AirPlay integration has not been explicitly tested. `audio_service` should handle it automatically via `AVAudioSession`, but confirm during device testing. | Low | Mark the AirPlay checkbox in the iOS section above. |
| 6 | Both | `withOpacity` deprecation warnings across multiple screens are pre-existing (not introduced by background-playback work) and should be addressed in a dedicated UI cleanup task. | Low | Replace `.withOpacity(x)` with `.withValues(alpha: x)` across affected files. |

---

*Generated by BuildAgent — subtask 08 of the background-playback feature track.*
*Date: 2026-04-03*
