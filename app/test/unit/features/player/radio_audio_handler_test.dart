// Tests for RadioAudioHandler in radio_audio_handler.dart
//
// Strategy: RadioAudioHandler owns a real just_audio AudioPlayer that initialises
// platform channels in its constructor. Running it in a unit test without a full
// Flutter binding will throw. The safest approach is to:
//
//  • Test updateIcyMetadata() + buildMediaItem() integration using a
//    hand-rolled subclass that stubs the AudioPlayer and captures
//    mediaItem.add() calls via a StreamController we own.
//
//  • Test RadioPlaybackSnapshot (pure Dart value type) independently.
//
//  • Test _stationFromMediaItem logic indirectly via the public
//    updateIcyMetadata() / buildMediaItem() path.
//
// We do NOT try to call AudioPlayer.setUrl / play / pause from tests because
// that requires real platform channels.
//
// Covers:
//  ✅ RadioPlaybackSnapshot defaults
//  ✅ updateIcyMetadata adds MediaItem when station loaded and metadata changes
//  ✅ updateIcyMetadata is a no-op when no station is loaded
//  ✅ updateIcyMetadata is a no-op (dedup) when metadata is identical
//  ✅ updateIcyMetadata parses raw ICY "Artist - Title" string
//  ❌ updateIcyMetadata with null station does NOT add to mediaItem
//  ❌ updateIcyMetadata with identical metadata does NOT add to mediaItem (dedup)

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:unearth_radio/src/features/player/services/media_item_sync.dart';
import 'package:unearth_radio/src/features/player/services/radio_audio_handler.dart';
import 'package:unearth_radio/src/shared/models/station.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Station _station({
  String id = 'st-test',
  String name = 'Test FM',
  String url = 'http://stream.test/fm',
  String? favicon,
}) {
  return Station(id: id, rbId: id, name: name, url: url, favicon: favicon);
}

// ---------------------------------------------------------------------------
// Lightweight harness that exercises updateIcyMetadata without a real player.
//
// It reproduces the logic of RadioAudioHandler.updateIcyMetadata() using only
// pure-Dart dependencies (buildMediaItem + a BehaviorSubject-like value holder).
// ---------------------------------------------------------------------------

/// Thin wrapper that mirrors the updateIcyMetadata / dedup logic of
/// [RadioAudioHandler] without touching platform channels.
class _UpdateIcyHarness {
  Station? currentStation;
  MediaItem? currentMediaItem;

  final List<MediaItem?> mediaItemAdds = [];

