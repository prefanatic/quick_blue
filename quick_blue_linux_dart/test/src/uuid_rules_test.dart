import 'package:bluez/bluez.dart';
import 'package:test/test.dart';
import 'package:quick_blue_linux_dart/src/uuid_rules.dart';

void main() {
  const canonical = '0000180d00001000800000805f9b34fb';
  const dashed = '0000180d-0000-1000-8000-00805f9b34fb';

  test('16-bit, 32-bit, full and dashed UUIDs share canonical form', () {
    for (final uuid in ['180D', '0000180D', canonical, dashed.toUpperCase()]) {
      expect(canonicalizeUuid(uuid), canonical);
    }
    expect(canonicalToDashed(canonical), dashed);
    expect(bluezUuidToCanonical(BlueZUUID.short(0x180d)), canonical);
    expect(formatUuid(BlueZUUID.short(0x180d)), dashed);
  });

  test('unsupported UUID lengths retain ArgumentError behavior', () {
    for (final uuid in ['', '180', '123456789']) {
      expect(() => canonicalizeUuid(uuid), throwsArgumentError);
    }
    expect(canonicalToDashed('180d'), '180d');
  });
}
