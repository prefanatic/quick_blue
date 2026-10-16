import 'dart:async';

import 'package:test/test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/fake_quick_blue_platform.dart';

void main() {
  // Independent Dart platform instances model engine-local wait tables over
  // shared native work. These tests do not replace hardware multi-engine tests.
  for (final operation in [
    'connect',
    'disconnect',
    'discoverServices',
    'requestMtu',
  ]) {
    for (final expiresByTimeout in [false, true]) {
      test(
        '$operation ${expiresByTimeout ? 'timeout' : 'cancellation'} in one engine leaves the other engine waiting',
        () async {
          final native = Completer<int>();
          final firstEngine = _SharedNativePlatform(native);
          final secondEngine = _SharedNativePlatform(native);
          addTearDown(firstEngine.dispose);
          addTearDown(secondEngine.dispose);
          Future<dynamic> call(
            QuickBluePlatform platform, {
            QuickBlueCancellationToken? token,
            Duration? timeout,
          }) {
            final device = platform.device('a');
            return switch (operation) {
              'connect' => device.connect(
                cancellationToken: token,
                timeout: timeout,
              ),
              'disconnect' => device.disconnect(
                cancellationToken: token,
                timeout: timeout,
              ),
              'discoverServices' => device.discoverServices(
                cancellationToken: token,
                timeout: timeout,
              ),
              _ => device.requestMtu(
                247,
                cancellationToken: token,
                timeout: timeout,
              ),
            };
          }

          final token = QuickBlueCancellationToken();
          final abandoned = call(
            firstEngine,
            token: token,
            timeout: expiresByTimeout ? Duration.zero : null,
          );
          final expectation = expectLater(
            abandoned,
            throwsA(
              expiresByTimeout
                  ? isA<TimeoutException>()
                  : isA<QuickBlueException>(),
            ),
          );
          var otherCompleted = false;
          final survivor = call(
            secondEngine,
          ).then((_) => otherCompleted = true);
          if (!expiresByTimeout) token.cancel();
          await expectation;
          final retry = call(firstEngine);
          await pumpEventQueue();
          expect(otherCompleted, isFalse);
          expect(firstEngine.calls, [operation]);
          expect(secondEngine.calls, [operation]);
          native.complete(247);
          await survivor;
          await retry;
          expect(otherCompleted, isTrue);
        },
      );
    }
  }
}

class _SharedNativePlatform extends FakeQuickBluePlatform {
  _SharedNativePlatform(this.native);
  final Completer<int> native;

  @override
  Future<void> connect(String deviceId) async {
    calls.add('connect');
    await native.future;
    onConnectionChanged!(
      deviceId,
      BlueConnectionState.connected,
      BleStatus.success,
    );
  }

  @override
  Future<void> disconnect(String deviceId) async {
    calls.add('disconnect');
    await native.future;
    onConnectionChanged!(
      deviceId,
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    calls.add('discoverServices');
    await native.future;
    onServiceDiscoveryComplete(deviceId);
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    calls.add('requestMtu');
    return native.future;
  }
}
