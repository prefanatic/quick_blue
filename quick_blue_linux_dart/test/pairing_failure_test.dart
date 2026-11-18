import 'package:dbus/dbus.dart';
import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';
import 'package:test/test.dart';

import 'adapter_selection_test.dart' as fixtures;

void main() {
  for (final name in [
    'org.bluez.Error.AuthenticationRejected',
    'org.bluez.Error.AuthenticationFailed',
    'org.bluez.Error.AuthenticationCanceled',
    'org.bluez.Error.Failed',
  ]) {
    test(
      'public pair preserves $name without RemoveDevice or unrelated actions',
      () async {
        final adapter = fixtures.Adapter('02:00:00:00:00:01');
        final failure = DBusMethodResponseException(
          DBusMethodErrorResponse(name, [
            const DBusString('Synthetic agent unavailable or rejected'),
          ]),
        );
        final selected = PairDevice(adapter, '02:00:00:00:00:02', failure);
        final unrelated = PairDevice(adapter, '02:00:00:00:00:03', failure);
        final client = fixtures.Client([adapter])
          ..deviceList = [selected, unrelated];
        final platform = QuickBlueLinux.withClient(
          client,
          connectionLease: fixtures.Lease(),
        );
        try {
          await expectLater(
            platform.device(selected.address).pair(),
            throwsA(same(failure)),
          );
          expect(selected.pairs, 1);
          expect(unrelated.pairs, 0);
          expect(selected.connects, 0);
          expect(unrelated.connects, 0);
          // The strict fakes throw on every unsupported call, including
          // Adapter.RemoveDevice, agent registration, trust and auto-acceptance.
          expect(adapter.calls, isEmpty);
        } finally {
          await platform.close();
          await client.removed.close();
        }
        expect(unrelated.disconnects, 0);
      },
    );
  }
}

class PairDevice extends fixtures.Device {
  PairDevice(super.adapter, String super.remoteAddress, this.failure);
  final Object failure;
  int pairs = 0;
  @override
  bool get paired => false;
  @override
  Future<void> pair() async {
    pairs++;
    throw failure;
  }
}
