// Tests for LeaderboardEntry model (leaderboard_entry.dart)
//
// Covers:
//  ✅ fromJson handles rank as int (e.g. 1) — normal Dart/Supabase path
//  ✅ fromJson handles rank as double (e.g. 1.0) — PostgreSQL bigint quirk
//  ✅ fromJson handles avatarUrl: null gracefully
//  ✅ fromJson round-trip with all fields populated
//  ✅ toJson produces correct snake_case keys
//  ✅ == and hashCode work correctly (two instances from same JSON are equal)
//  ❌ Negative: instances with different rank are not equal
//  ❌ Negative: instances with different id are not equal
//  ❌ Negative: non-LeaderboardEntry object is not equal

import 'package:flutter_test/flutter_test.dart';

import 'package:unearth_radio/src/shared/models/leaderboard_entry.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Builds a JSON map for [LeaderboardEntry.fromJson].
/// [rank] can be an [int] or [double] to exercise both DB serialisation paths.
Map<String, dynamic> _entryJson({
  String id = 'user-uuid-1',
  String displayName = 'Alice',
  String? avatarUrl = 'https://example.com/avatar.png',
  int totalPoints = 1500,
  Object rank = 1, // int or double
}) {
  return {
    'id': id,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'total_points': totalPoints,
    'rank': rank,
  };
}

