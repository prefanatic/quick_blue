import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/src/bluetooth_uuid.dart';

void main() {
  test('canonicalBluetoothUuid expands short and dashed UUIDs', () {
    expect(canonicalBluetoothUuid('2A37'), '00002a3700001000800000805f9b34fb');
    expect(
      canonicalBluetoothUuid('12345678'),
      '1234567800001000800000805f9b34fb',
    );
    expect(
      canonicalBluetoothUuid('cba20003-224d-11e6-9fb8-0002a5d5c51b'),
      'cba20003224d11e69fb80002a5d5c51b',
    );
    expect(
      canonicalBluetoothUuid(' {00002A37-0000-1000-8000-00805F9B34FB} '),
      '00002a3700001000800000805f9b34fb',
    );
  });

  test('bluetoothUuidKey returns stable canonical keys', () {
    final first = bluetoothUuidKey('2a37');
    final second = bluetoothUuidKey('00002A37-0000-1000-8000-00805F9B34FB');

    expect(first, '00002a3700001000800000805f9b34fb');
    expect(second, first);
    expect(identical(bluetoothUuidKey('2a37'), first), isTrue);
  });

  test('bluetoothUuidKey preserves invalid UUIDs', () {
    expect(bluetoothUuidKey('characteristic-a'), 'characteristic-a');
    expect(matchesBluetoothUuid('2a37', 'characteristic-a'), isFalse);
  });
}
