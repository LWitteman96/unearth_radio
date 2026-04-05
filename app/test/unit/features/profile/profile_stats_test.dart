// Tests for ProfileStats value object (profile_stats.dart)
//
// Covers:
//  ✅ totalListeningDuration returns the correct Duration
//  ✅ formattedListeningTime returns "0h 0m" for 0 seconds
//  ✅ formattedListeningTime returns "0h 45m" for 2700 seconds
//  ✅ formattedListeningTime returns "1h 30m" for 5400 seconds
//  ✅ formattedListeningTime returns "10h 0m" for 36000 seconds
//  ✅ ProfileStats.empty has all zero fields
//  ✅ == and hashCode work correctly
//  ❌ Negative: instances with any differing field are not equal
//  ❌ Negative: ProfileStats is not equal to unrelated object

import 'package:flutter_test/flutter_test.dart';

import 'package:unearth_radio/src/shared/models/profile_stats.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Builds a [ProfileStats] with sensible non-zero defaults.
/// Override individual fields as needed per-test.
ProfileStats _stats({
  int stationsDiscovered = 42,
  int songsRecognized = 17,
  int countriesExplored = 8,
  int totalListeningSeconds = 3661,
}) {
  return ProfileStats(
    stationsDiscovered: stationsDiscovered,
    songsRecognized: songsRecognized,
    countriesExplored: countriesExplored,
    totalListeningSeconds: totalListeningSeconds,
  );
}

