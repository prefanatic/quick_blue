import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/multi_engine_test_support.dart';

const _deviceId = String.fromEnvironment('QUICK_BLUE_MULTI_ENGINE_DEVICE_ID');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two Android engines share one native GATT connection', (
    _,
  ) async {
    await runMultiEngineConnectionScenario(
      targetDescription: 'BLE device',
      deviceId: _deviceId,
    );
  });
}
