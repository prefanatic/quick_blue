import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quick_blue_core/quick_blue_core.dart';
import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

const help =
    '''Headless BLE operator example (no automatic pairing or bond replacement)
--help                       No bus connection
--list-adapters              List adapter addresses and power state
--adapter ADDRESS --service UUID [--scan-seconds 5]
                             Scan only; print advertisement JSON
Add --device ADDRESS         Select exactly this discovered device and discover GATT
--pair                       Explicitly pair only the selected device
--characteristic UUID        Resolve a snapshot-bound handle under --service
--read                       Read only when explicitly requested
--write-hex HEX               Explicit acknowledged write; know your peripheral protocol
--notify-seconds N           Subscribe for N seconds, then cancel
Ctrl-C stops scan/connection waiting/notification observation; finally releases resources.
No flag powers an adapter, registers an agent, trusts a device, or removes a bond.
''';

/// The CLI opts out of the library's normal automatic pairing recovery.
/// Existing Flutter and library consumers retain their established behavior.
mixin ExplicitPairingOnly on QuickBluePlatform {
  @override
  Future<QuickBlueSecurityRecoveryResult> performSecurityRecovery(
    String deviceId,
    QuickBlueSecurityException error,
  ) async => QuickBlueSecurityRecoveryResult.userActionRequired;
}

class OperatorLinux extends QuickBlueLinux with ExplicitPairingOnly {
  OperatorLinux({super.adapterAddress});
}

class CliRuntime {
  CliRuntime({
    required this.platform,
    required this.adapters,
    required this.close,
  });
  final QuickBluePlatform platform;
  final Future<List<QuickBlueLinuxAdapter>> Function() adapters;
  final Future<void> Function() close;
}

CliRuntime linuxRuntime(String? address) {
  final linux = OperatorLinux(adapterAddress: address);
  return CliRuntime(
    platform: linux,
    adapters: linux.adapters,
    close: linux.close,
  );
}

class Options {
  Options(List<String> args) {
    const flags = {'help', 'list-adapters', 'pair', 'read'};
    const values = {
      'adapter',
      'service',
      'device',
      'characteristic',
      'scan-seconds',
      'write-hex',
      'notify-seconds',
    };
    for (var i = 0; i < args.length; i++) {
      final key = args[i].startsWith('--') ? args[i].substring(2) : '';
      if ((!flags.contains(key) && !values.contains(key)) ||
          options.containsKey(key)) {
        throw FormatException('Unknown or duplicate option: ${args[i]}');
      }
      if (flags.contains(key)) {
        options[key] = '';
      } else {
        if (++i == args.length || args[i].startsWith('--')) {
          throw FormatException('Missing value for --$key');
        }
        options[key] = args[i];
      }
    }
    if (has('help')) return;
    if (has('list-adapters')) {
      if (options.length != 1)
        throw const FormatException('Use --list-adapters alone');
      return;
    }
    if (!has('adapter') || !has('service')) {
      throw const FormatException('--adapter and --service are required');
    }
    validateUuid(options['service']!);
    if (has('characteristic')) validateUuid(options['characteristic']!);
    seconds('scan-seconds', 5);
    seconds('notify-seconds', 0);
    if ((has('pair') ||
            has('read') ||
            has('write-hex') ||
            has('notify-seconds')) &&
        !has('device')) {
      throw const FormatException('IO and pairing require --device');
    }
    if ((has('read') || has('write-hex') || has('notify-seconds')) &&
        !has('characteristic')) {
      throw const FormatException('IO requires --characteristic');
    }
    if (has('write-hex')) {
      final value = options['write-hex']!;
      if (value.isEmpty ||
          value.length.isOdd ||
          !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
        throw const FormatException(
          '--write-hex requires nonempty even-length hex',
        );
      }
    }
  }
  final options = <String, String>{};
  bool has(String key) => options.containsKey(key);
  int seconds(String key, int fallback) {
    if (!has(key)) return fallback;
    final value = int.tryParse(options[key]!);
    if (value == null || value <= 0 || value > 3600) {
      throw FormatException('--$key must be 1..3600');
    }
    return value;
  }
}

void validateUuid(String value) {
  if (!RegExp(
    r'^(?:[0-9a-fA-F]{4}|[0-9a-fA-F]{8}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$',
  ).hasMatch(value)) {
    throw FormatException('Invalid Bluetooth UUID: $value');
  }
}

String hex(List<int> value) =>
    value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<void> waitInterval(
  int seconds,
  Future<void> stop,
  Future<void> error,
) async {
  final elapsed = Completer<void>();
  final timer = Timer(Duration(seconds: seconds), elapsed.complete);
  try {
    await Future.any([elapsed.future, stop, error]);
  } finally {
    timer.cancel();
  }
}