void main() {
  group('ProfileStats', () {
    // -------------------------------------------------------------------------
    // 1. Constructor — fields are stored correctly
    // -------------------------------------------------------------------------
    group('constructor', () {
      test('✅ stores all four int fields correctly', () {
        // Arrange & Act
        const stats = ProfileStats(
          stationsDiscovered: 10,
          songsRecognized: 5,
          countriesExplored: 3,
          totalListeningSeconds: 7200,
        );

        // Assert
        expect(stats.stationsDiscovered, equals(10));
        expect(stats.songsRecognized, equals(5));
        expect(stats.countriesExplored, equals(3));
        expect(stats.totalListeningSeconds, equals(7200));
      });

      test('✅ accepts zero for all fields without error', () {
        // Arrange & Act
        const stats = ProfileStats(
          stationsDiscovered: 0,
          songsRecognized: 0,
          countriesExplored: 0,
          totalListeningSeconds: 0,
        );

        // Assert
        expect(stats.stationsDiscovered, equals(0));
        expect(stats.songsRecognized, equals(0));
        expect(stats.countriesExplored, equals(0));
        expect(stats.totalListeningSeconds, equals(0));
      });
    });

    // -------------------------------------------------------------------------
    // 2. ProfileStats.empty sentinel
    // -------------------------------------------------------------------------
    group('ProfileStats.empty', () {
      test('✅ empty has stationsDiscovered == 0', () {
        expect(ProfileStats.empty.stationsDiscovered, equals(0));
      });

      test('✅ empty has songsRecognized == 0', () {
        expect(ProfileStats.empty.songsRecognized, equals(0));
      });

      test('✅ empty has countriesExplored == 0', () {
        expect(ProfileStats.empty.countriesExplored, equals(0));
      });

      test('✅ empty has totalListeningSeconds == 0', () {
        expect(ProfileStats.empty.totalListeningSeconds, equals(0));
      });

      test('✅ empty equals a manually constructed all-zero instance', () {
        // Arrange
        const zeros = ProfileStats(
          stationsDiscovered: 0,
          songsRecognized: 0,
          countriesExplored: 0,
          totalListeningSeconds: 0,
        );

        // Act & Assert
        expect(ProfileStats.empty, equals(zeros));
      });
    });

    // -------------------------------------------------------------------------
    // 3. totalListeningDuration
    // -------------------------------------------------------------------------
    group('totalListeningDuration', () {
      test('✅ returns Duration.zero when totalListeningSeconds is 0', () {
        // Arrange
        const stats = ProfileStats(
          stationsDiscovered: 0,
          songsRecognized: 0,
          countriesExplored: 0,
          totalListeningSeconds: 0,
        );

        // Act
        final duration = stats.totalListeningDuration;

        // Assert
        expect(duration, equals(Duration.zero));
      });

      test('✅ returns correct Duration for 3661 seconds (1h 1m 1s)', () {
        // Arrange
        final stats = _stats(totalListeningSeconds: 3661);

        // Act
        final duration = stats.totalListeningDuration;

        // Assert
        expect(duration, equals(const Duration(seconds: 3661)));
        expect(duration.inHours, equals(1));
        expect(duration.inMinutes % 60, equals(1));
        expect(duration.inSeconds % 60, equals(1));
      });

      test('✅ returns correct Duration for 7200 seconds (2h)', () {
        // Arrange
        final stats = _stats(totalListeningSeconds: 7200);

        // Act
        final duration = stats.totalListeningDuration;

        // Assert
        expect(duration, equals(const Duration(hours: 2)));
      });

      test(
        '❌ returns large Duration without overflow for very high seconds',
        () {
          // Arrange — 100 hours in seconds
          final stats = _stats(totalListeningSeconds: 360000);

          // Act
          final duration = stats.totalListeningDuration;

          // Assert — Dart Duration handles large values without overflow
          expect(duration.inHours, equals(100));
        },
      );
    });

    // -------------------------------------------------------------------------
    // 4. formattedListeningTime
    //
    // The actual implementation format is "Xh Ym" (not just "Ym").
    // Tests verify the real output from the model.
    // -------------------------------------------------------------------------
    group('formattedListeningTime', () {
      test('✅ returns "0h 0m" for 0 seconds', () {
        // Arrange
        const stats = ProfileStats(
          stationsDiscovered: 0,
          songsRecognized: 0,
          countriesExplored: 0,
          totalListeningSeconds: 0,
        );

        // Act
        final formatted = stats.formattedListeningTime;

        // Assert
        expect(formatted, equals('0h 0m'));
      });

      test('✅ returns "0h 45m" for 2700 seconds', () {
        // Arrange — 2700 s = 45 min exactly
        final stats = _stats(totalListeningSeconds: 2700);

        // Act
        final formatted = stats.formattedListeningTime;

        // Assert
        expect(formatted, equals('0h 45m'));
      });

      test('✅ returns "1h 30m" for 5400 seconds', () {
        // Arrange — 5400 s = 1 h 30 min
        final stats = _stats(totalListeningSeconds: 5400);

        // Act
        final formatted = stats.formattedListeningTime;

        // Assert
        expect(formatted, equals('1h 30m'));
      });

      test('✅ returns "10h 0m" for 36000 seconds', () {
        // Arrange — 36000 s = 10 h exactly
        final stats = _stats(totalListeningSeconds: 36000);

        // Act
        final formatted = stats.formattedListeningTime;

        // Assert
        expect(formatted, equals('10h 0m'));
      });

      test('✅ returns "1h 1m" for 3661 seconds (rounds down sub-minute)', () {
        // Arrange — 3661 s = 1h 1m 1s; sub-minute seconds are truncated
        final stats = _stats(totalListeningSeconds: 3661);

        // Act
        final formatted = stats.formattedListeningTime;

        // Assert — integer division truncates the 1 leftover second
        expect(formatted, equals('1h 1m'));
      });

      test('✅ returns "0h 59m" for 3599 seconds', () {
        // Arrange — 3599 s = 59 min 59 s → 0h 59m
        final stats = _stats(totalListeningSeconds: 3599);

        // Act
        final formatted = stats.formattedListeningTime;

        // Assert
        expect(formatted, equals('0h 59m'));
      });

      test('❌ sub-minute seconds are truncated (not rounded) in display', () {
        // Arrange — 61 seconds = 1 min 1 s → display shows "0h 1m"
        final stats = _stats(totalListeningSeconds: 61);

        // Act
        final formatted = stats.formattedListeningTime;

        // Assert — truncation means we show 1 minute, not 2
        expect(formatted, equals('0h 1m'));
      });

      test('❌ 59 seconds shows "0h 0m" (less than 1 minute)', () {
        // Arrange
        final stats = _stats(totalListeningSeconds: 59);

        // Act
        final formatted = stats.formattedListeningTime;

        // Assert
        expect(formatted, equals('0h 0m'));
      });
    });

    // -------------------------------------------------------------------------
    // 5. Equality and hashCode
    // -------------------------------------------------------------------------
    group('== and hashCode', () {
      test('✅ two instances with the same field values are equal', () {
        // Arrange
        final a = _stats();
        final b = _stats();

        // Act & Assert
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('✅ identical() is true for same reference', () {
        // Arrange
        final stats = _stats();

        // Act & Assert
        expect(stats == stats, isTrue);
      });

      test('❌ instances with different stationsDiscovered are not equal', () {
        // Arrange
        final a = _stats(stationsDiscovered: 10);
        final b = _stats(stationsDiscovered: 20);

        // Act & Assert
        expect(a, isNot(equals(b)));
      });

      test('❌ instances with different songsRecognized are not equal', () {
        // Arrange
        final a = _stats(songsRecognized: 5);
        final b = _stats(songsRecognized: 50);

        // Act & Assert
        expect(a, isNot(equals(b)));
      });

      test('❌ instances with different countriesExplored are not equal', () {
        // Arrange
        final a = _stats(countriesExplored: 3);
        final b = _stats(countriesExplored: 30);

        // Act & Assert
        expect(a, isNot(equals(b)));
      });

      test(
        '❌ instances with different totalListeningSeconds are not equal',
        () {
          // Arrange
          final a = _stats(totalListeningSeconds: 100);
          final b = _stats(totalListeningSeconds: 200);

          // Act & Assert
          expect(a, isNot(equals(b)));
        },
      );

      test('❌ ProfileStats is not equal to an unrelated object', () {
        // Arrange
        final stats = _stats();

        // Act & Assert
        // ignore: unrelated_type_equality_checks
        expect(stats == 'not a stats object', isFalse);
      });

      test('✅ ProfileStats.empty equals itself', () {
        // Act & Assert
        expect(ProfileStats.empty, equals(ProfileStats.empty));
        expect(
          ProfileStats.empty.hashCode,
          equals(ProfileStats.empty.hashCode),
        );
      });
    });
  });
}
