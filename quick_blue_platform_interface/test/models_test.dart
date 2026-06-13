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

    test('manufacturerData falls back to the head when full payload is empty',
        () {
      final result = BlueScanResult(
        name: 'dev',
        deviceId: 'id',
        manufacturerDataHead: head,
        manufacturerData: Uint8List(0),
        rssi: -50,
      );

      expect(result.manufacturerData, head);
    });

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
}
