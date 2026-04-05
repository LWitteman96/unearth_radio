// Tests for PlayerState and PlayerNotifier (playerProvider) in player_provider.dart
//
// Strategy: avoid instantiating RadioAudioHandler (which starts real just_audio
// platform channels). Instead, we:
//  1. Test PlayerState pure Dart logic directly (no platform dependencies).
//  2. Test PlayerNotifier by overriding backgroundAudioHandlerProvider with a
//     FakeRadioAudioHandler that emits snapshots from a StreamController.
//
// Covers:
//  ✅ PlayerState default values are correct
//  ✅ PlayerState.copyWith replaces provided fields
//  ✅ copyWith with explicit null clears currentStation
//  ✅ copyWith with no args keeps all existing values
//  ✅ currentUrl prefers urlResolved over url
//  ✅ currentUrl is null when no station
//  ✅ PlayerNotifier initial state mirrors handler snapshot
//  ✅ PlayerNotifier reacts to snapshot stream emissions
//  ❌ currentUrl returns null when currentStation is null
//  ❌ PlayerState.hasError defaults to false (not an error state)

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

import 'package:unearth_radio/src/features/player/providers/player_provider.dart'
    as player_provider
    show
        PlayerState,
        PlayerNotifier,
        playerProvider,
        backgroundAudioHandlerProvider;
import 'package:unearth_radio/src/features/player/services/radio_audio_handler.dart';
import 'package:unearth_radio/src/shared/models/station.dart';

// Convenient aliases to avoid just_audio.PlayerState vs PlayerState ambiguity
typedef AppPlayerState = player_provider.PlayerState;

// ---------------------------------------------------------------------------
// Fake RadioAudioHandler — no real audio platform channels
// ---------------------------------------------------------------------------

/// A minimal fake for [RadioAudioHandler] that does NOT instantiate
/// `AudioPlayer` or touch any platform channels.
///
/// It exposes a [StreamController] so tests can push [RadioPlaybackSnapshot]
/// events and observe provider reactions.
class _FakeRadioAudioHandler extends Fake implements RadioAudioHandler {
  _FakeRadioAudioHandler({RadioPlaybackSnapshot? initialSnapshot})
    : _snapshot = initialSnapshot ?? const RadioPlaybackSnapshot(),
      _controller = StreamController<RadioPlaybackSnapshot>.broadcast();

  RadioPlaybackSnapshot _snapshot;
  final StreamController<RadioPlaybackSnapshot> _controller;
  final List<Station> playedStations = [];
  var pauseCallCount = 0;
  var stopCallCount = 0;

  @override
  RadioPlaybackSnapshot get snapshot => _snapshot;

  @override
  Stream<RadioPlaybackSnapshot> get snapshotStream => _controller.stream;

  /// Push a new snapshot to subscribed listeners.
  void emit(RadioPlaybackSnapshot s) {
    _snapshot = s;
    _controller.add(s);
  }

  void closeController() => _controller.close();

  // --- Stubs for playback controls (not called in provider-state tests) ---

  @override
  Future<void> playStation(Station station) async {
    playedStations.add(station);
  }

  @override
  Future<void> pause() async {
    pauseCallCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCallCount += 1;
  }

  // --- Stub audioPlayer to prevent real platform channel access ---
  @override
  just_audio.AudioPlayer get audioPlayer {
    throw UnsupportedError(
      '_FakeRadioAudioHandler.audioPlayer must not be called in these tests',
    );
  }