/// Injectable runtime and stop signal keep the executable workflow fake-testable.
Future<void> runCli(
  List<String> args, {
  required void Function(String) output,
  Future<void>? stop,
  CliRuntime Function(String?) createRuntime = linuxRuntime,
}) async {
  final options = Options(args);
  if (options.has('help')) {
    output(help);
    return;
  }
  final runtime = createRuntime(options.options['adapter']);
  // Explicit registration: no Flutter engine/plugin registrant is involved.
  QuickBluePlatform.instance = runtime.platform;
  final token = QuickBlueCancellationToken();
  var stopped = false;
  final stopWait = stop ?? Completer<void>().future;
  // This handler cannot throw; native pairing/IO already submitted is not aborted.
  stopWait.then<void>(
    (_) {
      stopped = true;
      token.cancel();
    },
    onError: (Object error, StackTrace stack) {
      stopped = true;
      token.cancel();
      output('stop signal failed: $error');
    },
  );
  StreamSubscription<BlueScanResult>? scan;
  StreamSubscription<Uint8List>? notifications;
  BluetoothDevice? device;
  Object? primary;
  Future<void> cleanup(String name, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      output('cleanup $name failed: $error');
      if (primary == null) {
        primary = error;
        rethrow;
      }
    }
  }

  try {
    for (final adapter in await runtime.adapters()) {
      output(
        jsonEncode({'adapter': adapter.address, 'powered': adapter.powered}),
      );
    }
    if (options.has('list-adapters') || stopped) return;
    final results = <String, BlueScanResult>{};
    final scanError = Completer<void>();
    scan = runtime.platform
        .scanResults(
          scanFilter: ScanFilter(serviceUuids: [options.options['service']!]),
        )
        .listen(
          (result) {
            results[result.deviceId] =
                result; // Retain full identity and service data, not just name.
            output(
              jsonEncode({
                'device': result.deviceId,
                'name': result.name,
                'rssi': result.rssi,
                'time': result.advertisedDateTime.toIso8601String(),
                'services': result.serviceUuids,
                'serviceData': result.serviceData.map(
                  (key, bytes) => MapEntry(key, hex(bytes)),
                ),
                'manufacturerData': hex(result.manufacturerData),
              }),
            );
          },
          onError: (Object error, StackTrace stack) {
            if (!scanError.isCompleted) scanError.completeError(error, stack);
          },
        );
    await waitInterval(
      options.seconds('scan-seconds', 5),
      stopWait,
      scanError.future,
    );
    await scan.cancel();
    scan = null;
    if (stopped || !options.has('device')) return;
    final id = options.options['device']!;
    if (!results.containsKey(id))
      throw StateError(
        'Selected device was not discovered by this filtered scan',
      );
    device = QuickBlue.device(
      id,
    ); // Public factory, never BluetoothDevice.internal.
    await device.connect(
      timeout: const Duration(seconds: 20),
      cancellationToken: token,
    );
    if (stopped) return;
    if (options.has('pair')) await device.pair();
    if (stopped) return;
    final gatt = await device.discoverGatt(
      timeout: const Duration(seconds: 20),
      cancellationToken: token,
    );
    for (final service in gatt.services) {
      output('service ${service.uuid}: ${service.characteristics}');
    }
    if (!options.has('characteristic') || stopped) return;
    final characteristic = gatt.boundCharacteristic(
      options.options['characteristic']!,
      service: options.options['service'],
    );
    if (options.has('read')) output('read ${hex(await characteristic.read())}');
    if (stopped) return;
    if (options.has('write-hex')) {
      final value = options.options['write-hex']!;
      final bytes = Uint8List.fromList([
        for (var i = 0; i < value.length; i += 2)
          int.parse(value.substring(i, i + 2), radix: 16),
      ]);
      await characteristic.write(bytes, BleOutputProperty.withResponse);
      output('write acknowledged');
    }
    if (stopped) return;
    if (options.has('notify-seconds')) {
      final error = Completer<void>();
      notifications = characteristic.notifications().listen(
        (bytes) => output('notify ${hex(bytes)}'),
        onError: (Object failure, StackTrace stack) {
          if (!error.isCompleted) error.completeError(failure, stack);
        },
      );
      await waitInterval(
        options.seconds('notify-seconds', 1),
        stopWait,
        error.future,
      );
    }
  } catch (error) {
    primary = error;
    rethrow;
  } finally {
    // Each cleanup is attempted even when a preceding cleanup fails.
    try {
      await cleanup('scan', () async {
        await scan?.cancel();
      });
    } finally {
      try {
        await cleanup('notifications', () async {
          await notifications?.cancel();
        });
      } finally {
        try {
          await cleanup('disconnect', () async {
            await device?.disconnect(timeout: const Duration(seconds: 20));
          });
        } finally {
          await cleanup('close', runtime.close);
        }
      }
    }
  }
}
