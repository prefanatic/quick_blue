import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/models.dart';

void main() {
  group(BlueScanResult, () {
    final head = Uint8List.fromList(<int>[0x4c, 0x00, 0x01]);
    final full = Uint8List.fromList(<int>[0x4c, 0x00, 0x01, 0x02, 0x03]);

    test('manufacturerData falls back to the head when no full payload', () {
      final result = BlueScanResult(
        name: 'dev',
        deviceId: 'id',
        manufacturerDataHead: head,
        rssi: -50,
      );

      expect(result.manufacturerDataHead, head);
      expect(result.manufacturerData, head);
    });

    test(
      'manufacturerData falls back to the head when full payload is empty',
      () {
        final result = BlueScanResult(
          name: 'dev',
          deviceId: 'id',
          manufacturerDataHead: head,
          manufacturerData: Uint8List(0),
          rssi: -50,
        );

        expect(result.manufacturerData, head);
      },
    );

    test('manufacturerData prefers the full payload when present', () {
      final result = BlueScanResult(
        name: 'dev',
        deviceId: 'id',
        manufacturerDataHead: head,
        manufacturerData: full,
        rssi: -50,
      );

      expect(result.manufacturerData, full);
    });
    test('defensively copies scan payload collections and bytes', () {
      final manufacturerDataHead = Uint8List.fromList(<int>[1, 2]);
      final manufacturerData = Uint8List.fromList(<int>[3, 4]);
      final serviceDataBytes = Uint8List.fromList(<int>[5, 6]);
      final serviceUuids = <String>['180d'];
      final serviceData = <String, Uint8List>{'180d': serviceDataBytes};
      final result = BlueScanResult(
        name: 'dev',
        deviceId: 'id',
        manufacturerDataHead: manufacturerDataHead,
        manufacturerData: manufacturerData,
        rssi: -50,
        serviceUuids: serviceUuids,
        serviceData: serviceData,
      );

      manufacturerDataHead[0] = 9;
      manufacturerData[0] = 9;
      serviceUuids.add('180f');
      serviceDataBytes[0] = 9;
      serviceData['180f'] = Uint8List.fromList(<int>[7, 8]);

      expect(result.manufacturerDataHead, orderedEquals(<int>[1, 2]));
      expect(result.manufacturerData, orderedEquals(<int>[3, 4]));
      expect(result.serviceUuids, <String>['180d']);
      expect(result.serviceData.keys, <String>['180d']);
      expect(result.serviceData['180d'], orderedEquals(<int>[5, 6]));
      expect(() => result.serviceUuids.add('180f'), throwsUnsupportedError);
      expect(
        () => result.serviceData['180f'] = Uint8List(0),
        throwsUnsupportedError,
      );

      final exposedManufacturerData = result.manufacturerData;
      final exposedServiceData = result.serviceData['180d']!;
      exposedManufacturerData[0] = 9;
      exposedServiceData[0] = 9;

      expect(result.manufacturerData, orderedEquals(<int>[3, 4]));
      expect(result.serviceData['180d'], orderedEquals(<int>[5, 6]));
    });

    test('compares by value', () {
      final advertisedDateTime = DateTime(2026, 6, 13);
      final first = BlueScanResult(
        name: 'dev',
        deviceId: 'id',
        manufacturerDataHead: Uint8List.fromList(<int>[1, 2]),
        manufacturerData: Uint8List.fromList(<int>[3, 4]),
        rssi: -50,
        advertisedDateTime: advertisedDateTime,
        serviceUuids: const <String>['180d'],
        serviceData: <String, Uint8List>{
          '180d': Uint8List.fromList(<int>[5, 6]),
        },
      );
      final equivalent = BlueScanResult(
        name: 'dev',
        deviceId: 'id',
        manufacturerDataHead: Uint8List.fromList(<int>[1, 2]),
        manufacturerData: Uint8List.fromList(<int>[3, 4]),
        rssi: -50,
        advertisedDateTime: advertisedDateTime,
        serviceUuids: const <String>['180d'],
        serviceData: <String, Uint8List>{
          '180d': Uint8List.fromList(<int>[5, 6]),
        },
      );
      final different = BlueScanResult(
        name: 'dev',
        deviceId: 'id',
        manufacturerDataHead: Uint8List.fromList(<int>[1, 2]),
        manufacturerData: Uint8List.fromList(<int>[3, 4]),
        rssi: -51,
        advertisedDateTime: advertisedDateTime,
        serviceUuids: const <String>['180d'],
        serviceData: <String, Uint8List>{
          '180d': Uint8List.fromList(<int>[5, 6]),
        },
      );

      expect(first, equivalent);
      expect(first.hashCode, equivalent.hashCode);
      expect(first, isNot(different));
      expect(first.toString(), contains('BlueScanResult'));
    });
  });

  group(ScanFilter, () {
    test('defensively copies and exposes unmodifiable service UUIDs', () {
      final serviceUuids = <String>['180d'];
      final filter = ScanFilter(serviceUuids: serviceUuids);

      serviceUuids.add('180f');

      expect(filter.serviceUuids, <String>['180d']);
      expect(() => filter.serviceUuids.add('180f'), throwsUnsupportedError);
    });

    test('defensively copies and exposes unmodifiable manufacturer data', () {
      final manufacturerBytes = Uint8List.fromList(<int>[1, 2, 3]);
      final manufacturerData = <int, Uint8List>{76: manufacturerBytes};
      final filter = ScanFilter(manufacturerData: manufacturerData);

      manufacturerBytes[0] = 9;
      manufacturerData[77] = Uint8List.fromList(<int>[4, 5, 6]);

      expect(filter.manufacturerData!.keys, <int>[76]);
      expect(filter.manufacturerData![76], orderedEquals(<int>[1, 2, 3]));
      expect(
        () => filter.manufacturerData![77] = Uint8List(0),
        throwsUnsupportedError,
      );

      final exposedBytes = filter.manufacturerData![76]!;
      exposedBytes[0] = 9;

      expect(filter.manufacturerData![76], orderedEquals(<int>[1, 2, 3]));
    });

    test('compares service UUIDs by order', () {
      expect(
        ScanFilter(serviceUuids: const <String>['180d', '180f']),
        ScanFilter(serviceUuids: const <String>['180d', '180f']),
      );
      expect(
        ScanFilter(serviceUuids: const <String>['180d', '180f']),
        isNot(ScanFilter(serviceUuids: const <String>['180f', '180d'])),
      );
    });

    test('compares manufacturer data by key and bytes', () {
      final first = ScanFilter(
        manufacturerData: <int, Uint8List>{
          76: Uint8List.fromList(<int>[1, 2, 3]),
          224: Uint8List.fromList(<int>[4]),
        },
      );
      final equivalent = ScanFilter(
        manufacturerData: <int, Uint8List>{
          224: Uint8List.fromList(<int>[4]),
          76: Uint8List.fromList(<int>[1, 2, 3]),
        },
      );
      final differentBytes = ScanFilter(
        manufacturerData: <int, Uint8List>{
          76: Uint8List.fromList(<int>[1, 2, 4]),
          224: Uint8List.fromList(<int>[4]),
        },
      );

      expect(first, equivalent);
      expect(first.hashCode, equivalent.hashCode);
      expect(first, isNot(differentBytes));
    });

    test('treats null and empty manufacturer data consistently', () {
      final nullData = ScanFilter();
      final emptyData = ScanFilter(manufacturerData: <int, Uint8List>{});

      expect(emptyData.manufacturerData, isNull);
      expect(nullData, emptyData);
      expect(nullData.hashCode, emptyData.hashCode);
    });

    test('has a useful string representation', () {
      final filter = ScanFilter(
        serviceUuids: const <String>['180d'],
        manufacturerData: <int, Uint8List>{
          76: Uint8List.fromList(<int>[1, 2, 3]),
        },
      );

      expect(filter.toString(), contains('ScanFilter'));
      expect(filter.toString(), contains('180d'));
    });
  });

  group(BluetoothConnectionStateChange, () {
    test('compares by value', () {
      final first = BluetoothConnectionStateChange(
        deviceId: 'device-a',
        state: BlueConnectionState.connected,
        status: BleStatus.success,
      );
      final equivalent = BluetoothConnectionStateChange(
        deviceId: 'device-a',
        state: BlueConnectionState.connected,
        status: BleStatus.success,
      );
      final different = BluetoothConnectionStateChange(
        deviceId: 'device-b',
        state: BlueConnectionState.connected,
        status: BleStatus.success,
      );

      expect(first, equivalent);
      expect(first.hashCode, equivalent.hashCode);
      expect(first, isNot(different));
      expect(first.toString(), contains('device-a'));
    });
  });

  group(BluetoothService, () {
    test('defensively copies characteristics', () {
      final characteristics = <String>['characteristic-a'];
      final service = BluetoothService(
        deviceId: 'device-a',
        uuid: 'service-a',
        characteristics: characteristics,
      );

      characteristics.add('characteristic-b');

      expect(service.characteristics, <String>['characteristic-a']);
      expect(
        () => service.characteristics.add('characteristic-b'),
        throwsUnsupportedError,
      );
      expect(
        service,
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
      );
      expect(service.toString(), contains('BluetoothService'));
    });
  });

  group(BluetoothCharacteristicValue, () {
    test('defensively copies bytes', () {
      final value = Uint8List.fromList(<int>[1, 2, 3]);
      final characteristicValue = BluetoothCharacteristicValue(
        deviceId: 'device-a',
        characteristicId: 'characteristic-a',
        value: value,
      );

      value[0] = 9;

      expect(characteristicValue.value, orderedEquals(<int>[1, 2, 3]));

      final exposedValue = characteristicValue.value;
      exposedValue[0] = 9;

      expect(characteristicValue.value, orderedEquals(<int>[1, 2, 3]));
      expect(
        characteristicValue,
        BluetoothCharacteristicValue(
          deviceId: 'device-a',
          characteristicId: 'characteristic-a',
          value: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );
      expect(
        characteristicValue.toString(),
        contains('BluetoothCharacteristicValue'),
      );
    });
  });

  group(BleL2CapSocketEvent, () {
    test('compares by value and copies data bytes', () {
      final data = Uint8List.fromList(<int>[1, 2, 3]);
      final dataEvent = BleL2CapSocketEventData(
        deviceId: 'device-a',
        data: data,
      );

      data[0] = 9;

      expect(dataEvent.data, orderedEquals(<int>[1, 2, 3]));

      final exposedData = dataEvent.data;
      exposedData[0] = 9;

      expect(dataEvent.data, orderedEquals(<int>[1, 2, 3]));
      expect(
        dataEvent,
        BleL2CapSocketEventData(
          deviceId: 'device-a',
          data: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );
      expect(
        BleL2CapSocketEventOpened(deviceId: 'device-a'),
        BleL2CapSocketEventOpened(deviceId: 'device-a'),
      );
      expect(
        BleL2CapSocketEventClosed(deviceId: 'device-a'),
        BleL2CapSocketEventClosed(deviceId: 'device-a'),
      );
      expect(
        BleL2CapSocketEventError(deviceId: 'device-a', error: 'failed'),
        BleL2CapSocketEventError(deviceId: 'device-a', error: 'failed'),
      );
      expect(dataEvent.toString(), contains('BleL2CapSocketEventData'));
    });
  });

  group(CompanionDevice, () {
    test('compares by value', () {
      final first = CompanionDevice(
        id: 'device-a',
        name: 'Device A',
        associationId: 42,
      );
      final equivalent = CompanionDevice(
        id: 'device-a',
        name: 'Device A',
        associationId: 42,
      );
      final different = CompanionDevice(
        id: 'device-b',
        name: 'Device B',
        associationId: 43,
      );

      expect(first, equivalent);
      expect(first.hashCode, equivalent.hashCode);
      expect(first, isNot(different));
      expect(first.toString(), contains('CompanionDevice'));
    });
  });
}
