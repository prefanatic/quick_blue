import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quick_blue/quick_blue.dart';

const _workerChannel = MethodChannel('quick_blue.example/multi_engine_worker');

/// Reference used by the integration-test root to retain this Dart library.
Function get multiEngineWorkerEntrypointReference => multiEngineWorkerMain;

/// Secondary Flutter-engine entrypoint for Android multi-engine testing.
@pragma('vm:entry-point')
Future<void> multiEngineWorkerMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  QuickBlueAndroid.registerWith();
  _workerChannel.setMethodCallHandler((call) async {
    final arguments = (call.arguments as Map<Object?, Object?>?) ?? const {};
    final deviceId = arguments['deviceId'] as String;
    final device = QuickBlue.device(deviceId);
    switch (call.method) {
      case 'connect':
        await device.connect().timeout(const Duration(seconds: 15));
        return null;
      case 'discoverServices':
        return (await device.discoverServices().timeout(
          const Duration(seconds: 15),
        )).length;
      case 'disconnect':
        await device.disconnect().timeout(const Duration(seconds: 10));
        return null;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          message: 'Unknown worker method ${call.method}',
        );
    }
  });
  await _workerChannel.invokeMethod<void>('ready');
}
