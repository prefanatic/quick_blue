// Deterministic public-platform fake. No BlueZ, D-Bus, agent, or radio calls.
import 'dart:async';
import 'dart:typed_data';

import 'package:quick_blue_linux/quick_blue_linux.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'cli.dart';

const adapterId = '02:00:00:00:00:01';
const deviceId = '02:00:00:00:00:02';
const serviceId = '12345678-1234-5678-1234-567812345678';
const characteristicId = '12345678-1234-5678-1234-567812345679';
const flowArgs = [
  '--adapter',
  adapterId,
  '--service',
  serviceId,
  '--scan-seconds',
  '1',
  '--device',
  deviceId,
  '--characteristic',
  characteristicId,
  '--pair',
  '--read',
  '--write-hex',
  '0102',
  '--notify-seconds',
  '1',
];

class FakeRuntime extends QuickBluePlatform with ExplicitPairingOnly {
  final calls = <String>[];
  final scans = StreamController<BlueScanResult>.broadcast();
  Object? pairError;
  Object? readError;
  Object? notifyError;
  Object? scanError;
  Object? closeError;
  Completer<void>? connectGate;
  bool closed = false;
  CliRuntime runtime(String? address) {
    if (address != adapterId) throw StateError('wrong adapter');
    return CliRuntime(
      platform: this,
      adapters: () async => [
        const QuickBlueLinuxAdapter(address: adapterId, powered: true),
      ],
      close: () async {
        calls.add('close');
        closed = true;
        await scans.close();
        if (closeError != null) throw closeError!;
      },
    );
  }

  @override
  Stream<BlueScanResult> get scanResultStream => scans.stream;
  @override
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) async {
    if (scanFilter.serviceUuids.single != serviceId)
      throw StateError('missing service filter');
    calls.add('scan');
    Timer.run(() {
      if (scanError != null) {
        scans.addError(scanError!);
        return;
      }
      scans.add(
        BlueScanResult(
          name: 'Synthetic sensor',
          deviceId: deviceId,
          rssi: -42,
          serviceUuids: [serviceId],
          serviceData: {
            serviceId: Uint8List.fromList([1, 2]),
          },
        ),
      );
    });
  }

  @override
  Future<void> stopScan() async {
    calls.add('stopScan');
  }

  @override
  Future<void> connect(String id) async {
    calls.add('connect $id');
    await connectGate?.future;
    onConnectionChanged?.call(
      id,
      BlueConnectionState.connected,
      BleStatus.success,
    );
  }

  @override
  Future<void> disconnect(String id) async {
    calls.add('disconnect $id');
    onConnectionChanged?.call(
      id,
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
  }

  @override
  Future<void> pair(String id) async {
    calls.add('pair $id');
    if (pairError != null) throw pairError!;
  }

  @override
  Future<void> discoverServices(String id) async {
    calls.add('discover $id');
    handleServiceDiscovered(id, serviceId, [
      BluetoothCharacteristicInfo(uuid: characteristicId),
    ]);
    onServiceDiscoveryComplete(id);
  }

  @override
  Future<Uint8List> readCharacteristicValue(
    String id,
    String service,
    String characteristic,
  ) async {
    calls.add('read $id');
    if (readError != null) throw readError!;
    return Uint8List.fromList([3]);
  }

  @override
  Future<void> writeValue(
    String id,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty mode,
  ) async {
    if (hex(value) != '0102' || mode != BleOutputProperty.withResponse)
      throw StateError('unexpected write');
    calls.add('write $id');
  }

  @override
  Future<void> setNotifiable(
    String id,
    String service,
    String characteristic,
    BleInputProperty mode,
  ) async {
    calls.add('notify $mode $id');
    if (notifyError != null) throw notifyError!;
    if (mode != BleInputProperty.disabled) {
      // The stream starts forwarding only after setup's Future completes.
      Timer.run(
        () => handleCharacteristicValueChanged(
          id,
          service,
          characteristic,
          Uint8List.fromList([4]),
        ),
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected platform call: ${invocation.memberName}');
}

Future<void> fakeFlow(void Function(String) output) async {
  final fake = FakeRuntime();
  final lines = <String>[];
  await runCli(
    flowArgs,
    output: (line) {
      lines.add(line);
      output(line);
    },
    createRuntime: fake.runtime,
  );
  final expected = [
    'scan',
    'stopScan',
    'connect $deviceId',
    'pair $deviceId',
    'discover $deviceId',
    'read $deviceId',
    'write $deviceId',
    'notify notification $deviceId',
    'notify disabled $deviceId',
    'disconnect $deviceId',
    'close',
  ];
  if (fake.calls.join('|') != expected.join('|') ||
      !lines.any(
        (line) => line.contains('"serviceData":{"$serviceId":"0102"}'),
      ) ||
      !lines.contains('notify 04') ||
      !fake.closed ||
      fake.scans.hasListener) {
    throw StateError(
      'Fake sequence/advertisement/cleanup mismatch: ${fake.calls}',
    );
  }
  output('PASS: fake-only public CLI sequence; no radio proof');
}