void main() {
  group('LeaderboardEntry', () {
    // -------------------------------------------------------------------------
    // 1. fromJson — parsing variations
    // -------------------------------------------------------------------------
    group('fromJson', () {
      test('✅ round-trip with all fields populated', () {
        // Arrange
        final json = _entryJson();

        // Act
        final entry = LeaderboardEntry.fromJson(json);

        // Assert
        expect(entry.id, equals('user-uuid-1'));
        expect(entry.displayName, equals('Alice'));
        expect(entry.avatarUrl, equals('https://example.com/avatar.png'));
        expect(entry.totalPoints, equals(1500));
        expect(entry.rank, equals(1));
      });

      test('✅ handles rank as int (normal Supabase Dart client path)', () {
        // Arrange — rank supplied as a plain int (most common path)
        final json = _entryJson(rank: 3);

        // Act
        final entry = LeaderboardEntry.fromJson(json);

        // Assert
        expect(entry.rank, equals(3));
        expect(entry.rank, isA<int>());
      });

      test('✅ handles rank as double (PostgreSQL bigint quirk)', () {
        // Arrange — PostgreSQL bigint may deserialise as double in some envs
        final json = _entryJson(rank: 1.0);

        // Act
        final entry = LeaderboardEntry.fromJson(json);

        // Assert — fromJson casts via (num).toInt()
        expect(entry.rank, equals(1));
        expect(entry.rank, isA<int>());
      });

      test('✅ handles rank: 2.0 (double) correctly toInt', () {
        // Arrange
        final json = _entryJson(rank: 2.0);

        // Act
        final entry = LeaderboardEntry.fromJson(json);

        // Assert
        expect(entry.rank, equals(2));
      });

      test('✅ handles avatarUrl: null gracefully', () {
        // Arrange
        final json = _entryJson(avatarUrl: null);

        // Act
        final entry = LeaderboardEntry.fromJson(json);

        // Assert
        expect(entry.avatarUrl, isNull);
      });

      test('✅ handles totalPoints = 0 (new user with no points)', () {
        // Arrange
        final json = _entryJson(totalPoints: 0);

        // Act
        final entry = LeaderboardEntry.fromJson(json);

        // Assert
        expect(entry.totalPoints, equals(0));
      });

      test('❌ high rank value (e.g. 999) is preserved correctly', () {
        // Arrange — user with many peers ranked far down the list
        final json = _entryJson(rank: 999);

        // Act
        final entry = LeaderboardEntry.fromJson(json);

        // Assert
        expect(entry.rank, equals(999));
      });
    });

    // -------------------------------------------------------------------------
    // 2. toJson — correct key names
    // -------------------------------------------------------------------------
    group('toJson', () {
      test('✅ produces correct snake_case keys for all fields', () {
        // Arrange
        final json = _entryJson();
        final entry = LeaderboardEntry.fromJson(json);

        // Act
        final result = entry.toJson();

        // Assert — keys match DB column names
        expect(
          result.keys,
          containsAll([
            'id',
            'display_name',
            'avatar_url',
            'total_points',
            'rank',
          ]),
        );
        expect(result['id'], equals('user-uuid-1'));
        expect(result['display_name'], equals('Alice'));
        expect(result['avatar_url'], equals('https://example.com/avatar.png'));
        expect(result['total_points'], equals(1500));
        expect(result['rank'], equals(1));
      });

      test('✅ toJson includes null for avatarUrl when absent', () {
        // Arrange
        final entry = LeaderboardEntry.fromJson(_entryJson(avatarUrl: null));

        // Act
        final result = entry.toJson();

        // Assert
        expect(result['avatar_url'], isNull);
      });

      test('✅ rank in toJson is an int (not double)', () {
        // Arrange — even if rank arrived as double it is stored as int
        final entry = LeaderboardEntry.fromJson(_entryJson(rank: 5.0));

        // Act
        final result = entry.toJson();

        // Assert
        expect(result['rank'], equals(5));
        expect(result['rank'], isA<int>());
      });
    });

    // -------------------------------------------------------------------------
    // 3. Equality and hashCode
    // -------------------------------------------------------------------------
    group('== and hashCode', () {
      test('✅ two instances built from the same JSON map are equal', () {
        // Arrange
        final json = _entryJson();

        // Act
        final a = LeaderboardEntry.fromJson(json);
        final b = LeaderboardEntry.fromJson(json);

        // Assert
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('✅ identical() is true for same reference', () {
        // Arrange
        final entry = LeaderboardEntry.fromJson(_entryJson());

        // Act & Assert
        expect(entry == entry, isTrue);
      });

      test('❌ instances with different id are not equal', () {
        // Arrange
        final a = LeaderboardEntry.fromJson(_entryJson(id: 'id-A'));
        final b = LeaderboardEntry.fromJson(_entryJson(id: 'id-B'));

        // Act & Assert
        expect(a, isNot(equals(b)));
        expect(a.hashCode, isNot(equals(b.hashCode)));
      });

      test('❌ instances with different rank are not equal', () {
        // Arrange
        final a = LeaderboardEntry.fromJson(_entryJson(rank: 1));
        final b = LeaderboardEntry.fromJson(_entryJson(rank: 2));

        // Act & Assert
        expect(a, isNot(equals(b)));
      });

      test('❌ instances with different displayName are not equal', () {
        // Arrange
        final a = LeaderboardEntry.fromJson(_entryJson(displayName: 'Alice'));
        final b = LeaderboardEntry.fromJson(_entryJson(displayName: 'Bob'));

        // Act & Assert
        expect(a, isNot(equals(b)));
      });

      test('❌ instances with different totalPoints are not equal', () {
        // Arrange
        final a = LeaderboardEntry.fromJson(_entryJson(totalPoints: 100));
        final b = LeaderboardEntry.fromJson(_entryJson(totalPoints: 200));

        // Act & Assert
        expect(a, isNot(equals(b)));
      });

      test(
        '✅ instances with same id but different avatarUrl are not equal',
        () {
          // Arrange — avatarUrl is included in == and hashCode
          final a = LeaderboardEntry.fromJson(
            _entryJson(avatarUrl: 'https://a.example.com/avatar.png'),
          );
          final b = LeaderboardEntry.fromJson(
            _entryJson(avatarUrl: 'https://b.example.com/avatar.png'),
          );

          // Act & Assert
          expect(a, isNot(equals(b)));
        },
      );

      test('❌ LeaderboardEntry is not equal to an unrelated object', () {
        // Arrange
        final entry = LeaderboardEntry.fromJson(_entryJson());

        // Act & Assert
        // ignore: unrelated_type_equality_checks
        expect(entry == 'not an entry', isFalse);
      });
    });
  });
}
