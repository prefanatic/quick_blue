import 'package:test/test.dart';
import 'package:quick_blue_core/quick_blue_core.dart';

// Compile the additive API through the app-facing package, not the interface.
BluetoothCharacteristic resolveBound(BluetoothGatt gatt) =>
    gatt.boundCharacteristic('characteristic-a', service: 'service-a');

void main() {
  test('snapshot-bound resolver is available from the public entrypoint', () {
    expect(
      resolveBound,
      isA<BluetoothCharacteristic Function(BluetoothGatt)>(),
    );
  });
}
