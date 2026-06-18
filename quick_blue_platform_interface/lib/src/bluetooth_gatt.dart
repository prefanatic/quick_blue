import 'package:meta/meta.dart';

import '../models.dart';
import 'bluetooth_characteristic.dart';
import 'bluetooth_device.dart';
import 'bluetooth_uuid.dart';

class BluetoothGatt {
  @internal
  BluetoothGatt.internal({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  }) : _device = device,
       services = List<BluetoothService>.unmodifiable(services);

  final BluetoothDevice _device;
  final List<BluetoothService> services;

  String get deviceId => _device.deviceId;

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

  BluetoothCharacteristicInfo characteristicInfo(
    String characteristic, {
    String? service,
  }) {
    return _resolveCharacteristic(
      characteristic,
      service: service,
    ).characteristic;
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
      throw StateError(
        'Characteristic $characteristic not found$serviceContext on '
        'Bluetooth device $deviceId.',
      );
    }
    if (matches.length > 1) {
      final services = matches
          .map((match) => match.service.uuid)
          .toSet()
          .join(', ');
      throw StateError(
        'Characteristic $characteristic was found under multiple services on '
        'Bluetooth device $deviceId: $services. Specify a service UUID.',
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