  @override
  Future<void> updateIcyMetadata({String? rawTitle, String? artist}) async {}
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Station _testStation({
  String id = 'st-1',
  String name = 'Test Station',
  String url = 'http://stream.test/radio',
  String? urlResolved,
}) {
  return Station(
    id: id,
    rbId: id,
    name: name,
    url: url,
    urlResolved: urlResolved,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // PlayerState — pure Dart, no platform dependencies
  // =========================================================================
  group('PlayerState', () {
    group('default constructor', () {
      test('✅ isPlaying defaults to false', () {
        // Arrange + Act
        const state = AppPlayerState();

        // Assert
        expect(state.isPlaying, isFalse);
      });

      test('✅ isLoading defaults to false', () {
        // Arrange + Act
        const state = AppPlayerState();

        // Assert
        expect(state.isLoading, isFalse);
      });

      test('✅ currentStation defaults to null', () {
        // Arrange + Act
        const state = AppPlayerState();

        // Assert
        expect(state.currentStation, isNull);
      });

      test('✅ hasError defaults to false', () {
        // Arrange + Act
        const state = AppPlayerState();

        // Assert
        expect(state.hasError, isFalse);
      });

      test('❌ default state is NOT an error state', () {
        // Arrange + Act
        const state = AppPlayerState();

        // Assert — guard against false-positive error display on fresh launch.
        expect(state.hasError, isFalse);
      });
    });

    group('currentUrl', () {
      test('✅ is null when currentStation is null', () {
        // Arrange
        const state = AppPlayerState();

        // Act + Assert
        expect(state.currentUrl, isNull);
      });

      test(
        '❌ currentUrl returns null when currentStation is explicitly null',
        () {
          // Arrange
          // ignore: avoid_redundant_argument_values
          const state = AppPlayerState(currentStation: null);

          // Assert
          expect(state.currentUrl, isNull);
        },
      );

      test('✅ prefers urlResolved when both url and urlResolved are set', () {
        // Arrange
        final station = _testStation(
          url: 'http://raw.example.com',
          urlResolved: 'http://cdn.example.com/stream',
        );
        final state = AppPlayerState(currentStation: station);

        // Act + Assert
        expect(state.currentUrl, equals('http://cdn.example.com/stream'));
      });

      test('✅ falls back to url when urlResolved is null', () {
        // Arrange
        final station = _testStation(
          url: 'http://raw.example.com',
          urlResolved: null,
        );
        final state = AppPlayerState(currentStation: station);

        // Act + Assert
        expect(state.currentUrl, equals('http://raw.example.com'));
      });
    });

    group('copyWith()', () {
      test('✅ replaces isPlaying when provided', () {
        // Arrange
        const state = AppPlayerState(isPlaying: false);

        // Act
        final next = state.copyWith(isPlaying: true);

        // Assert
        expect(next.isPlaying, isTrue);
      });

      test('✅ replaces isLoading when provided', () {
        // Arrange
        const state = AppPlayerState(isLoading: false);

        // Act
        final next = state.copyWith(isLoading: true);

        // Assert
        expect(next.isLoading, isTrue);
      });

      test('✅ replaces hasError when provided', () {
        // Arrange
        const state = AppPlayerState(hasError: false);

        // Act
        final next = state.copyWith(hasError: true);

        // Assert
        expect(next.hasError, isTrue);
      });

      test('✅ replaces currentStation when provided', () {
        // Arrange
        final original = _testStation(name: 'Original');
        final replacement = _testStation(name: 'Replacement', id: 'st-2');
        final state = AppPlayerState(currentStation: original);

        // Act
        final next = state.copyWith(currentStation: replacement);

        // Assert
        expect(next.currentStation?.name, equals('Replacement'));
      });

      test('✅ rehydrates serialized currentStation maps during copyWith', () {
        // Arrange
        const state = AppPlayerState();
        final serializedStation = _testStation(
          id: 'st-map',
          name: 'Map Station',
        ).toJson();

        // Act
        final next = state.copyWith(currentStation: serializedStation);

        // Assert
        expect(next.currentStation?.id, equals('st-map'));
        expect(next.currentStation?.name, equals('Map Station'));
      });

      test('✅ passing explicit null for currentStation clears the field', () {
        // Arrange
        final station = _testStation();
        final state = AppPlayerState(currentStation: station);

        // Act — explicit null should clear (sentinel trick).
        final next = state.copyWith(currentStation: null);

        // Assert
        expect(next.currentStation, isNull);
      });

      test('✅ omitting currentStation keeps the existing value', () {
        // Arrange
        final station = _testStation(name: 'Keep Me');
        final state = AppPlayerState(currentStation: station);

        // Act — no currentStation argument.
        final next = state.copyWith(isPlaying: true);

        // Assert
        expect(next.currentStation?.name, equals('Keep Me'));
      });

      test('✅ no-arg copyWith preserves all fields', () {
        // Arrange
        final station = _testStation(name: 'Full State');
        final base = const AppPlayerState(
          isPlaying: true,
          isLoading: true,
          hasError: true,
        );
        final stateWithStation = base.copyWith(currentStation: station);

        // Act
        final next = stateWithStation.copyWith();

        // Assert
        expect(next.isPlaying, isTrue);
        expect(next.isLoading, isTrue);
        expect(next.hasError, isTrue);
        expect(next.currentStation?.name, equals('Full State'));
      });
    });
  });

  // =========================================================================
  // PlayerNotifier — uses ProviderContainer with fake handler override
  // =========================================================================
  group('PlayerNotifier (via ProviderContainer)', () {
    late _FakeRadioAudioHandler fakeHandler;
    late ProviderContainer container;

    setUp(() {
      fakeHandler = _FakeRadioAudioHandler();
      container = ProviderContainer(
        overrides: [
          player_provider.backgroundAudioHandlerProvider.overrideWithValue(
            fakeHandler,
          ),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      fakeHandler.closeController();
    });

    test('✅ initial state mirrors the handler snapshot (all defaults)', () {
      // Arrange — handler has default snapshot (isPlaying: false, etc.)

      // Act
      final state = container.read(player_provider.playerProvider);

      // Assert
      expect(state.isPlaying, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.currentStation, isNull);
      expect(state.hasError, isFalse);
    });

    test('✅ initial state reflects non-default handler snapshot', () {
      // Arrange — pre-load handler with an active station snapshot.
      final station = _testStation(name: 'Pre-loaded FM');
      final preloadedHandler = _FakeRadioAudioHandler(
        initialSnapshot: RadioPlaybackSnapshot(
          isPlaying: true,
          isLoading: false,
          currentStation: station,
        ),
      );
      final localContainer = ProviderContainer(
        overrides: [
          player_provider.backgroundAudioHandlerProvider.overrideWithValue(
            preloadedHandler,
          ),
        ],
      );
      addTearDown(() {
        localContainer.dispose();
        preloadedHandler.closeController();
      });

      // Act
      final state = localContainer.read(player_provider.playerProvider);

      // Assert
      expect(state.isPlaying, isTrue);
      expect(state.currentStation?.name, equals('Pre-loaded FM'));
    });

    test('✅ state updates when handler emits a new snapshot', () async {
      // Arrange — read the provider to subscribe it.
      container.read(player_provider.playerProvider);

      // Act
      final station = _testStation(name: 'Live FM');
      fakeHandler.emit(
        RadioPlaybackSnapshot(isPlaying: true, currentStation: station),
      );

      // Yield to the event loop so the stream listener fires.
      await Future<void>.delayed(Duration.zero);

      // Assert
      final state = container.read(player_provider.playerProvider);
      expect(state.isPlaying, isTrue);
      expect(state.currentStation?.name, equals('Live FM'));
    });

    test(
      '✅ play forwards the requested station to the background handler',
      () async {
        // Arrange
        final station = _testStation(id: 'play-id', name: 'Play FM');
        final notifier = container.read(
          player_provider.playerProvider.notifier,
        );

        // Act
        await notifier.play(station);

        // Assert
        expect(fakeHandler.playedStations, hasLength(1));
        expect(fakeHandler.playedStations.single.id, equals('play-id'));
        expect(fakeHandler.playedStations.single.name, equals('Play FM'));
      },
    );

    test(
      '❌ pause does not trigger play and only forwards pause to the handler',
      () async {
        // Arrange
        final notifier = container.read(
          player_provider.playerProvider.notifier,
        );

        // Act
        await notifier.pause();

        // Assert
        expect(fakeHandler.pauseCallCount, equals(1));
        expect(fakeHandler.playedStations, isEmpty);
      },
    );

    test('✅ stop forwards to the background handler', () async {
      // Arrange
      final notifier = container.read(player_provider.playerProvider.notifier);

      // Act
      await notifier.stop();

      // Assert
      expect(fakeHandler.stopCallCount, equals(1));
    });

    test(
      '✅ toggle plays a new station when switching away from the current station',
      () async {
        // Arrange
        final currentStation = _testStation(
          id: 'current-id',
          name: 'Current FM',
        );
        final nextStation = _testStation(id: 'next-id', name: 'Next FM');
        final switchingHandler = _FakeRadioAudioHandler(
          initialSnapshot: RadioPlaybackSnapshot(
            isPlaying: true,
            currentStation: currentStation,
          ),
        );
        final localContainer = ProviderContainer(
          overrides: [
            player_provider.backgroundAudioHandlerProvider.overrideWithValue(
              switchingHandler,
            ),
          ],
        );
        addTearDown(() {
          localContainer.dispose();
          switchingHandler.closeController();
        });
        final notifier = localContainer.read(
          player_provider.playerProvider.notifier,
        );

        // Act
        await notifier.toggle(nextStation);

        // Assert
        expect(switchingHandler.playedStations, hasLength(1));
        expect(switchingHandler.playedStations.single.id, equals('next-id'));
        expect(switchingHandler.pauseCallCount, equals(0));
      },
    );

    test(
      '❌ toggle resumes via play when the same station is selected while paused',
      () async {
        // Arrange
        final station = _testStation(id: 'paused-id', name: 'Paused FM');
        final pausedHandler = _FakeRadioAudioHandler(
          initialSnapshot: RadioPlaybackSnapshot(
            isPlaying: false,
            currentStation: station,
          ),
        );
        final localContainer = ProviderContainer(
          overrides: [
            player_provider.backgroundAudioHandlerProvider.overrideWithValue(
              pausedHandler,
            ),
          ],
        );
        addTearDown(() {
          localContainer.dispose();
          pausedHandler.closeController();
        });
        final notifier = localContainer.read(
          player_provider.playerProvider.notifier,
        );

        // Act
        await notifier.toggle(station);

        // Assert
        expect(pausedHandler.playedStations, hasLength(1));
        expect(pausedHandler.playedStations.single.id, equals('paused-id'));
        expect(pausedHandler.pauseCallCount, equals(0));
      },
    );

    test(
      '✅ state rehydrates serialized stations emitted by the handler',
      () async {
        // Arrange
        container.read(player_provider.playerProvider);

        // Act
        fakeHandler.emit(
          RadioPlaybackSnapshot(
            isPlaying: true,
            currentStation: _testStation(
              id: 'serialized',
              name: 'Serialized Snapshot FM',
            ).toJson(),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Assert
        final state = container.read(player_provider.playerProvider);
        expect(state.isPlaying, isTrue);
        expect(state.currentStation?.id, equals('serialized'));
        expect(state.currentStation?.name, equals('Serialized Snapshot FM'));
      },
    );

    test('✅ isLoading updates when handler emits loading snapshot', () async {
      // Arrange
      container.read(player_provider.playerProvider);

      // Act
      fakeHandler.emit(const RadioPlaybackSnapshot(isLoading: true));
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(container.read(player_provider.playerProvider).isLoading, isTrue);
    });

    test('✅ hasError updates when handler emits error snapshot', () async {
      // Arrange
      container.read(player_provider.playerProvider);

      // Act
      fakeHandler.emit(const RadioPlaybackSnapshot(hasError: true));
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(container.read(player_provider.playerProvider).hasError, isTrue);
    });

    test(
      '✅ state clears station when handler emits snapshot with null station',
      () async {
        // Arrange — start with a station loaded.
        final stationHandler = _FakeRadioAudioHandler(
          initialSnapshot: RadioPlaybackSnapshot(
            isPlaying: true,
            currentStation: _testStation(),
          ),
        );
        final localContainer = ProviderContainer(
          overrides: [
            player_provider.backgroundAudioHandlerProvider.overrideWithValue(
              stationHandler,
            ),
          ],
        );
        addTearDown(() {
          localContainer.dispose();
          stationHandler.closeController();
        });
        localContainer.read(player_provider.playerProvider);

        // Act — emit a stopped snapshot.
        stationHandler.emit(const RadioPlaybackSnapshot());
        await Future<void>.delayed(Duration.zero);

        // Assert
        final state = localContainer.read(player_provider.playerProvider);
        expect(state.currentStation, isNull);
        expect(state.isPlaying, isFalse);
      },
    );

    test('❌ provider is NOT in error state on fresh init', () {
      // Act
      final state = container.read(player_provider.playerProvider);

      // Assert — guard against accidental error-state display on cold start.
      expect(state.hasError, isFalse);
    });

    test(
      '❌ toggle calls pause (not play) when same station is already playing',
      () async {
        // Arrange — handler snapshot shows the station is already playing.
        final station = _testStation(id: 'same-id');
        var pauseCalled = false;
        final trackingHandler = _FakeRadioAudioHandler(
          initialSnapshot: RadioPlaybackSnapshot(
            isPlaying: true,
            currentStation: station,
          ),
        );

        // Replace pause() via override so we can observe it.
        final pauseTracker = _PauseTrackingHandler(
          delegate: trackingHandler,
          onPause: () => pauseCalled = true,
        );
        final localContainer = ProviderContainer(
          overrides: [
            player_provider.backgroundAudioHandlerProvider.overrideWithValue(
              pauseTracker,
            ),
          ],
        );
        addTearDown(() {
          localContainer.dispose();
          trackingHandler.closeController();
        });
        localContainer.read(player_provider.playerProvider);

        // Act — toggle the same station that is already playing → should pause.
        await localContainer
            .read(player_provider.playerProvider.notifier)
            .toggle(station);

        // Assert — pause must have been called, not play.
        expect(pauseCalled, isTrue);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helper: wraps a _FakeRadioAudioHandler to track pause() calls.
// ---------------------------------------------------------------------------
class _PauseTrackingHandler extends Fake implements RadioAudioHandler {
  _PauseTrackingHandler({
    required _FakeRadioAudioHandler delegate,
    required void Function() onPause,
  }) : _delegate = delegate,
       _onPause = onPause;

  final _FakeRadioAudioHandler _delegate;
  final void Function() _onPause;

  @override
  RadioPlaybackSnapshot get snapshot => _delegate.snapshot;

  @override
  Stream<RadioPlaybackSnapshot> get snapshotStream => _delegate.snapshotStream;

  @override
  Future<void> pause() async {
    _onPause();
  }

  @override
  Future<void> playStation(Station station) async {}

  @override
  Future<void> stop() async {}

  @override
  just_audio.AudioPlayer get audioPlayer {
    throw UnsupportedError('audioPlayer not available in tracking handler');
  }

  @override
  Future<void> updateIcyMetadata({String? rawTitle, String? artist}) async {}
}
