import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:meta/meta.dart';

import '../models.dart';
import 'bluetooth_uuid.dart';
import 'quick_blue_platform.dart';

/// A handle for a Bluetooth LE characteristic.
///
/// The handle is service-scoped so duplicate characteristic UUIDs under
/// different services can be addressed safely.
class BluetoothCharacteristic {
  @internal
  BluetoothCharacteristic.internal({
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
    required QuickBluePlatform platform,
  }) : _platform = platform;

  /// The platform-specific device identifier.
  final String deviceId;

  /// The service UUID containing this characteristic.
  final String serviceId;

  /// The characteristic UUID.
  final String characteristicId;
  final QuickBluePlatform _platform;

  /// Value updates for this characteristic.
  ///
  /// Legacy platform events without a service id are still matched by
  /// characteristic UUID for compatibility.
  Stream<Uint8List> get valueStream {
    return _platform.characteristicValueStream
        .where(
          (event) =>
              event.deviceId == deviceId &&
              (event.serviceId.isEmpty ||
                  matchesBluetoothUuid(event.serviceId, serviceId)) &&
              matchesBluetoothUuid(event.characteristicId, characteristicId),
        )
        .map((event) => event.value);
  }

  /// Enables notifications or indications while the returned stream is active.
  ///
  /// Values are not forwarded until notification setup succeeds. Canceling the
  /// stream disables updates again.
  Stream<Uint8List> notifications({
    BleInputProperty bleInputProperty = BleInputProperty.notification,
  }) {
    late StreamSubscription<Uint8List> valueSubscription;
    late Future<void> setUpNotification;
    var valueSubscriptionCanceled = false;
    var enabled = false;
    final controller = StreamController<Uint8List>();

    Future<void> cancelValueSubscription() async {
      if (valueSubscriptionCanceled) {
        return;
      }
      valueSubscriptionCanceled = true;
      await valueSubscription.cancel();
    }

    controller.onListen = () {
      valueSubscription = valueStream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      valueSubscription.pause();
      setUpNotification = () async {
        try {
          await _platform.setNotifiable(
            deviceId,
            serviceId,
            characteristicId,
            bleInputProperty,
          );
          enabled = true;
          valueSubscription.resume();
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await cancelValueSubscription();
        }
      }();
    };

    controller.onCancel = () async {
      await setUpNotification;
      await cancelValueSubscription();
      if (enabled) {
        await _platform.setNotifiable(
          deviceId,
          serviceId,
          characteristicId,
          BleInputProperty.disabled,
        );
      }
    };

    return controller.stream;
  }

  /// Reads the current characteristic value.
  ///
  /// The future completes with the next matching value event after the platform
  /// read request is sent.
  Future<Uint8List> read() async {
    final values = StreamQueue(valueStream);

    try {
      await _platform.readValue(deviceId, serviceId, characteristicId);
      return await values.next;
    } finally {
      await values.cancel();
    }
  }

  /// Writes [value] to the characteristic.
  ///
  /// Completion timing follows the platform implementation and selected
  /// [bleOutputProperty].
  Future<void> write(Uint8List value, BleOutputProperty bleOutputProperty) {
    return _platform.writeValue(
      deviceId,
      serviceId,
      characteristicId,
      value,
      bleOutputProperty,
    );
  }
}
