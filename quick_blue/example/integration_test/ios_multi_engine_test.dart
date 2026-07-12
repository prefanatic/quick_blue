import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue/quick_blue.dart';

import 'support/multi_engine_test_support.dart';

const _deviceId = String.fromEnvironment('QUICK_BLUE_MULTI_ENGINE_DEVICE_ID');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS starts and stops a headless secondary Flutter engine', (
    _,
  ) async {
    await startSecondaryEngine();
    await stopSecondaryEngine();
  });

  testWidgets('two iOS engines share one CoreBluetooth connection', (_) async {
    await runMultiEngineConnectionScenario(
      targetDescription: 'BLE device UUID',
      deviceId: _deviceId,
      preparePrimaryConnection: () async {
        await QuickBlue.scanResults()
            .firstWhere(
              (result) =>
                  result.deviceId.toLowerCase() == _deviceId.toLowerCase(),
            )
            .timeout(const Duration(seconds: 15));
      },
    );
  });
}
