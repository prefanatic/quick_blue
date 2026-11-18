import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/src/messages.g.dart' as messages;

final class AndroidBondHarness {
  AndroidBondHarness({
    required messages.PlatformBondState initialState,
    this.repairState = messages.PlatformRepairState.unknown,
  }) : _currentState = initialState;

  static const _bondStateChannel =
      'dev.flutter.pigeon.quick_blue.QuickBlueApi.bondState';
  static const _startPairingChannel =
      'dev.flutter.pigeon.quick_blue.QuickBlueApi.startPairing';
  static const _bondEventChannel =
      'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.bondStateChanges';

  final Map<int, List<Completer<void>>> _bondStateWaiters =
      <int, List<Completer<void>>>{};
  final Completer<void> _startPairingCompleter = Completer<void>();
  late messages.PlatformBondState _currentState;
  int bondStateCalls = 0;
  int startPairingCalls = 0;
  int listenCalls = 0;
  int cancelCalls = 0;
  messages.PlatformRepairState repairState;
  final repairListening = Completer<void>();

  Future<void> get startPairingCalled => _startPairingCompleter.future;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler<Object?>(
      const BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.quick_blue.QuickBlueApi.repairObservation',
        messages.QuickBlueApi.pigeonChannelCodec,
      ),
      (_) async => <Object?>[
        messages.PlatformRepairObservation(
          deviceId: 'device-a',
          generation: 1,
          state: repairState,
        ),
      ],
    );
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.repairChanges',
      (message) async {
        if (message != null &&
            messages.pigeonMethodCodec.decodeMethodCall(message).method ==
                'listen' &&
            !repairListening.isCompleted) {
          repairListening.complete();
        }
        return messages.pigeonMethodCodec.encodeSuccessEnvelope(null);
      },
    );
    messenger.setMockDecodedMessageHandler<Object?>(
      const BasicMessageChannel<Object?>(
        _bondStateChannel,
        messages.QuickBlueApi.pigeonChannelCodec,
      ),
      (_) async {
        bondStateCalls += 1;
        for (final expected in _bondStateWaiters.keys.toList()) {
          if (bondStateCalls >= expected) {
            for (final waiter in _bondStateWaiters.remove(expected)!) {
              waiter.complete();
            }
          }
        }
        return <Object?>[_currentState];
      },
    );
    messenger.setMockDecodedMessageHandler<Object?>(
      const BasicMessageChannel<Object?>(
        _startPairingChannel,
        messages.QuickBlueApi.pigeonChannelCodec,
      ),
      (_) async {
        startPairingCalls += 1;
        if (!_startPairingCompleter.isCompleted) {
          _startPairingCompleter.complete();
        }
        return <Object?>[null];
      },
    );
    messenger.setMockMessageHandler(_bondEventChannel, (
      ByteData? message,
    ) async {
      if (message == null) {
        return null;
      }
      final methodCall = messages.pigeonMethodCodec.decodeMethodCall(message);
      if (methodCall.method == 'listen') {
        listenCalls += 1;
      } else if (methodCall.method == 'cancel') {
        cancelCalls += 1;
      } else {
        fail(
          'Unexpected method call for $_bondEventChannel: '
          '${methodCall.method}',
        );
      }
      return messages.pigeonMethodCodec.encodeSuccessEnvelope(null);
    });
  }

  Future<void> waitForBondStateCalls(int expected) {
    if (bondStateCalls >= expected) {
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _bondStateWaiters
        .putIfAbsent(expected, () => <Completer<void>>[])
        .add(waiter);
    return waiter.future;
  }

  Future<void> emit(messages.PlatformBondState state) async {
    final previousState = _currentState;
    _currentState = state;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _bondEventChannel,
          messages.pigeonMethodCodec.encodeSuccessEnvelope(
            messages.PlatformBondStateChange(
              deviceId: 'device-a',
              state: state,
              previousState: previousState,
            ),
          ),
          (_) {},
        );
    await pumpEventQueue();
  }

  Future<void> emitRepair(messages.PlatformRepairState state) async {
    repairState = state;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.repairChanges',
          messages.pigeonMethodCodec.encodeSuccessEnvelope(
            messages.PlatformRepairObservation(
              deviceId: 'device-a',
              generation: 1,
              state: state,
            ),
          ),
          (_) {},
        );
    await pumpEventQueue();
  }
}
