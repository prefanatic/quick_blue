import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'test_support/fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'BluetoothCharacteristic notifications enable and disable notify',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final values = <Uint8List>[];
      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final subscription = characteristic.notifications().listen(values.add);
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);

      platform.handleCharacteristicValueChanged(
        'device-a',
        'service-a',
        'characteristic-a',
        Uint8List.fromList(<int>[7, 8, 9]),
      );
      await pumpEventQueue();

      expect(values.single, Uint8List.fromList(<int>[7, 8, 9]));

      await subscription.cancel();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
    },
  );

  test(
    'BluetoothCharacteristic notifications emits notify setup errors',
    () async {
      final error = StateError('notify failed');
      final platform = FakeQuickBluePlatform(setNotifiableError: error);
      addTearDown(platform.dispose);

      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');
      final errors = <Object>[];
      final subscription = characteristic.notifications().listen(
        (_) {},
        onError: errors.add,
      );

      await pumpEventQueue();
      await subscription.cancel();

      expect(errors, <Object>[error]);
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);
    },
  );

  test(
    'BluetoothCharacteristic notifications recover security setup errors',
    () async {
      const securityError = QuickBlueSecurityException(
        reason: QuickBlueSecurityErrorReason.insufficientEncryption,
        nativeDomain: 'test.security',
        nativeCode: 15,
        operation: 'setNotifiable',
        deviceId: 'device-a',
        message: 'Encryption required',
      );
      final platform = FakeQuickBluePlatform(
        setNotifiableError: securityError,
        clearSecurityErrorsOnPair: true,
      );
      addTearDown(platform.dispose);

      final errors = <Object>[];
      final subscription = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a')
          .notifications()
          .listen((_) {}, onError: errors.add);
      await pumpEventQueue();

      expect(errors, isEmpty);
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'bondState device-a',
        'pair device-a',
        'setNotifiable device-a service-a characteristic-a notification',
      ]);

      await subscription.cancel();
    },
  );

  test(
    'BluetoothCharacteristic notifications waits for notify before forwarding',
    () async {
      final enableNotify = Completer<void>();
      final platform = FakeQuickBluePlatform(
        setNotifiableCompletions: <Completer<void>>[enableNotify],
      );
      addTearDown(platform.dispose);

      final values = <Uint8List>[];
      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final subscription = characteristic.notifications().listen(values.add);
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);

      platform.handleCharacteristicValueChanged(
        'device-a',
        'service-a',
        'characteristic-a',
        Uint8List.fromList(<int>[7, 8, 9]),
      );
      await pumpEventQueue();

      expect(values, isEmpty);

      enableNotify.complete();
      await pumpEventQueue();

      expect(values.single, Uint8List.fromList(<int>[7, 8, 9]));

      await subscription.cancel();
    },
  );

  test(
    'BluetoothCharacteristic notifications disables after pending enable',
    () async {
      final enableNotify = Completer<void>();
      final disableNotify = Completer<void>();
      final platform = FakeQuickBluePlatform(
        setNotifiableCompletions: <Completer<void>>[
          enableNotify,
          disableNotify,
        ],
      );
      addTearDown(platform.dispose);

      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final subscription = characteristic.notifications().listen((_) {});
      await pumpEventQueue();

      final cancel = subscription.cancel();
      var cancelCompleted = false;
      final cancelCompletedFuture = cancel.then((_) => cancelCompleted = true);
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);
      expect(cancelCompleted, isFalse);

      enableNotify.complete();
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
      expect(cancelCompleted, isFalse);

      disableNotify.complete();
      await cancelCompletedFuture;

      expect(cancelCompleted, isTrue);
    },
  );

  test(
    'BluetoothCharacteristic notifications share native listener ownership',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final firstValues = <Uint8List>[];
      final secondValues = <Uint8List>[];
      final device = platform.device('device-a');
      final firstCharacteristic = device.characteristic(
        'service-a',
        'characteristic-a',
      );
      final secondCharacteristic = device.characteristic(
        'service-a',
        'characteristic-a',
      );

      final firstSubscription = firstCharacteristic.notifications().listen(
        firstValues.add,
      );
      final secondSubscription = secondCharacteristic.notifications().listen(
        secondValues.add,
      );
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);

      await firstSubscription.cancel();
      expect(platform.calls, hasLength(1));

      platform.handleCharacteristicValueChanged(
        'device-a',
        'service-a',
        'characteristic-a',
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      await pumpEventQueue();

      expect(firstValues, isEmpty);
      expect(secondValues.single, Uint8List.fromList(<int>[1, 2, 3]));

      await secondSubscription.cancel();
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
    },
  );

  test(
    'BluetoothCharacteristic notifications can retry failed setup',
    () async {
      final error = StateError('notify failed');
      final platform = FakeQuickBluePlatform(setNotifiableError: error);
      addTearDown(platform.dispose);
      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final errors = <Object>[];
      final failedSubscription = characteristic.notifications().listen(
        (_) {},
        onError: errors.add,
      );
      await pumpEventQueue();
      await failedSubscription.cancel();
      expect(errors, <Object>[error]);

      platform.setNotifiableError = null;
      final retrySubscription = characteristic.notifications().listen((_) {});
      await pumpEventQueue();
      await retrySubscription.cancel();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
    },
  );

  test(
    'BluetoothCharacteristic rejects conflicting notification properties',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final notificationSubscription = characteristic.notifications().listen(
        (_) {},
      );
      await pumpEventQueue();

      final errors = <Object>[];
      final indicationSubscription = characteristic
          .notifications(bleInputProperty: BleInputProperty.indication)
          .listen((_) {}, onError: errors.add);
      await pumpEventQueue();
      await indicationSubscription.cancel();

      expect(
        errors.single,
        isA<QuickBlueException>()
            .having(
              (error) => error.code,
              'code',
              QuickBlueErrorCode.invalidState,
            )
            .having((error) => error.operation, 'operation', 'notifications'),
      );
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);

      await notificationSubscription.cancel();
      expect(platform.calls.last, contains('disabled'));
    },
  );

  test(
    'BluetoothCharacteristic can re-enable after failed final disable',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final subscription = characteristic.notifications().listen((_) {});
      await pumpEventQueue();

      final disableError = StateError('disable failed');
      platform.setNotifiableError = disableError;
      await expectLater(subscription.cancel(), throwsA(same(disableError)));

      platform.setNotifiableError = null;
      final retrySubscription = characteristic.notifications().listen((_) {});
      await pumpEventQueue();
      await retrySubscription.cancel();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
    },
  );
}
