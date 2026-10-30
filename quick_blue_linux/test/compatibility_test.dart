import 'package:quick_blue_core/quick_blue_core.dart';
import 'package:quick_blue_linux/quick_blue_linux.dart' as legacy;
import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart' as backend;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  test(
    'legacy exports preserve backend type, constructors and singleton',
    () async {
      expect(legacy.QuickBlueLinux, backend.QuickBlueLinux);
      expect(
        legacy.QuickBlueLinux.withClient,
        backend.QuickBlueLinux.withClient,
      );
      expect(legacy.QuickBlueLinuxAdapter, backend.QuickBlueLinuxAdapter);
      expect(legacy.DbusConnectionLease, backend.DbusConnectionLease);
      expect(
        legacy.QuickBlueLinuxConnectionLease,
        backend.QuickBlueLinuxConnectionLease,
      );
      final legacy.QuickBlueLinux explicit = legacy.QuickBlueLinux(
        adapterAddress: '00:11:22:33:44:55',
      );
      expect(explicit, isA<backend.QuickBlueLinux>());
      expect(explicit.adapterAddress, '00:11:22:33:44:55');
      await explicit.close();

      legacy.QuickBlueLinux.registerWith();
      final installed = QuickBluePlatform.instance as backend.QuickBlueLinux;
      expect(
        QuickBlue.bluetoothStateStream,
        same(installed.bluetoothStateStream),
      );
      expect(await QuickBlue.capabilities(), isA<QuickBlueCapabilities>());
      await installed.close();
    },
  );
}
