import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  group(QuickBlueException, () {
    test('exposes structured context and a readable string', () {
      const error = QuickBlueException(
        code: QuickBlueErrorCode.notFound,
        operation: 'resolveCharacteristic',
        deviceId: 'device-a',
        serviceId: 'service-a',
        characteristicId: 'characteristic-a',
        details: 'extra',
        message: 'Characteristic not found.',
      );

      expect(error.code, QuickBlueErrorCode.notFound);
      expect(error.operation, 'resolveCharacteristic');
      expect(error.deviceId, 'device-a');
      expect(error.serviceId, 'service-a');
      expect(error.characteristicId, 'characteristic-a');
      expect(error.details, 'extra');
      expect(error.toString(), contains('notFound'));
      expect(error.toString(), contains('Characteristic not found.'));
    });
  });

  group(BlueConnectionState, () {
    test('parses known states and rejects invalid states', () {
      expect(
        BlueConnectionState.parse('connected'),
        BlueConnectionState.connected,
      );
      expect(
        BlueConnectionState.parse('disconnected'),
        BlueConnectionState.disconnected,
      );
      expect(
        () => BlueConnectionState.parse('linkLost'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

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

    test('compares RSSI thresholds by value', () {
      expect(ScanFilter(rssi: -80), ScanFilter(rssi: -80));
      expect(ScanFilter(rssi: -80), isNot(ScanFilter(rssi: -70)));
    });

    test('treats null and empty manufacturer data consistently', () {
      final nullData = ScanFilter();
      final emptyData = ScanFilter(manufacturerData: <int, Uint8List>{});

      expect(emptyData.manufacturerData, isNull);
      expect(nullData, emptyData);
      expect(nullData.hashCode, emptyData.hashCode);
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
      expect(service.characteristicDetails, <BluetoothCharacteristicInfo>[
        BluetoothCharacteristicInfo(uuid: 'characteristic-a'),
      ]);
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
    });
  });

  group(BluetoothCharacteristicInfo, () {
    test('compares by properties', () {
      final characteristic = BluetoothCharacteristicInfo(
        uuid: 'characteristic-a',
        canRead: true,
        canWriteWithResponse: true,
        canNotify: true,
      );

      expect(characteristic.canWrite, isTrue);
      expect(characteristic.canSubscribe, isTrue);
      expect(
        characteristic,
        BluetoothCharacteristicInfo(
          uuid: 'characteristic-a',
          canRead: true,
          canWriteWithResponse: true,
          canNotify: true,
        ),
      );
      expect(
        characteristic.hashCode,
        BluetoothCharacteristicInfo(
          uuid: 'characteristic-a',
          canRead: true,
          canWriteWithResponse: true,
          canNotify: true,
        ).hashCode,
      );
    });
  });

  group(BluetoothCharacteristicValue, () {
    test('defensively copies bytes', () {
      final value = Uint8List.fromList(<int>[1, 2, 3]);
      final characteristicValue = BluetoothCharacteristicValue(
        deviceId: 'device-a',
        serviceId: 'service-a',
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
          serviceId: 'service-a',
          characteristicId: 'characteristic-a',
          value: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );
      expect(
        characteristicValue.hashCode,
        BluetoothCharacteristicValue(
          deviceId: 'device-a',
          serviceId: 'service-a',
          characteristicId: 'characteristic-a',
          value: Uint8List.fromList(<int>[1, 2, 3]),
        ).hashCode,
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
        dataEvent.hashCode,
        BleL2CapSocketEventData(
          deviceId: 'device-a',
          data: Uint8List.fromList(<int>[1, 2, 3]),
        ).hashCode,
      );
      expect(
        BleL2CapSocketEventOpened(deviceId: 'device-a'),
        BleL2CapSocketEventOpened(deviceId: 'device-a'),
      );
      expect(
        BleL2CapSocketEventOpened(deviceId: 'device-a').hashCode,
        BleL2CapSocketEventOpened(deviceId: 'device-a').hashCode,
      );
      expect(
        BleL2CapSocketEventClosed(deviceId: 'device-a'),
        BleL2CapSocketEventClosed(deviceId: 'device-a'),
      );
      expect(
        BleL2CapSocketEventClosed(deviceId: 'device-a').hashCode,
        BleL2CapSocketEventClosed(deviceId: 'device-a').hashCode,
      );
      expect(
        BleL2CapSocketEventError(deviceId: 'device-a', error: 'failed'),
        BleL2CapSocketEventError(deviceId: 'device-a', error: 'failed'),
      );
      expect(
        BleL2CapSocketEventError(
          deviceId: 'device-a',
          error: 'failed',
        ).hashCode,
        BleL2CapSocketEventError(
          deviceId: 'device-a',
          error: 'failed',
        ).hashCode,
      );
      expect(
        BleL2CapSocketEventError(deviceId: 'device-a').hashCode,
        BleL2CapSocketEventError(deviceId: 'device-a').hashCode,
      );
    });
  });

  group(BleCompanionFilter, () {
    test('defensively copies manufacturer data', () {
      final manufacturerPayload = Uint8List.fromList(<int>[1, 2, 3]);
      final filter = BleCompanionFilter(
        deviceId: 'device-a',
        namePattern: 'Device.*',
        serviceUuids: const <String>['180d'],
        manufacturerData: <int, Uint8List>{76: manufacturerPayload},
      );

      manufacturerPayload[0] = 9;
      final firstRead = filter.manufacturerData![76]!;
      firstRead[1] = 8;

      expect(filter.manufacturerData![76], Uint8List.fromList(<int>[1, 2, 3]));
    });
  });

  group(ScanOptions, () {
    test('compares nested platform options by value', () {
      const first = ScanOptions(
        allowDuplicates: false,
        scanMode: ScanMode.balanced,
        android: AndroidScanOptions(
          scanMode: AndroidScanMode.balanced,
          callbackType: AndroidScanCallbackType.firstMatch,
          matchMode: AndroidScanMatchMode.aggressive,
          numOfMatches: AndroidScanNumOfMatches.few,
          reportDelay: Duration(seconds: 1),
          legacy: true,
          phy: AndroidScanPhy.leCoded,
        ),
        linux: LinuxScanOptions(
          rssi: -80,
          pathloss: 10,
          transport: LinuxScanTransport.auto,
          duplicateData: true,
          discoverable: true,
          pattern: 'AA:BB',
        ),
        windows: WindowsScanOptions(
          scanningMode: WindowsScanMode.active,
          signalStrengthFilter: WindowsSignalStrengthFilter(
            inRangeThresholdInDBm: -65,
            outOfRangeThresholdInDBm: -75,
            outOfRangeTimeout: Duration(seconds: 3),
            samplingInterval: Duration(milliseconds: 500),
          ),
        ),
      );
      const equivalent = ScanOptions(
        allowDuplicates: false,
        scanMode: ScanMode.balanced,
        android: AndroidScanOptions(
          scanMode: AndroidScanMode.balanced,
          callbackType: AndroidScanCallbackType.firstMatch,
          matchMode: AndroidScanMatchMode.aggressive,
          numOfMatches: AndroidScanNumOfMatches.few,
          reportDelay: Duration(seconds: 1),
          legacy: true,
          phy: AndroidScanPhy.leCoded,
        ),
        linux: LinuxScanOptions(
          rssi: -80,
          pathloss: 10,
          transport: LinuxScanTransport.auto,
          duplicateData: true,
          discoverable: true,
          pattern: 'AA:BB',
        ),
        windows: WindowsScanOptions(
          scanningMode: WindowsScanMode.active,
          signalStrengthFilter: WindowsSignalStrengthFilter(
            inRangeThresholdInDBm: -65,
            outOfRangeThresholdInDBm: -75,
            outOfRangeTimeout: Duration(seconds: 3),
            samplingInterval: Duration(milliseconds: 500),
          ),
        ),
      );
      const different = ScanOptions(scanMode: ScanMode.lowPower);

      expect(first, equivalent);
      expect(first.hashCode, equivalent.hashCode);
      expect(first, isNot(different));
    });

    test('defensively copies Darwin solicited service UUIDs', () {
      final solicitedServiceUuids = <String>['180d'];
      final options = DarwinScanOptions(
        solicitedServiceUuids: solicitedServiceUuids,
      );

      solicitedServiceUuids.add('180f');

      expect(options.solicitedServiceUuids, <String>['180d']);
      expect(
        () => options.solicitedServiceUuids.add('180f'),
        throwsUnsupportedError,
      );
    });
  });

  group(CompanionAssociationRequest, () {
    test('compares by value', () {
      final first = CompanionAssociationRequest.ble(
        filters: <BleCompanionFilter>[
          BleCompanionFilter(
            deviceId: 'device-a',
            serviceUuids: const <String>['180d'],
          ),
        ],
      );
      final equivalent = CompanionAssociationRequest.ble(
        filters: <BleCompanionFilter>[
          BleCompanionFilter(
            deviceId: 'device-a',
            serviceUuids: const <String>['180d'],
          ),
        ],
      );
      final different = CompanionAssociationRequest.ble(
        filters: <BleCompanionFilter>[BleCompanionFilter(deviceId: 'device-b')],
      );

      expect(first, equivalent);
      expect(first.hashCode, equivalent.hashCode);
      expect(first, isNot(different));
    });
  });

  group(CompanionAssociation, () {
    test('compares by value', () {
      final first = CompanionAssociation(
        id: 42,
        deviceId: 'device-a',
        displayName: 'Device A',
        deviceProfile: 'watch',
      );
      final equivalent = CompanionAssociation(
        id: 42,
        deviceId: 'device-a',
        displayName: 'Device A',
        deviceProfile: 'watch',
      );
      final different = CompanionAssociation(id: 43);

      expect(first, equivalent);
      expect(first.hashCode, equivalent.hashCode);
      expect(first, isNot(different));
    });

    test('creates from map payload', () {
      final fromMap = CompanionAssociation.fromMap(<String, dynamic>{
        'id': 42,
        'deviceId': 'device-a',
        'displayName': 'Device A',
        'deviceProfile': 'watch',
      });

      expect(fromMap, const TypeMatcher<CompanionAssociation>());
      expect(fromMap.id, 42);
      expect(fromMap.deviceId, 'device-a');
      expect(fromMap.displayName, 'Device A');
      expect(fromMap.deviceProfile, 'watch');
      expect(
        fromMap.hashCode,
        CompanionAssociation(
          id: 42,
          deviceId: 'device-a',
          displayName: 'Device A',
          deviceProfile: 'watch',
        ).hashCode,
      );
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

      final fromMap = CompanionDevice.fromMap(<String, dynamic>{
        'id': 'device-a',
        'name': 'Device A',
        'associationId': 42,
      });

      expect(
        fromMap,
        CompanionDevice(id: 'device-a', name: 'Device A', associationId: 42),
      );
    });
  });

  group(BleInputProperty, () {
    test('has a string representation', () {
      expect(BleInputProperty.notification.toString(), 'notification');
      expect(BleInputProperty.indication.toString(), 'indication');
      expect(BleInputProperty.disabled.toString(), 'disabled');
    });
  });

  group(BleOutputProperty, () {
    test('has a string representation', () {
      expect(BleOutputProperty.withResponse.toString(), 'withResponse');
      expect(BleOutputProperty.withoutResponse.toString(), 'withoutResponse');
    });
  });
}
