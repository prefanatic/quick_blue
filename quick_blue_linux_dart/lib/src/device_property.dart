import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

Future<void> waitForDeviceProperty(
  BlueZDevice device, {
  required String propertyName,
  required bool Function() isReady,
  required Duration timeout,
  Future<void>? cancelled,
}) async {
  if (isReady()) {
    return;
  }

  final completer = Completer<void>();
  late final StreamSubscription<List<String>> subscription;
  subscription = device.propertiesChanged.listen(
    (properties) {
      if (properties.contains(propertyName) &&
          isReady() &&
          !completer.isCompleted) {
        completer.complete();
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
  );

  try {
    await Future.any<void>([
      completer.future,
      if (cancelled != null)
        cancelled.then<void>(
          (_) => throw QuickBlueException(
            code: QuickBlueErrorCode.cancelled,
            deviceId: device.address,
            operation: 'waitFor$propertyName',
            message: 'Device state was cleared.',
          ),
        ),
    ]).timeout(timeout);
  } finally {
    await subscription.cancel();
  }
}
