import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:meta/meta.dart';

import '../models.dart';
import 'bluetooth_uuid.dart';
import 'quick_blue_platform.dart';

class BluetoothCharacteristic {
  @internal
  BluetoothCharacteristic.internal({
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
    required QuickBluePlatform platform,
  }) : _platform = platform;

  final String deviceId;
  final String serviceId;
  final String characteristicId;
  final QuickBluePlatform _platform;

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

  Future<Uint8List> read() async {
    final values = StreamQueue(valueStream);

    try {
      await _platform.readValue(deviceId, serviceId, characteristicId);
      return await values.next;
    } finally {
      await values.cancel();
    }
  }

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
