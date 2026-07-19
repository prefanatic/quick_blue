import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../models.dart';
import 'bluetooth_uuid.dart';
import 'quick_blue_exception.dart';

@internal
class CharacteristicLifecycleCoordinator {
  CharacteristicLifecycleCoordinator({
    required this.setNotifiable,
    required this.setNotifiableWithSecurityRecovery,
  });

  final Future<void> Function(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  )
  setNotifiable;
  final Future<void> Function(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  )
  setNotifiableWithSecurityRecovery;

  final _valueController =
      StreamController<BluetoothCharacteristicValue>.broadcast();
  final _valueStreams =
      <_CharacteristicValueKey, StreamController<Uint8List>>{};
  final _activeNotifications = <_CharacteristicValueKey, _ActiveNotification>{};
  final _notificationLifecycles = <_CharacteristicValueKey, Future<void>>{};

  Stream<BluetoothCharacteristicValue> get valueStream =>
      _valueController.stream;

  Stream<Uint8List> valueStreamFor(
    String deviceId,
    String service,
    String characteristic,
  ) {
    final key = _CharacteristicValueKey.fromParts(
      deviceId,
      service,
      characteristic,
    );
    final existing = _valueStreams[key];
    if (existing != null) {
      return existing.stream;
    }

    late StreamController<Uint8List> controller;
    controller = StreamController<Uint8List>.broadcast(
      onCancel: () {
        if (!controller.hasListener) {
          _valueStreams.remove(key);
        }
      },
    );
    _valueStreams[key] = controller;
    return controller.stream;
  }

  Stream<Uint8List> notifications(
    String deviceId,
    String service,
    String characteristic, {
    BleInputProperty bleInputProperty = BleInputProperty.notification,
  }) {
    late StreamSubscription<Uint8List> valueSubscription;
    late Future<void> setUpNotification;
    var valueSubscriptionCanceled = false;
    var acquired = false;
    final controller = StreamController<Uint8List>();

    Future<void> cancelValueSubscription() async {
      if (valueSubscriptionCanceled) {
        return;
      }
      valueSubscriptionCanceled = true;
      await valueSubscription.cancel();
    }

    controller.onListen = () {
      valueSubscription = valueStreamFor(deviceId, service, characteristic)
          .listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
      valueSubscription.pause();
      setUpNotification = () async {
        try {
          await _acquire(deviceId, service, characteristic, bleInputProperty);
          acquired = true;
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
      if (acquired) {
        await _release(deviceId, service, characteristic);
      }
    };

    return controller.stream;
  }

  Future<void> _acquire(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    final key = _CharacteristicValueKey.fromParts(
      deviceId,
      service,
      characteristic,
    );
    return _queue(key, () async {
      final active = _activeNotifications[key];
      if (active != null) {
        if (active.bleInputProperty != bleInputProperty) {
          throw QuickBlueException(
            code: QuickBlueErrorCode.invalidState,
            operation: 'notifications',
            deviceId: deviceId,
            serviceId: service,
            characteristicId: characteristic,
            message:
                'Cannot listen with ${bleInputProperty.value} while '
                '${active.bleInputProperty.value} is already active.',
          );
        }
        active.listenerCount++;
        return;
      }

      await setNotifiableWithSecurityRecovery(
        deviceId,
        service,
        characteristic,
        bleInputProperty,
      );
      _activeNotifications[key] = _ActiveNotification(bleInputProperty);
    });
  }

  Future<void> _release(
    String deviceId,
    String service,
    String characteristic,
  ) {
    final key = _CharacteristicValueKey.fromParts(
      deviceId,
      service,
      characteristic,
    );
    return _queue(key, () async {
      final active = _activeNotifications[key];
      if (active == null) {
        return;
      }
      active.listenerCount--;
      if (active.listenerCount != 0) {
        return;
      }

      _activeNotifications.remove(key);
      await setNotifiable(
        deviceId,
        service,
        characteristic,
        BleInputProperty.disabled,
      );
    });
  }

  Future<void> _queue(
    _CharacteristicValueKey key,
    Future<void> Function() action,
  ) {
    final previous = _notificationLifecycles[key] ?? Future<void>.value();
    final next = previous.then((_) => action());
    final recovered = next.catchError((Object _) {});
    _notificationLifecycles[key] = recovered;
    recovered.then((_) {
      if (identical(_notificationLifecycles[key], recovered)) {
        _notificationLifecycles.remove(key);
      }
    });
    return next;
  }

  void handleValueChanged(
    String deviceId,
    String serviceId,
    String characteristicId,
    Uint8List value,
  ) {
    _valueStreams[_CharacteristicValueKey.fromParts(
          deviceId,
          serviceId,
          characteristicId,
        )]
        ?.add(value);
    if (serviceId.isEmpty) {
      _dispatchLegacyValue(deviceId, characteristicId, value);
    }

    if (_valueController.hasListener) {
      _valueController.add(
        BluetoothCharacteristicValue(
          deviceId: deviceId,
          serviceId: serviceId,
          characteristicId: characteristicId,
          value: value,
        ),
      );
    }
  }

  void _dispatchLegacyValue(
    String deviceId,
    String characteristicId,
    Uint8List value,
  ) {
    final characteristic = bluetoothUuidKey(characteristicId);
    for (final entry in _valueStreams.entries) {
      final key = entry.key;
      if (key.service.isNotEmpty &&
          key.deviceId == deviceId &&
          key.characteristic == characteristic) {
        entry.value.add(value);
      }
    }
  }
}

class _CharacteristicValueKey {
  const _CharacteristicValueKey({
    required this.deviceId,
    required this.service,
    required this.characteristic,
  });

  factory _CharacteristicValueKey.fromParts(
    String deviceId,
    String service,
    String characteristic,
  ) {
    return _CharacteristicValueKey(
      deviceId: deviceId,
      service: bluetoothUuidKey(service),
      characteristic: bluetoothUuidKey(characteristic),
    );
  }

  final String deviceId;
  final String service;
  final String characteristic;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _CharacteristicValueKey &&
            other.deviceId == deviceId &&
            other.service == service &&
            other.characteristic == characteristic;
  }

  @override
  int get hashCode => Object.hash(deviceId, service, characteristic);
}

class _ActiveNotification {
  _ActiveNotification(this.bleInputProperty);

  final BleInputProperty bleInputProperty;
  var listenerCount = 1;
}
