import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/models.dart';

void main() {
  group('BlueScanResult manufacturer data', () {
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
  });

  group('ScanFilter', () {
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
  });
}
