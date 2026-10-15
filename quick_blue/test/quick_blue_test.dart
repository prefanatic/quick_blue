import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/quick_blue.dart' as flutter;
import 'package:quick_blue/src/quick_blue.dart' as legacy;
import 'package:quick_blue_core/quick_blue_core.dart' as core;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Flutter and former implementation libraries reexport core types', () {
    expect(flutter.QuickBlue, same(core.QuickBlue));
    expect(legacy.QuickBlue, same(core.QuickBlue));
    expect(flutter.BluetoothDevice, same(core.BluetoothDevice));
    expect(flutter.QuickBlueCompanion, same(core.QuickBlueCompanion));
    expect(
      flutter.QuickBlueAppleAccessorySetup,
      same(core.QuickBlueAppleAccessorySetup),
    );
    expect(legacy.QuickBlueAndroid, same(flutter.QuickBlueAndroid));
  });

  test(
    'all entrypoints share the platform instance and instrumentation',
    () async {
      final previous = QuickBluePlatform.instance;
      final platform = FakeQuickBluePlatform();
      final observer = _Observer();
      try {
        QuickBluePlatform.instance = platform;
        flutter.QuickBlue.observer = observer;
        expect(core.QuickBlue.observer, same(observer));
        expect(legacy.QuickBlue.observer, same(observer));
        await core.QuickBlue.configure(maintainState: true);
        await flutter.QuickBlue.configure();
        await legacy.QuickBlue.configure();
        expect(platform.calls, [
          'configure true',
          'configure false',
          'configure false',
        ]);
        expect(observer.operations, 3);
        expect(
          core.QuickBlue.device('synthetic-device').id,
          'synthetic-device',
        );
      } finally {
        flutter.QuickBlue.observer = null;
        QuickBluePlatform.instance = previous;
        await platform.dispose();
      }
    },
  );
}

class _Observer implements core.QuickBlueObserver {
  int operations = 0;

  @override
  core.QuickBlueOperationObservation? onOperationStarted(
    core.QuickBlueOperation operation,
  ) {
    operations++;
    return null;
  }
}
