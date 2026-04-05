// Tests for PointEvent model (point_event.dart)
//
// Covers:
//  ✅ fromJson round-trip with all 7 fields populated
//  ✅ fromJson handles metadata: null gracefully
//  ✅ fromJson handles referenceId: null gracefully
//  ✅ toJson produces correct snake_case keys
//  ✅ displayLabel returns non-empty string for each of the 7 known event types
//  ✅ displayLabel returns a non-empty fallback for an unknown eventType
//  ✅ icon returns an IconData for each of the 7 known event types
//  ✅ == and hashCode work (two instances from same JSON are equal)
//  ❌ Negative: fromJson with unknown eventType still constructs correctly
//  ❌ Negative: displayLabel unknown type does not throw and is non-empty
//  ❌ Negative: equal instances with different metadata are still == (metadata excluded from ==)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:unearth_radio/src/shared/models/point_event.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Returns a fully-populated JSON map suitable for [PointEvent.fromJson].
Map<String, dynamic> _fullJson({
  String id = 'event-uuid-1',
  String userId = 'user-uuid-1',
  String eventType = 'discovery',
  int points = 10,
  Map<String, dynamic>? metadata = const {'station_name': 'Jazz FM'},
  String? referenceId = 'ref-uuid-1',
  String createdAt = '2026-01-15T12:00:00.000Z',
}) {
  return {
    'id': id,
    'user_id': userId,
    'event_type': eventType,
    'points': points,
    'metadata': metadata,
    'reference_id': referenceId,
    'created_at': createdAt,
  };
}

/// All 7 known event type strings, matching the DB constraint.
const _knownEventTypes = [
  'discovery',
  'distance_bonus',
  'obscurity_bonus',
  'share',
  'vote',
  'streak',
  'achievement',
];

