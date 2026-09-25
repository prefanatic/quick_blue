// Copyright (c) 2026, the quick_blue authors.
// Use of this source code is governed by the BSD-3-Clause license.

import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_darwin/quick_blue_darwin.dart';

const _deviceId = String.fromEnvironment('QUICK_BLUE_MULTI_ENGINE_DEVICE_ID');
const _namePattern = String.fromEnvironment(
  'QUICK_BLUE_MULTI_ENGINE_NAME_PATTERN',
);
const _serviceId = String.fromEnvironment(
  'QUICK_BLUE_MULTI_ENGINE_SERVICE_UUID',
);
const _characteristicId = String.fromEnvironment(
  'QUICK_BLUE_MULTI_ENGINE_CHARACTERISTIC_UUID',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a second Dart isolate receives Darwin Bluetooth state', (
    _,
  ) async {
    final mailbox = ReceivePort();
    final messages = mailbox.asBroadcastStream();
    final isolate = await Isolate.spawn(_worker, mailbox.sendPort);
    try {
      final worker =
          await messages.first.timeout(const Duration(seconds: 5)) as SendPort;
      final response = messages.first;
      worker.send('isBluetoothAvailable');
      expect(
        await response.timeout(const Duration(seconds: 10)),
        await QuickBlue.isBluetoothAvailable(),
      );
    } finally {
      isolate.kill(priority: Isolate.immediate);
      mailbox.close();
    }
  });

  testWidgets('a second Dart isolate shares the Darwin connection', (_) async {
    if (_deviceId.isEmpty && _namePattern.isEmpty) {
      fail('Set a BLE device UUID or a name pattern for this test.');
    }
    final ready = DateTime.now().add(const Duration(seconds: 8));
    while (!await QuickBlue.isBluetoothAvailable()) {
      if (DateTime.now().isAfter(ready)) {
        fail('Bluetooth did not become available.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final deviceId = _namePattern.isEmpty
        ? _deviceId
        : (await QuickBlue.scanResults()
                  .firstWhere(
                    (result) => RegExp(
                      _namePattern,
                      caseSensitive: false,
                    ).hasMatch(result.name),
                  )
                  .timeout(const Duration(seconds: 15)))
              .deviceId;
    final primary = QuickBlue.device(deviceId);
    await primary.connect().timeout(const Duration(seconds: 15));
    var primaryConnected = true;
    final mailbox = ReceivePort();
    final messages = mailbox.asBroadcastStream();
    final isolate = await Isolate.spawn(_worker, mailbox.sendPort);
    try {
      final worker =
          await messages.first.timeout(const Duration(seconds: 5)) as SendPort;

      Future<Object?> call(
        String method, [
        List<Object?> arguments = const [],
      ]) async {
        final response = messages.first;
        worker.send([method, deviceId, ...arguments]);
        final value = await response.timeout(const Duration(seconds: 20));
        if (value is String) throw StateError(value);
        return value;
      }

      await call('connect');
      expect(await call('discoverServices'), greaterThan(0));
      final services = await primary.discoverServices();
      expect(services, isNotEmpty);
      if (_serviceId.isNotEmpty && _characteristicId.isNotEmpty) {
        final handle = primary.characteristic(_serviceId, _characteristicId);
        await handle.setNotifiable(BleInputProperty.notification);
        await call('setNotifiable', [
          _serviceId,
          _characteristicId,
          'notification',
        ]);
        await handle.setNotifiable(BleInputProperty.disabled);
      }
      await primary.disconnect().timeout(const Duration(seconds: 10));
      primaryConnected = false;
      expect(await call('discoverServices'), greaterThan(0));
      if (_serviceId.isNotEmpty && _characteristicId.isNotEmpty) {
        await call('setNotifiable', [
          _serviceId,
          _characteristicId,
          'disabled',
        ]);
      }
      await call('disconnect');
      await call('exit');
    } finally {
      isolate.kill(priority: Isolate.immediate);
      mailbox.close();
      if (primaryConnected) {
        try {
          await primary.disconnect().timeout(const Duration(seconds: 10));
        } on PlatformException catch (error) {
          if (error.code != 'IllegalArgument' && error.code != 'Disconnected') {
            rethrow;
          }
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

void _worker(SendPort parent) {
  _runWorker(parent).catchError((Object error, StackTrace stack) {
    parent.send('$error\n$stack');
  });
}

Future<void> _runWorker(SendPort parent) async {
  QuickBlueDarwin.registerWith();
  final inbox = ReceivePort();
  parent.send(inbox.sendPort);
  await for (final message in inbox) {
    try {
      final command = message is List<Object?> ? message[0] : message;
      final deviceId = message is List<Object?>
          ? message[1] as String
          : _deviceId;
      final device = QuickBlue.device(deviceId);
      switch (command) {
        case 'isBluetoothAvailable':
          parent.send(await QuickBlue.isBluetoothAvailable());
        case 'connect':
          await device.connect().timeout(const Duration(seconds: 15));
          parent.send(true);
        case 'discoverServices':
          final services = await device.discoverServices().timeout(
            const Duration(seconds: 15),
          );
          parent.send(services.length);
        case 'disconnect':
          await device.disconnect().timeout(const Duration(seconds: 10));
          parent.send(true);
        case 'setNotifiable':
          final data = message as List<Object?>;
          final property = switch (data[4]) {
            'notification' => BleInputProperty.notification,
            'indication' => BleInputProperty.indication,
            'disabled' => BleInputProperty.disabled,
            _ => throw ArgumentError.value(data[4], 'property'),
          };
          await device
              .characteristic(data[2] as String, data[3] as String)
              .setNotifiable(property)
              .timeout(const Duration(seconds: 10));
          parent.send(true);
        case 'exit':
          parent.send(true);
          inbox.close();
          return;
        default:
          parent.send('Unknown worker command: $message');
      }
    } catch (error) {
      parent.send(error.toString());
    }
  }
}
