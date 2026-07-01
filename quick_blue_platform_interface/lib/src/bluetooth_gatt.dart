import 'package:meta/meta.dart';

import '../models.dart';
import 'bluetooth_characteristic.dart';
import 'bluetooth_device.dart';
import 'bluetooth_uuid.dart';
import 'quick_blue_exception.dart';

/// A discovered GATT view for one Bluetooth LE device.
///
/// This is a snapshot of the services returned by [BluetoothDevice.discoverGatt].
class BluetoothGatt {
  @internal
  BluetoothGatt.internal({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  }) : _device = device,
       services = List<BluetoothService>.unmodifiable(services);

  final BluetoothDevice _device;

  /// The discovered services.
  ///
  /// The list is immutable.
  final List<BluetoothService> services;

  /// The platform-specific device identifier.
  String get deviceId => _device.deviceId;

  /// Resolves a characteristic and returns a handle for it.
  ///
  /// Pass [service] when the characteristic UUID appears under multiple
  /// services. Throws [QuickBlueException] when the characteristic is missing
  /// or ambiguous.
  BluetoothCharacteristic characteristic(
    String characteristic, {
    String? service,
  }) {
    final resolved = _resolveCharacteristic(characteristic, service: service);
    return _device.characteristic(
      resolved.service.uuid,
      resolved.characteristic.uuid,
    );
  }

  /// Resolves metadata for a discovered characteristic.
  ///
  /// Pass [service] when the characteristic UUID appears under multiple
  /// services. Throws [QuickBlueException] when the characteristic is missing
  /// or ambiguous.
  BluetoothCharacteristicInfo characteristicInfo(
    String characteristic, {
    String? service,
  }) {
    return _resolveCharacteristic(
      characteristic,
      service: service,
    ).characteristic;
  }

  /// Returns whether [characteristic] exists in the discovered GATT view.
  ///
  /// Pass [service] to restrict the lookup to a single service. An ambiguous
  /// characteristic still returns `true` because the characteristic exists, but
  /// [characteristic] or [characteristicInfo] will require a service UUID to
  /// resolve it uniquely.
  bool hasCharacteristic(String characteristic, {String? service}) {
    try {
      _resolveCharacteristic(characteristic, service: service);
      return true;
    } on QuickBlueException catch (error) {
      if (error.code == QuickBlueErrorCode.notFound) {
        return false;
      }
      if (error.code == QuickBlueErrorCode.ambiguous) {
        return true;
      }
      rethrow;
    }
  }

  _BluetoothGattCharacteristic _resolveCharacteristic(
    String characteristic, {
    String? service,
  }) {
    final matches = <_BluetoothGattCharacteristic>[];
    for (final discoveredService in services) {
      if (service != null &&
          !matchesBluetoothUuid(discoveredService.uuid, service)) {
        continue;
      }
      for (final discoveredCharacteristic
          in discoveredService.characteristicDetails) {
        if (matchesBluetoothUuid(
          discoveredCharacteristic.uuid,
          characteristic,
        )) {
          matches.add(
            _BluetoothGattCharacteristic(
              service: discoveredService,
              characteristic: discoveredCharacteristic,
            ),
          );
        }
      }
    }

    if (matches.isEmpty) {
      final serviceContext = service == null ? '' : ' under service $service';
      throw QuickBlueException(
        code: QuickBlueErrorCode.notFound,
        operation: 'resolveCharacteristic',
        deviceId: deviceId,
        serviceId: service,
        characteristicId: characteristic,
        message:
            'Characteristic $characteristic not found$serviceContext on '
            'Bluetooth device $deviceId.',
      );
    }
    if (matches.length > 1) {
      final services = matches
          .map((match) => match.service.uuid)
          .toSet()
          .join(', ');
      throw QuickBlueException(
        code: QuickBlueErrorCode.ambiguous,
        operation: 'resolveCharacteristic',
        deviceId: deviceId,
        characteristicId: characteristic,
        details: services,
        message:
            'Characteristic $characteristic was found under multiple services '
            'on Bluetooth device $deviceId: $services. Specify a service UUID.',
      );
    }

    return matches.single;
  }
}

class _BluetoothGattCharacteristic {
  _BluetoothGattCharacteristic({
    required this.service,
    required this.characteristic,
  });

  final BluetoothService service;
  final BluetoothCharacteristicInfo characteristic;
}
