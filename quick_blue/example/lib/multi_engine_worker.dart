import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quick_blue/quick_blue.dart';

const _workerChannel = MethodChannel('quick_blue.example/multi_engine_worker');

/// Reference used by the integration-test root to retain this Dart library.
Function get multiEngineWorkerEntrypointReference => multiEngineWorkerMain;

/// Secondary Flutter-engine entrypoint for Android and iOS multi-engine tests.
@pragma('vm:entry-point')
Future<void> multiEngineWorkerMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (Platform.isAndroid) {
    QuickBlueAndroid.registerWith();
  }
  _workerChannel.setMethodCallHandler((call) async {
    final arguments = (call.arguments as Map<Object?, Object?>?) ?? const {};
    final deviceId = arguments['deviceId'] as String;
    final device = QuickBlue.device(deviceId);
    switch (call.method) {
      case 'connect':
        if (Platform.isIOS) {
          await _waitForBluetooth();
        }
        await device.connect().timeout(const Duration(seconds: 15));
        return null;
      case 'discoverServices':
        return (await device.discoverServices().timeout(
          const Duration(seconds: 15),
        )).length;
      case 'disconnect':
        await device.disconnect().timeout(const Duration(seconds: 10));
        return null;
      case 'setNotifiable':
        final serviceId = arguments['serviceId'] as String;
        final characteristicId = arguments['characteristicId'] as String;
        final property = switch (arguments['property']) {
          'notification' => BleInputProperty.notification,
          'indication' => BleInputProperty.indication,
          'disabled' => BleInputProperty.disabled,
          final Object? property => throw ArgumentError.value(
            property,
            'property',
            'Unsupported notification property',
          ),
        };
        await device
            .characteristic(serviceId, characteristicId)
            .setNotifiable(property)
            .timeout(const Duration(seconds: 10));
        return null;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          message: 'Unknown worker method ${call.method}',
        );
    }
  });
  await _signalReady();
}

Future<void> _waitForBluetooth() async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  do {
    if (await QuickBlue.isBluetoothAvailable()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  } while (DateTime.now().isBefore(deadline));
  throw StateError('Bluetooth is unavailable in the secondary engine.');
}

Future<void> _signalReady() async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  do {
    try {
      await _workerChannel.invokeMethod<void>('ready');
      return;
    } on MissingPluginException {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  } while (DateTime.now().isBefore(deadline));
  throw StateError(
    'The native multi-engine worker channel was not registered.',
  );
}