void main() {
  group('PointEvent', () {
    // -------------------------------------------------------------------------
    // 1. fromJson — full round-trip
    // -------------------------------------------------------------------------
    group('fromJson', () {
      test('✅ round-trips correctly when all 7 fields are populated', () {
        // Arrange
        final json = _fullJson();

        // Act
        final event = PointEvent.fromJson(json);

        // Assert
        expect(event.id, equals('event-uuid-1'));
        expect(event.userId, equals('user-uuid-1'));
        expect(event.eventType, equals('discovery'));
        expect(event.points, equals(10));
        expect(event.metadata, equals({'station_name': 'Jazz FM'}));
        expect(event.referenceId, equals('ref-uuid-1'));
        expect(
          event.createdAt,
          equals(DateTime.parse('2026-01-15T12:00:00.000Z')),
        );
      });

      test('✅ handles metadata: null gracefully (field is null, no throw)', () {
        // Arrange
        final json = _fullJson(metadata: null);

        // Act
        final event = PointEvent.fromJson(json);

        // Assert
        expect(event.metadata, isNull);
      });

      test(
        '✅ handles referenceId: null gracefully (field is null, no throw)',
        () {
          // Arrange
          final json = _fullJson(referenceId: null);

          // Act
          final event = PointEvent.fromJson(json);

          // Assert
          expect(event.referenceId, isNull);
        },
      );

      test(
        '❌ unknown eventType still constructs correctly (no validation throw)',
        () {
          // Arrange — event type not in the allowed set
          final json = _fullJson(eventType: 'mystery_bonus');

          // Act — should not throw
          final event = PointEvent.fromJson(json);

          // Assert
          expect(event.eventType, equals('mystery_bonus'));
        },
      );
    });

    // -------------------------------------------------------------------------
    // 2. toJson — produces correct snake_case keys
    // -------------------------------------------------------------------------
    group('toJson', () {
      test('✅ produces correct snake_case keys for all fields', () {
        // Arrange
        final json = _fullJson();
        final event = PointEvent.fromJson(json);

        // Act
        final result = event.toJson();

        // Assert — key names use snake_case as DB expects
        expect(
          result.keys,
          containsAll([
            'id',
            'user_id',
            'event_type',
            'points',
            'metadata',
            'reference_id',
            'created_at',
          ]),
        );
        expect(result['id'], equals('event-uuid-1'));
        expect(result['user_id'], equals('user-uuid-1'));
        expect(result['event_type'], equals('discovery'));
        expect(result['points'], equals(10));
        expect(result['metadata'], equals({'station_name': 'Jazz FM'}));
        expect(result['reference_id'], equals('ref-uuid-1'));
        // createdAt is round-tripped as ISO-8601 string
        expect(result['created_at'], isA<String>());
        expect(
          DateTime.parse(result['created_at'] as String),
          equals(DateTime.parse('2026-01-15T12:00:00.000Z')),
        );
      });

      test(
        '✅ toJson includes null for metadata and referenceId when absent',
        () {
          // Arrange
          final json = _fullJson(metadata: null, referenceId: null);
          final event = PointEvent.fromJson(json);

          // Act
          final result = event.toJson();

          // Assert
          expect(result['metadata'], isNull);
          expect(result['reference_id'], isNull);
        },
      );
    });

    // -------------------------------------------------------------------------
    // 3. displayLabel — all known event types + fallback
    // -------------------------------------------------------------------------
    group('displayLabel', () {
      for (final type in _knownEventTypes) {
        test('✅ returns non-empty string for known event type "$type"', () {
          // Arrange
          final event = PointEvent.fromJson(_fullJson(eventType: type));

          // Act
          final label = event.displayLabel;

          // Assert
          expect(label, isNotEmpty);
          // Also verify no raw underscores leak through for known types
          expect(label, isNot(contains('_')));
        });
      }

      test('✅ returns non-empty fallback for unknown eventType', () {
        // Arrange — unknown type is title-cased with underscores replaced
        final event = PointEvent.fromJson(
          _fullJson(eventType: 'custom_event_type'),
        );

        // Act
        final label = event.displayLabel;

        // Assert
        expect(label, isNotEmpty);
        // Fallback title-cases each word and replaces underscores with spaces
        expect(label, equals('Custom Event Type'));
      });

      test('❌ unknown eventType fallback does not throw', () {
        // Arrange
        final event = PointEvent.fromJson(
          _fullJson(eventType: 'totally_unknown_xyz'),
        );

        // Act & Assert — must not throw
        expect(() => event.displayLabel, returnsNormally);
        expect(event.displayLabel, isNotEmpty);
      });

      test('✅ "discovery" maps to "New Discovery"', () {
        // Arrange
        final event = PointEvent.fromJson(_fullJson(eventType: 'discovery'));
        // Act & Assert
        expect(event.displayLabel, equals('New Discovery'));
      });

      test('✅ "distance_bonus" maps to "Distance Bonus"', () {
        final event = PointEvent.fromJson(
          _fullJson(eventType: 'distance_bonus'),
        );
        expect(event.displayLabel, equals('Distance Bonus'));
      });

      test('✅ "obscurity_bonus" maps to "Obscurity Bonus"', () {
        final event = PointEvent.fromJson(
          _fullJson(eventType: 'obscurity_bonus'),
        );
        expect(event.displayLabel, equals('Obscurity Bonus'));
      });

      test('✅ "share" maps to "Shared Station"', () {
        final event = PointEvent.fromJson(_fullJson(eventType: 'share'));
        expect(event.displayLabel, equals('Shared Station'));
      });

      test('✅ "vote" maps to "Station Vote"', () {
        final event = PointEvent.fromJson(_fullJson(eventType: 'vote'));
        expect(event.displayLabel, equals('Station Vote'));
      });

      test('✅ "streak" maps to "Listening Streak"', () {
        final event = PointEvent.fromJson(_fullJson(eventType: 'streak'));
        expect(event.displayLabel, equals('Listening Streak'));
      });

      test('✅ "achievement" maps to "Achievement Unlocked"', () {
        final event = PointEvent.fromJson(_fullJson(eventType: 'achievement'));
        expect(event.displayLabel, equals('Achievement Unlocked'));
      });
    });

    // -------------------------------------------------------------------------
    // 4. icon — all known event types return an IconData
    // -------------------------------------------------------------------------
    group('icon', () {
      for (final type in _knownEventTypes) {
        test('✅ returns an IconData for known event type "$type"', () {
          // Arrange
          final event = PointEvent.fromJson(_fullJson(eventType: type));

          // Act
          final iconData = event.icon;

          // Assert
          expect(iconData, isA<IconData>());
        });
      }

      test('✅ returns fallback IconData for unknown eventType', () {
        // Arrange
        final event = PointEvent.fromJson(
          _fullJson(eventType: 'not_a_real_type'),
        );

        // Act
        final iconData = event.icon;

        // Assert
        expect(iconData, isA<IconData>());
        // Unknown types fall back to Icons.star
        expect(iconData, equals(Icons.star));
      });

      test('❌ unknown eventType icon does not throw', () {
        // Arrange
        final event = PointEvent.fromJson(
          _fullJson(eventType: 'totally_unknown'),
        );

        // Act & Assert
        expect(() => event.icon, returnsNormally);
      });
    });

    // -------------------------------------------------------------------------
    // 5. Equality and hashCode
    // -------------------------------------------------------------------------
    group('== and hashCode', () {
      test('✅ two instances built from the same JSON map are equal', () {
        // Arrange
        final json = _fullJson();

        // Act
        final a = PointEvent.fromJson(json);
        final b = PointEvent.fromJson(json);

        // Assert
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('✅ identical() check is true for same reference', () {
        // Arrange
        final event = PointEvent.fromJson(_fullJson());

        // Act & Assert
        // ignore: unrelated_type_equality_checks
        expect(event == event, isTrue);
      });

      test('❌ instances with different id are not equal', () {
        // Arrange
        final a = PointEvent.fromJson(_fullJson(id: 'id-A'));
        final b = PointEvent.fromJson(_fullJson(id: 'id-B'));

        // Act & Assert
        expect(a, isNot(equals(b)));
      });

      test('❌ instances with different eventType are not equal', () {
        // Arrange
        final a = PointEvent.fromJson(_fullJson(eventType: 'discovery'));
        final b = PointEvent.fromJson(_fullJson(eventType: 'vote'));

        // Act & Assert
        expect(a, isNot(equals(b)));
      });

      test(
        '✅ instances with different metadata are still equal (metadata excluded from ==)',
        () {
          // Arrange — == is defined over id, userId, eventType, points,
          // referenceId, createdAt — NOT metadata.
          final a = PointEvent.fromJson(
            _fullJson(metadata: {'key': 'value-a'}),
          );
          final b = PointEvent.fromJson(
            _fullJson(metadata: {'key': 'value-b'}),
          );

          // Act & Assert
          expect(a, equals(b));
          expect(a.hashCode, equals(b.hashCode));
        },
      );

      test('❌ PointEvent is not equal to an unrelated object', () {
        // Arrange
        final event = PointEvent.fromJson(_fullJson());

        // Act & Assert
        // ignore: unrelated_type_equality_checks
        expect(event == 'not an event', isFalse);
      });
    });
  });
}
