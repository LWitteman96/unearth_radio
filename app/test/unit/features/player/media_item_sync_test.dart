// Tests for buildMediaItem() in media_item_sync.dart
//
// Covers:
//  ✅ Station name fallback when no ICY metadata
//  ✅ "Artist - Title" raw ICY string parsing
//  ✅ Explicit icyArtist + icyTitle fields
//  ✅ Dedup: returns null when MediaItem is identical to current
//  ✅ Graceful fallback when ICY string has no ` - ` separator
//  ✅ station.favicon used as artUri when non-null
//  ❌ Negative: empty icyTitle treated as no ICY metadata
//  ❌ Negative: empty icyArtist treated as null artist
//  ❌ Negative: invalid favicon URL handled gracefully (no crash)

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:unearth_radio/src/features/player/services/media_item_sync.dart';
import 'package:unearth_radio/src/shared/models/station.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Minimal station with sensible defaults. Override fields as needed per-test.
Station _station({
  String id = 'station-1',
  String name = 'Test Radio',
  String url = 'http://stream.example.com/radio',
  String? urlResolved,
  String? favicon,
}) {
  return Station(
    id: id,
    rbId: id,
    name: name,
    url: url,
    urlResolved: urlResolved,
    favicon: favicon,
  );
}

void main() {
  group('buildMediaItem()', () {
    test('✅ stores station extras as JSON-safe data for restoration', () {
      // Arrange
      final station = _station(id: 'station-json', name: 'Serialized FM');

      // Act
      final result = buildMediaItem(station: station);

      // Assert
      expect(result, isNotNull);
      expect(
        result!.extras?[mediaItemStationIdExtrasKey],
        equals('station-json'),
      );
      expect(
        result.extras?[mediaItemSchemaVersionExtrasKey],
        equals(mediaItemSchemaVersion),
      );
      expect(
        deserializeStation(result.extras?[mediaItemStationExtrasKey])?.name,
        equals('Serialized FM'),
      );
    });

    // -------------------------------------------------------------------------
    // 1. Fallback: no ICY metadata → station name used as title
    // -------------------------------------------------------------------------
    group('no ICY metadata', () {
      test(
        '✅ uses station.name as title when no icyTitle or icyArtist provided',
        () {
          // Arrange
          final station = _station(name: 'Jazz FM');

          // Act
          final result = buildMediaItem(station: station);

          // Assert
          expect(result, isNotNull);
          expect(result!.title, equals('Jazz FM'));
          expect(result.artist, isNull);
        },
      );

      test('✅ artist is null when no ICY metadata', () {
        // Arrange
        final station = _station(name: 'Radio Galaxie');

        // Act
        final result = buildMediaItem(station: station);

        // Assert
        expect(result, isNotNull);
        expect(result!.artist, isNull);
      });

      test('✅ album is always station.name regardless of ICY metadata', () {
        // Arrange
        final station = _station(name: 'Deep House Radio');

        // Act
        final result = buildMediaItem(station: station, icyTitle: 'DJ - Track');

        // Assert
        expect(result, isNotNull);
        expect(result!.album, equals('Deep House Radio'));
      });

      test('✅ marks radio media items as live for system controls', () {
        // Arrange
        final station = _station(name: 'Live Radio');

        // Act
        final result = buildMediaItem(station: station);

        // Assert
        expect(result, isNotNull);
        expect(result!.isLive, isTrue);
      });

      test(
        '❌ empty icyTitle is treated as "no ICY metadata" → fallback to station name',
        () {
          // Arrange
          final station = _station(name: 'Chill Waves');

          // Act
          final result = buildMediaItem(station: station, icyTitle: '');

          // Assert
          expect(result, isNotNull);
          expect(result!.title, equals('Chill Waves'));
          expect(result.artist, isNull);
        },
      );

      test('❌ whitespace-only icyTitle is treated as "no ICY metadata"', () {
        // Arrange
        final station = _station(name: 'Station X');

        // Act
        // The parser trims; `parseIcyTitle('   ')` returns both null.
        // buildMediaItem will therefore use station.name.
        final result = buildMediaItem(station: station, icyTitle: '   ');

        // Assert
        expect(result, isNotNull);
        expect(result!.title, equals('Station X'));
      });
    });

    // -------------------------------------------------------------------------
    // 2. Raw ICY string "Artist - Title" parsing
    // -------------------------------------------------------------------------
    group('raw ICY string parsing', () {
      test('✅ parses "Artist - Title" correctly into artist and title', () {
        // Arrange
        final station = _station();

        // Act
        final result = buildMediaItem(
          station: station,
          icyTitle: 'Daft Punk - Get Lucky',
        );

        // Assert
        expect(result, isNotNull);
        expect(result!.title, equals('Get Lucky'));
        expect(result.artist, equals('Daft Punk'));
      });

      test(
        '✅ handles multiple " - " separators — splits on first occurrence only',
        () {
          // Arrange
          final station = _station();

          // Act
          final result = buildMediaItem(
            station: station,
            icyTitle: 'AC/DC - Back In Black - Live',
          );

          // Assert
          expect(result, isNotNull);
          expect(result!.artist, equals('AC/DC'));
          expect(result.title, equals('Back In Black - Live'));
        },
      );

      test('❌ fallback gracefully when ICY string has no " - " separator', () {
        // Arrange — ICY string with no separator: whole string becomes title,
        // artist is null.
        final station = _station(name: 'Radio Test');

        // Act
        final result = buildMediaItem(
          station: station,
          icyTitle: 'JustASingleWord',
        );

        // Assert
        expect(result, isNotNull);
        expect(result!.title, equals('JustASingleWord'));
        expect(result.artist, isNull);
      });

      test(
        '❌ ICY string " - " with empty artist → artist is null, title is non-empty',
        () {
          // Arrange
          // Parsing " - Track" → artist segment is empty → null; title = "Track"
          final station = _station(name: 'FallbackStation');

          // Act
          final result = buildMediaItem(
            station: station,
            icyTitle: ' - Track Only',
          );

          // Assert
          expect(result, isNotNull);
          expect(result!.artist, isNull);
          expect(result.title, equals('Track Only'));
        },
      );
    });

    // -------------------------------------------------------------------------
    // 3. Explicit icyArtist + icyTitle
    // -------------------------------------------------------------------------
    group('explicit icyArtist and icyTitle', () {
      test(
        '✅ uses icyTitle as literal title when icyArtist is also provided',
        () {
          // Arrange
          final station = _station();

          // Act
          final result = buildMediaItem(
            station: station,
            icyTitle: 'Bohemian Rhapsody',
            icyArtist: 'Queen',
          );

          // Assert
          expect(result, isNotNull);
          expect(result!.title, equals('Bohemian Rhapsody'));
          expect(result.artist, equals('Queen'));
        },
      );

      test(
        '✅ falls back to station.name as title when icyArtist given but icyTitle is null',
        () {
          // Arrange
          final station = _station(name: 'Radio One');

          // Act
          final result = buildMediaItem(
            station: station,
            icyArtist: 'The Beatles',
          );

          // Assert
          expect(result, isNotNull);
          expect(result!.title, equals('Radio One'));
          expect(result.artist, equals('The Beatles'));
        },
      );

      test(
        '❌ empty icyArtist is treated as null artist even when icyTitle is set',
        () {
          // Arrange
          final station = _station();

          // Act
          final result = buildMediaItem(
            station: station,
            icyTitle: 'Some Track',
            icyArtist: '',
          );

          // Assert
          expect(result, isNotNull);
          expect(result!.title, equals('Some Track'));
          expect(result.artist, isNull);
        },
      );
    });

    // -------------------------------------------------------------------------
    // 4. Deduplication: returns null when MediaItem is identical to current
    // -------------------------------------------------------------------------
    group('deduplication', () {
      test(
        '✅ returns null when new MediaItem would be identical to current',
        () {
          // Arrange — build the item once to establish "current".
          final station = _station(name: 'Jazz FM');
          final first = buildMediaItem(
            station: station,
            icyTitle: 'Miles Davis - Kind of Blue',
          );
          expect(
            first,
            isNotNull,
            reason: 'first call must produce a non-null item',
          );

          // Act — build again with the same inputs.
          final second = buildMediaItem(
            station: station,
            icyTitle: 'Miles Davis - Kind of Blue',
            current: first,
          );

          // Assert
          expect(second, isNull);
        },
      );

      test(
        '✅ returns a new item when title changes (dedup condition not met)',
        () {
          // Arrange
          final station = _station(name: 'Jazz FM');
          final first = buildMediaItem(
            station: station,
            icyTitle: 'Miles Davis - Kind of Blue',
          );

          // Act
          final second = buildMediaItem(
            station: station,
            icyTitle: 'Coltrane - A Love Supreme',
            current: first,
          );

          // Assert
          expect(second, isNotNull);
          expect(second!.title, equals('A Love Supreme'));
        },
      );

      test(
        '✅ returns a new item when artist changes (dedup condition not met)',
        () {
          // Arrange
          final station = _station(name: 'Rock FM');
          final first = buildMediaItem(
            station: station,
            icyTitle: 'Radiohead - Creep',
          );

          // Act — only the artist in the ICY string changes.
          final second = buildMediaItem(
            station: station,
            icyTitle: 'Nirvana - Creep',
            current: first,
          );

          // Assert
          expect(second, isNotNull);
          expect(second!.artist, equals('Nirvana'));
        },
      );

      test(
        '✅ returns a new item when artUri changes (dedup condition not met)',
        () {
          // Arrange — favicon changes between calls.
          final stationA = _station(favicon: 'http://a.example.com/ico.png');
          final first = buildMediaItem(station: stationA);

          final stationB = _station(favicon: 'http://b.example.com/ico.png');

          // Act
          final second = buildMediaItem(station: stationB, current: first);

          // Assert
          expect(second, isNotNull);
          expect(second!.artUri.toString(), contains('b.example.com'));
        },
      );

      test(
        '✅ returns a new item when station extras change with same visible metadata',
        () {
          // Arrange
          final firstStation = _station(
            id: 'station-a',
            name: 'Shared Name',
            url: 'http://stream.example.com/a',
          );
          final secondStation = _station(
            id: 'station-b',
            name: 'Shared Name',
            url: 'http://stream.example.com/b',
          );
          final first = buildMediaItem(
            station: firstStation,
            icyTitle: 'Artist - Song',
          );

          // Act
          final second = buildMediaItem(
            station: secondStation,
            icyTitle: 'Artist - Song',
            current: first,
          );

          // Assert
          expect(second, isNotNull);
          expect(second!.id, equals('http://stream.example.com/b'));
          expect(
            second.extras?[mediaItemStationIdExtrasKey],
            equals('station-b'),
          );
        },
      );

      test(
        '❌ does NOT return null when current is null (first call always builds)',
        () {
          // Arrange
          final station = _station(name: 'Test Station');

          // Act
          final result = buildMediaItem(station: station, current: null);

          // Assert
          expect(result, isNotNull);
        },
      );
    });

    // -------------------------------------------------------------------------
    // 5. artUri from station.favicon
    // -------------------------------------------------------------------------
    group('artUri from station.favicon', () {
      test('✅ uses station.favicon as artUri when non-null and valid', () {
        // Arrange
        final station = _station(favicon: 'https://www.example.com/logo.png');

        // Act
        final result = buildMediaItem(station: station);

        // Assert
        expect(result, isNotNull);
        expect(
          result!.artUri,
          equals(Uri.parse('https://www.example.com/logo.png')),
        );
      });

      test('✅ artUri is null when station.favicon is null', () {
        // Arrange
        final station = _station(favicon: null);

        // Act
        final result = buildMediaItem(station: station);

        // Assert
        expect(result, isNotNull);
        expect(result!.artUri, isNull);
      });

      test('✅ artUri is null when station.favicon is empty string', () {
        // Arrange
        final station = _station(favicon: '');

        // Act
        final result = buildMediaItem(station: station);

        // Assert
        expect(result, isNotNull);
        expect(result!.artUri, isNull);
      });

      test('❌ does not crash when station.favicon is an unparseable string', () {
        // Arrange — Uri.tryParse returns null for malformed URIs.
        final station = _station(favicon: ':::not a uri:::');

        // Act — should not throw.
        final result = buildMediaItem(station: station);

        // Assert
        expect(result, isNotNull);
        // artUri will be null because Uri.tryParse(':::not a uri:::') == null.
        expect(result!.artUri, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // 6. MediaItem field correctness
    // -------------------------------------------------------------------------
    group('MediaItem fields', () {
      test('✅ id is station.urlResolved when available', () {
        // Arrange
        final station = _station(
          url: 'http://raw.example.com',
          urlResolved: 'http://cdn.example.com/stream',
        );

        // Act
        final result = buildMediaItem(station: station);

        // Assert
        expect(result, isNotNull);
        expect(result!.id, equals('http://cdn.example.com/stream'));
      });

      test('✅ id falls back to station.url when urlResolved is null', () {
        // Arrange
        final station = _station(
          url: 'http://raw.example.com',
          urlResolved: null,
        );

        // Act
        final result = buildMediaItem(station: station);

        // Assert
        expect(result, isNotNull);
        expect(result!.id, equals('http://raw.example.com'));
      });

      test('✅ extras contains station JSON', () {
        // Arrange
        final station = _station(name: 'Extras Radio', id: 'extras-1');

        // Act
        final result = buildMediaItem(station: station);

        // Assert
        expect(result, isNotNull);
        expect(result!.extras, isNotNull);
        expect(result.extras!['station'], isA<Map<String, dynamic>>());
        final stationJson = result.extras!['station'] as Map<String, dynamic>;
        expect(stationJson['id'], equals('extras-1'));
        expect(stationJson['name'], equals('Extras Radio'));
      });
    });
  });

  group('restoreStationFromMediaItem()', () {
    test('✅ rehydrates station from serialized extras map', () {
      // Arrange
      final station = _station(id: 'rehydrated', name: 'Rehydrated FM');
      final item = MediaItem(
        id: station.url,
        title: station.name,
        album: station.name,
        extras: {mediaItemStationExtrasKey: station.toJson()},
      );

      // Act
      final restored = restoreStationFromMediaItem(item);

      // Assert
      expect(restored.id, equals('rehydrated'));
      expect(restored.name, equals('Rehydrated FM'));
    });

    test('❌ falls back safely when extras contain malformed station data', () {
      // Arrange
      const item = MediaItem(
        id: 'http://stream.example.com/fallback',
        title: 'Fallback Title',
        album: 'Fallback Station',
        artist: 'Fallback Country',
        extras: {
          mediaItemStationExtrasKey: {'unexpected': 'shape'},
        },
      );

      // Act
      final restored = restoreStationFromMediaItem(item);

      // Assert
      expect(restored.name, equals('Fallback Station'));
      expect(restored.url, equals('http://stream.example.com/fallback'));
      expect(restored.country, equals('Fallback Country'));
    });
  });
}
