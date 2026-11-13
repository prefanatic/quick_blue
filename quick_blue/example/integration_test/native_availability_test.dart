import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue/src/availability.g.dart';
import 'package:quick_blue_example/multi_engine_worker.dart';

import 'support/multi_engine_test_support.dart';

const _control = MethodChannel('quick_blue.example/multi_engine_control');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native availability is engine-scoped and detached handles fail', (
    tester,
  ) async {
    expect(multiEngineWorkerEntrypointReference, isA<Function>());
    // Resolve the first native client only AFTER a second engine registers.
    await startSecondaryEngine();
    var primaryDetached = false;
    try {
      await _control.invokeMethod<void>('disablePrimaryHostChannels');
      final primary = QuickBlueAndroid();
      expect(await primary.isBluetoothAvailable(), isA<bool>());
      expect(
        await callMultiEngineWorker<bool>('isBluetoothAvailable', ''),
        isA<bool>(),
      );
      await stopSecondaryEngine();
      expect(await primary.isBluetoothAvailable(), isA<bool>());
      await startSecondaryEngine();
      await _control.invokeMethod<void>('detachPrimaryPlugin');
      primaryDetached = true;
      await expectLater(
        primary.isBluetoothAvailable(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'unregistered-instance',
          ),
        ),
      );
      // A new lookup must not borrow the still-running secondary engine.
      expect(
        () => QuickBlueAvailabilityApi.createWithNativeInteropApi(
          messageChannelSuffix:
              'quick_blue.availability.${PlatformDispatcher.instance.engineId}',
        ),
        throwsArgumentError,
      );
      expect(
        await callMultiEngineWorker<bool>('isBluetoothAvailable', ''),
        isA<bool>(),
      );
    } finally {
      if (primaryDetached) {
        await _control.invokeMethod<void>('attachPrimaryPlugin');
      }
      await stopSecondaryEngine();
    }
  });
}
