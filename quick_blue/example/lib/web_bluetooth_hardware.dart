/// Browser-only, read-only-by-default hardware verification entry point.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:web/web.dart' as web;

void main() => runApp(const MaterialApp(home: HardwarePage()));

class HardwarePage extends StatefulWidget {
  const HardwarePage({super.key});
  @override
  State<HardwarePage> createState() => _HardwarePageState();
}

class _HardwarePageState extends State<HardwarePage> {
  final profile = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert({
      'profile': 'replace-with-known-peripheral',
      'adapter': '',
      'peripheral': '',
      'firmware': '',
      'service': '180f',
      'namePrefix': '',
      'filterServices': ['180f'],
      'optionalServices': <String>[],
      'readCharacteristic': '2a19',
      'expectedRead': [42],
      'notifyCharacteristic': '',
      'expectedNotification': <int>[],
      'writeCharacteristic': '',
      'safeWrite': <int>[],
      'repeat': 2,
    }),
  );
  final stages = <Map<String, Object?>>[];
  bool busy = false;
  bool allowWrite = false;
  Map<String, dynamic>? selectedProfile;
  BluetoothDevice? selected;
  DateTime? started;
  static const deadline = Duration(seconds: 25);
  static const sourceSha = String.fromEnvironment('QUICK_BLUE_SOURCE_SHA');

  void initializeStages(Map<String, dynamic> p) {
    started ??= DateTime.now().toUtc();
    selectedProfile = p;
    for (final name in [
      'selection',
      'permission cancel',
      'peripheral loss/recovery',
      for (var cycle = 1; cycle <= (p['repeat'] as int); cycle++)
        for (final step in [
          'connect',
          'discovery',
          'read assertion',
          'safe write',
          'notification',
          'disconnect cleanup',
        ])
          '$cycle $step',
    ]) {
      if (!stages.any((s) => s['stage'] == name)) {
        record(name, 'BLOCKED', 'Not executed.');
      }
    }
  }

  Map<String, dynamic> prepareStandalone() {
    started ??= DateTime.now().toUtc();
    final p = parse();
    require(
      selectedProfile == null || jsonEncode(selectedProfile) == jsonEncode(p),
      'Profile changed: start a new full run before standalone checks.',
    );
    initializeStages(p);
    return p;
  }

  void record(String name, String result, [Object? detail]) {
    setState(() {
      stages.removeWhere((s) => s['stage'] == name && s['result'] == 'BLOCKED');
      stages.add({
        'stage': name,
        'result': result,
        'detail': detail?.toString(),
        'at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<T> stage<T>(
    String name,
    Future<T> Function() action, {
    Duration timeout = deadline,
  }) async {
    try {
      final value = await action().timeout(timeout);
      record(name, 'PASS');
      return value;
    } catch (error) {
      final blocked =
          error is QuickBlueException &&
          (error.code == QuickBlueErrorCode.unsupported ||
              error.code == QuickBlueErrorCode.unavailable);
      record(name, blocked ? 'BLOCKED' : 'FAIL', error);
      rethrow;
    }
  }

  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Uint8List payload(Map<String, dynamic> p, String key) {
    final list = (p[key] as List).cast<int>();
    require(
      list.every((b) => b >= 0 && b <= 255),
      '$key must contain bytes 0..255',
    );
    return Uint8List.fromList(list);
  }

  bool same(List<int> a, List<int> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);

  Map<String, dynamic> parse() {
    final p = jsonDecode(profile.text) as Map<String, dynamic>;
    require(
      (p['repeat'] as int) >= 1 && (p['repeat'] as int) <= 10,
      'repeat must be 1..10',
    );
    for (final key in [
      'profile',
      'adapter',
      'peripheral',
      'firmware',
      'service',
    ]) {
      require((p[key] as String).isNotEmpty, 'Provide $key before selection');
    }
    require(sourceSha.isNotEmpty, 'Build with QUICK_BLUE_SOURCE_SHA');
    payload(p, 'expectedRead');
    payload(p, 'expectedNotification');
    payload(p, 'safeWrite');
    final filters =
        (p['filterServices'] as List?)?.cast<String>() ??
        [p['service'] as String];
    require(
      filters.isNotEmpty || (p['namePrefix'] as String? ?? '').isNotEmpty,
      'Provide filterServices or namePrefix; unrestricted selection is disabled',
    );
    return p;
  }

  Future<BluetoothDevice> pick(Map<String, dynamic> p) =>
      QuickBlue.requestDevice(
        serviceUuids:
            (p['filterServices'] as List?)?.cast<String>() ??
            [p['service'] as String],
        namePrefix: (p['namePrefix'] as String? ?? '').isEmpty
            ? null
            : p['namePrefix'] as String,
        optionalServices:
            (p['optionalServices'] as List?)?.cast<String>() ?? [],
      );

  Future<void> run() async {
    if (busy) return;
    setState(() {
      busy = true;
      stages.clear();
      selectedProfile = null;
      selected = null;
      started = DateTime.now().toUtc();
    });
    BluetoothDevice? device;
    try {
      final p = parse();
      initializeStages(p);
      for (var cycle = 1; cycle <= (p['repeat'] as int); cycle++) {
        for (final name in [
          'connect',
          'discovery',
          'read assertion',
          'safe write',
          'notification',
          'disconnect cleanup',
        ]) {
          record('$cycle $name', 'BLOCKED', 'Not executed.');
        }
      }
      record('permission cancel', 'BLOCKED', 'Run separate cancel check.');
      record('peripheral loss/recovery', 'BLOCKED', 'Run separate loss check.');
      // Must be the first asynchronous API: no awaited availability preflight.
      final picker = pick(p);
      device = await stage('selection', () => picker);
      selected = device;
      for (var cycle = 1; cycle <= (p['repeat'] as int); cycle++) {
        final d = device!;
        try {
          await stage('$cycle connect', () => d.connect(timeout: deadline));
          final gatt = await stage(
            '$cycle discovery',
            () => d.discoverGatt(timeout: deadline),
          );
          if ((p['readCharacteristic'] as String? ?? '').isEmpty) {
            record(
              '$cycle read assertion',
              'BLOCKED',
              'No documented safe read characteristic/payload configured.',
            );
          } else {
            final read = gatt.characteristic(
              p['readCharacteristic'] as String,
              service: p['service'] as String,
            );
            await stage('$cycle read assertion', () async {
              final value = await read.read();
              require(
                same(value, payload(p, 'expectedRead')),
                'Unexpected read bytes: $value',
              );
            });
          }
          if (allowWrite) {
            await stage('$cycle safe write', () async {
              require(
                (p['writeCharacteristic'] as String).isNotEmpty &&
                    payload(p, 'safeWrite').isNotEmpty,
                'Known-safe write profile required',
              );
              final c = gatt.characteristic(
                p['writeCharacteristic'] as String,
                service: p['service'] as String,
              );
              await c.write(
                payload(p, 'safeWrite'),
                BleOutputProperty.withResponse,
              );
            });
          } else {
            record(
              '$cycle safe write',
              'BLOCKED',
              'Read-only default: explicitly opt in only with known-safe bytes.',
            );
          }
          if ((p['notifyCharacteristic'] as String).isEmpty ||
              payload(p, 'expectedNotification').isEmpty) {
            record(
              '$cycle notification',
              'BLOCKED',
              'Configure an expected notification payload and arrange a peripheral trigger.',
            );
          } else {
            stages.removeWhere(
              (s) =>
                  s['stage'] == '$cycle notification' &&
                  s['result'] == 'BLOCKED',
            );
            final c = gatt.characteristic(
              p['notifyCharacteristic'] as String,
              service: p['service'] as String,
            );
            for (var listen = 1; listen <= 2; listen++) {
              StreamSubscription<Uint8List>? subscription;
              final received = Completer<Uint8List>();
              try {
                await stage('$cycle notification $listen payload', () async {
                  subscription = c.notifications().listen(
                    (value) {
                      if (!received.isCompleted) received.complete(value);
                    },
                    onError: (Object error, StackTrace stack) {
                      if (!received.isCompleted) {
                        received.completeError(error, stack);
                      }
                    },
                  );
                  final value = await received.future;
                  require(
                    same(value, payload(p, 'expectedNotification')),
                    'Unexpected notification bytes: $value',
                  );
                });
              } finally {
                await stage('$cycle notification $listen cleanup', () async {
                  await subscription?.cancel();
                });
              }
            }
            record('$cycle notification', 'PASS');
          }
        } finally {
          await stage(
            '$cycle disconnect cleanup',
            () => d.disconnect(timeout: deadline),
          );
        }
      }
      record(
        'permission cancel',
        'BLOCKED',
        'Use the separate cancel-check button.',
      );
      record(
        'peripheral loss/recovery',
        'BLOCKED',
        'Use the separate loss-check button.',
      );
    } catch (error) {
      record(
        stages.isEmpty ? 'profile/environment' : 'run',
        stages.any((s) => s['result'] == 'FAIL') ? 'FAIL' : 'BLOCKED',
        error,
      );
    } finally {
      if (device != null) {
        try {
          await stage(
            'final cleanup',
            () => device!.disconnect(timeout: deadline),
          );
        } catch (_) {
          /* stage already records failure */
        }
      }
      setState(() => busy = false);
    }
  }

  Future<void> cancelCheck() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final p = prepareStandalone();
      final picker = pick(p);
      try {
        await picker.timeout(deadline);
        record(
          'permission cancel',
          'FAIL',
          'A device was selected. Repeat and press Cancel.',
        );
      } catch (error) {
        // Browser NotFoundError conflates cancellation and no matching devices.
        if (error is! QuickBlueException ||
            error.details is! Map ||
            (error.details as Map)['chooserNotFound'] != true) {
          record('permission cancel', 'BLOCKED', error);
          return;
        }
        if (!mounted) return;
        final navigator = Navigator.of(context, rootNavigator: true);
        final route = DialogRoute<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm observed cancellation'),
            content: Text(
              'Browser rejected selection: $error\nDid you see the chooser and explicitly press Cancel? Do not confirm permission denial or missing API.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No / unsure'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes, I pressed Cancel'),
              ),
            ],
          ),
        );
        bool? confirmed;
        try {
          confirmed = await navigator.push(route).timeout(deadline);
        } on TimeoutException {
          if (route.isActive) navigator.removeRoute(route);
          record(
            'permission cancel',
            'BLOCKED',
            'Operator confirmation timed out.',
          );
          return;
        }
        record(
          'permission cancel',
          confirmed == true ? 'PASS' : 'BLOCKED',
          'Observed rejection: $error. Operator confirmed actual Cancel: $confirmed.',
        );
      }
    } catch (error) {
      record('permission cancel', 'BLOCKED', error);
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> lossCheck() async {
    if (busy) return;
    try {
      prepareStandalone();
    } catch (error) {
      record('peripheral loss/recovery', 'BLOCKED', error);
      return;
    }
    final d = selected;
    if (d == null) {
      record(
        'peripheral loss/recovery',
        'BLOCKED',
        'Select a known peripheral first.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      await stage('loss check connect', () => d.connect(timeout: deadline));

      await stage('remote disconnect assertion', () async {
        final event = await d.connectionStateStream
            .timeout(const Duration(seconds: 60))
            .firstWhere((e) => e.state == BlueConnectionState.disconnected);
        require(
          event.error?.failureReason ==
              QuickBlueFailureReason.remoteDisconnected,
          'Expected remote disconnect',
        );
      }, timeout: const Duration(seconds: 60));
      await stage('recovery reconnect', () async {
        final until = DateTime.now().add(const Duration(seconds: 60));
        Object? last;
        while (DateTime.now().isBefore(until)) {
          try {
            await d.connect(timeout: until.difference(DateTime.now()));
            final remaining = until.difference(DateTime.now());
            require(remaining > Duration.zero, 'Recovery deadline elapsed');
            await d.discoverGatt(timeout: remaining);
            return;
          } catch (error) {
            last = error;
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
        throw StateError('Peripheral did not recover: $last');
      }, timeout: const Duration(seconds: 65));
      record(
        'peripheral loss/recovery',
        'PASS',
        'Observed remote loss and rediscovered after reconnect.',
      );
    } catch (_) {
      /* stage already records failure */
    } finally {
      try {
        await stage(
          'loss check cleanup',
          () => d.disconnect(timeout: deadline),
        );
      } catch (_) {
        /* recorded */
      }
      setState(() => busy = false);
    }
  }

  Map<String, Object?> report() => {
    'evidence': 'real browser hardware run (not simulator)',
    'sourceSha': sourceSha,
    'started': started?.toIso8601String(),
    'browserOs': web.window.navigator.userAgent,
    'secureContext': web.window.isSecureContext,
    'profile': selectedProfile,
    'selectedDeviceId': selected?.deviceId,
    'aggregate':
        started == null ||
            selectedProfile == null ||
            selected == null ||
            sourceSha.isEmpty ||
            stages.isEmpty ||
            stages.any((s) => s['result'] == 'BLOCKED')
        ? (stages.any((s) => s['result'] == 'FAIL') ? 'FAIL' : 'BLOCKED')
        : (stages.any((s) => s['result'] == 'FAIL') ? 'FAIL' : 'PASS'),
    'stages': stages,
  };
  void download() {
    final url = web.URL.createObjectURL(
      web.Blob(
        [jsonEncode(report()).toJS].toJS,
        web.BlobPropertyBag(type: 'application/json'),
      ),
    );
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = 'quick-blue-web-hardware.json';
    anchor.click();
    web.URL.revokeObjectURL(url);
  }

  @override
  void dispose() {
    profile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Quick Blue Web Bluetooth hardware verification'),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use only your known peripheral. No writes by default. Enter adapter, peripheral, firmware and exact expected payloads. During notification stages trigger your peripheral. All waits are bounded. BLOCKED is not PASS.',
          ),
          TextField(
            controller: profile,
            minLines: 12,
            maxLines: 20,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Hardware profile JSON',
            ),
          ),
          CheckboxListTile(
            value: allowWrite,
            onChanged: busy
                ? null
                : (value) => setState(() => allowWrite = value!),
            title: const Text(
              'I authorize these known-safe write bytes on my selected peripheral',
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              ElevatedButton(
                onPressed: busy ? null : run,
                child: const Text('Select device and run loops'),
              ),
              ElevatedButton(
                onPressed: busy ? null : cancelCheck,
                child: const Text('Open chooser — press Cancel'),
              ),
              ElevatedButton(
                onPressed: busy ? null : lossCheck,
                child: const Text('Manual loss / recovery check'),
              ),
              ElevatedButton(
                onPressed: download,
                child: const Text('Export JSON'),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          SelectableText(const JsonEncoder.withIndent('  ').convert(report())),
        ],
      ),
    ),
  );
}