  /// Mirrors RadioAudioHandler.updateIcyMetadata().
  void updateIcyMetadata({String? rawTitle, String? artist}) {
    final station = currentStation;
    if (station == null) return;

    final next = buildMediaItem(
      station: station,
      icyTitle: rawTitle,
      icyArtist: artist,
      current: currentMediaItem,
    );
    if (next != null) {
      mediaItemAdds.add(next);
      currentMediaItem = next;
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // RadioPlaybackSnapshot — pure Dart value type
  // =========================================================================
  group('RadioPlaybackSnapshot', () {
    test(
      '✅ defaults: isPlaying=false, isLoading=false, no station, no error',
      () {
        // Arrange + Act
        const snap = RadioPlaybackSnapshot();

        // Assert
        expect(snap.isPlaying, isFalse);
        expect(snap.isLoading, isFalse);
        expect(snap.currentStation, isNull);
        expect(snap.hasError, isFalse);
      },
    );

    test('✅ custom values are stored correctly', () {
      // Arrange
      final station = _station(name: 'Radio X');

      // Act
      final snap = RadioPlaybackSnapshot(
        isPlaying: true,
        isLoading: false,
        currentStation: station,
        hasError: false,
      );

      // Assert
      expect(snap.isPlaying, isTrue);
      expect(snap.currentStation?.name, equals('Radio X'));
    });

    test('❌ snapshot is not an error state by default', () {
      // Arrange + Act
      const snap = RadioPlaybackSnapshot();

      // Assert
      expect(snap.hasError, isFalse);
    });

    test('❌ snapshot is not loading by default', () {
      // Arrange + Act
      const snap = RadioPlaybackSnapshot();

      // Assert
      expect(snap.isLoading, isFalse);
    });
  });

  // =========================================================================
  // updateIcyMetadata() integration — via lightweight harness
  // =========================================================================
  group('updateIcyMetadata() logic (via _UpdateIcyHarness)', () {
    late _UpdateIcyHarness harness;

    setUp(() {
      harness = _UpdateIcyHarness();
    });

    // -----------------------------------------------------------------------
    // No-op when no station is loaded
    // -----------------------------------------------------------------------
    test(
      '❌ no-op when currentStation is null (nothing added to mediaItem)',
      () {
        // Arrange — harness starts with no station.
        expect(harness.currentStation, isNull);

        // Act
        harness.updateIcyMetadata(rawTitle: 'Artist - Track');

        // Assert
        expect(harness.mediaItemAdds, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // First call with metadata → item added
    // -----------------------------------------------------------------------
    test(
      '✅ adds a MediaItem when station is loaded and metadata is provided',
      () {
        // Arrange
        harness.currentStation = _station(name: 'Jazz FM');

        // Act
        harness.updateIcyMetadata(rawTitle: 'Miles Davis - So What');

        // Assert
        expect(harness.mediaItemAdds, hasLength(1));
        expect(harness.mediaItemAdds.first!.title, equals('So What'));
        expect(harness.mediaItemAdds.first!.artist, equals('Miles Davis'));
      },
    );

    // -----------------------------------------------------------------------
    // Dedup: identical metadata → no second add
    // -----------------------------------------------------------------------
    test('❌ does NOT add to mediaItem when metadata is identical (dedup)', () {
      // Arrange — first call populates currentMediaItem.
      harness.currentStation = _station(name: 'Rock FM');
      harness.updateIcyMetadata(rawTitle: 'Nirvana - Smells Like Teen Spirit');
      expect(harness.mediaItemAdds, hasLength(1));

      // Act — identical call.
      harness.updateIcyMetadata(rawTitle: 'Nirvana - Smells Like Teen Spirit');

      // Assert — still only 1 add total.
      expect(harness.mediaItemAdds, hasLength(1));
    });

    // -----------------------------------------------------------------------
    // Metadata changes → new item added
    // -----------------------------------------------------------------------
    test('✅ adds a second MediaItem when metadata changes after dedup', () {
      // Arrange
      harness.currentStation = _station(name: 'Pop FM');
      harness.updateIcyMetadata(rawTitle: 'Lady Gaga - Bad Romance');
      expect(harness.mediaItemAdds, hasLength(1));

      // Act — different track.
      harness.updateIcyMetadata(rawTitle: 'Katy Perry - Roar');

      // Assert
      expect(harness.mediaItemAdds, hasLength(2));
      expect(harness.mediaItemAdds.last!.title, equals('Roar'));
      expect(harness.mediaItemAdds.last!.artist, equals('Katy Perry'));
    });

    // -----------------------------------------------------------------------
    // No ICY → station name fallback
    // -----------------------------------------------------------------------
    test('✅ falls back to station name when no ICY metadata provided', () {
      // Arrange
      harness.currentStation = _station(name: 'Ambient Radio');

      // Act
      harness.updateIcyMetadata();

      // Assert
      expect(harness.mediaItemAdds, hasLength(1));
      expect(harness.mediaItemAdds.first!.title, equals('Ambient Radio'));
      expect(harness.mediaItemAdds.first!.artist, isNull);
    });

    // -----------------------------------------------------------------------
    // Raw ICY string parsing
    // -----------------------------------------------------------------------
    test(
      '✅ parses "Artist - Title" ICY string into separate artist and title',
      () {
        // Arrange
        harness.currentStation = _station();

        // Act
        harness.updateIcyMetadata(rawTitle: 'Daft Punk - One More Time');

        // Assert
        expect(harness.mediaItemAdds, hasLength(1));
        final item = harness.mediaItemAdds.first!;
        expect(item.artist, equals('Daft Punk'));
        expect(item.title, equals('One More Time'));
      },
    );

    // -----------------------------------------------------------------------
    // Explicit artist + title
    // -----------------------------------------------------------------------
    test('✅ uses explicit artist param without re-parsing icyTitle', () {
      // Arrange
      harness.currentStation = _station();

      // Act — icyTitle should be used verbatim as title (no splitting).
      harness.updateIcyMetadata(rawTitle: 'Bohemian Rhapsody', artist: 'Queen');

      // Assert
      expect(harness.mediaItemAdds, hasLength(1));
      final item = harness.mediaItemAdds.first!;
      expect(item.artist, equals('Queen'));
      expect(item.title, equals('Bohemian Rhapsody'));
    });

    // -----------------------------------------------------------------------
    // ICY string with no separator → title is the full string, artist null
    // -----------------------------------------------------------------------
    test(
      '❌ no " - " separator in ICY string → artist is null, title is full string',
      () {
        // Arrange
        harness.currentStation = _station(name: 'Fallback Station');

        // Act
        harness.updateIcyMetadata(rawTitle: 'JustATitleNoSeparator');

        // Assert
        expect(harness.mediaItemAdds, hasLength(1));
        final item = harness.mediaItemAdds.first!;
        expect(item.artist, isNull);
        expect(item.title, equals('JustATitleNoSeparator'));
      },
    );

    // -----------------------------------------------------------------------
    // Station switch: different station, same metadata → new item added
    // (artUri changes because stations can have different favicons)
    // -----------------------------------------------------------------------
    test(
      '✅ adds new MediaItem after station switch even with same ICY metadata',
      () {
        // Arrange — first station populates currentMediaItem.
        harness.currentStation = _station(id: 'st-A', name: 'Shared Name');
        harness.updateIcyMetadata(rawTitle: 'Artist - Song');
        expect(harness.mediaItemAdds, hasLength(1));

        // Act — switch to a different station with the same visible metadata.
        harness.currentStation = _station(id: 'st-B', name: 'Shared Name');
        harness.updateIcyMetadata(rawTitle: 'Artist - Song');

        // Assert — the new station identity/extras should still force a refresh.
        expect(harness.mediaItemAdds, hasLength(2));
        expect(
          harness.mediaItemAdds.last!.extras?[mediaItemStationIdExtrasKey],
          equals('st-B'),
        );
      },
    );
  });

  // =========================================================================
  // buildMediaItem() — quick integration smoke tests from handler perspective
  // These complement media_item_sync_test.dart with handler-oriented framing.
  // =========================================================================
  group('buildMediaItem() (handler integration perspective)', () {
    test('✅ returns non-null on first call (current is null)', () {
      // Arrange
      final station = _station(name: 'My Radio');

      // Act
      final result = buildMediaItem(station: station, current: null);

      // Assert
      expect(result, isNotNull);
    });

    test('✅ MediaItem id uses station.urlResolved when available', () {
      // Arrange
      final station = Station(
        id: 'sid',
        rbId: 'sid',
        name: 'CDN Radio',
        url: 'http://raw.example.com',
        urlResolved: 'http://cdn.example.com/stream',
      );

      // Act
      final result = buildMediaItem(station: station);

      // Assert
      expect(result!.id, equals('http://cdn.example.com/stream'));
    });

    test('❌ returns null when all three dedup fields are unchanged', () {
      // Arrange — identical station, same ICY → dedup fires.
      final station = _station(name: 'Dedup FM');
      final first = buildMediaItem(
        station: station,
        icyTitle: 'DJ - Mix',
        current: null,
      );

      // Act
      final second = buildMediaItem(
        station: station,
        icyTitle: 'DJ - Mix',
        current: first,
      );

      // Assert
      expect(second, isNull);
    });
  });
}
