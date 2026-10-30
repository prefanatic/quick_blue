import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:test/test.dart';
import 'package:logging/logging.dart';
import 'package:quick_blue_linux_dart/generated_bindings.dart';
import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';
import 'package:quick_blue_linux_dart/src/l2cap_channel.dart';
import 'package:quick_blue_linux_dart/src/l2cap_endpoint.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  late _FakeClient client;
  late Map<String, BlueZDevice> devices;
  late Logger logger;
  late _FakeChannel channel;
  late LinuxL2capEndpoint endpoint;
  late List<({String deviceId, int psm, int addressType, Logger logger})> calls;

  setUp(() {
    client = _FakeClient();
    devices = <String, BlueZDevice>{};
    logger = Logger('l2cap-endpoint-test');
    channel = _FakeChannel();
    calls = [];
    endpoint = LinuxL2capEndpoint(
      client: client,
      devices: devices,
      logger: logger,
      channelFactory:
          ({
            required deviceId,
            required psm,
            required addressType,
            required logger,
          }) {
            calls.add((
              deviceId: deviceId,
              psm: psm,
              addressType: addressType,
              logger: logger,
            ));
            return channel;
          },
    );
    addTearDown(channel.dispose);
  });

  test(
    'unknown device preserves structured error without creating a channel',
    () async {
      await expectLater(
        endpoint.open('missing', 25),
        throwsA(
          isA<QuickBlueException>()
              .having((e) => e.code, 'code', QuickBlueErrorCode.notFound)
              .having((e) => e.operation, 'operation', 'openL2cap')
              .having((e) => e.deviceId, 'deviceId', 'missing')
              .having(
                (e) => e.message,
                'message',
                'Bluetooth device missing is not known.',
              ),
        ),
      );
      expect(calls, isEmpty);
      expect(devices, isEmpty);
    },
  );

  test(
    'default endpoint rejects unknown devices before native loading',
    () async {
      final nativeEndpoint = LinuxL2capEndpoint(
        client: client,
        devices: devices,
        logger: logger,
      );
      await expectLater(
        nativeEndpoint.open('missing', 25),
        throwsA(isA<QuickBlueException>()),
      );
    },
  );

  test('cached device takes precedence over client device', () async {
    devices['device'] = _FakeDevice('device', BlueZAddressType.random);
    client.currentDevices = [_FakeDevice('device', BlueZAddressType.public)];
    final socket = await endpoint.open('device', 129);
    expect(socket, same(channel.socket));
    expect(client.deviceLookups, 0);
    expect(calls.single, (
      deviceId: 'device',
      psm: 129,
      addressType: BDADDR_LE_RANDOM,
      logger: logger,
    ));
    expect(channel.openCount, 1);
  });

  test('client fallback matches address and caches the device', () async {
    final device = _FakeDevice('target', BlueZAddressType.public);
    client.currentDevices = [
      _FakeDevice('other', BlueZAddressType.random),
      device,
    ];
    await endpoint.open('target', 25);
    expect(devices['target'], same(device));
    expect(calls.single.addressType, BDADDR_LE_PUBLIC);
    expect(client.deviceLookups, 1);
    client.currentDevices = [];
    await endpoint.open('target', 27);
    expect(client.deviceLookups, 1);
    expect(calls.map((call) => call.psm), [25, 27]);
    expect(channel.openCount, 2);
  });

  test('each open resolves the current cached address type', () async {
    devices['device'] = _FakeDevice('device', BlueZAddressType.random);
    await endpoint.open('device', 25);
    devices['device'] = _FakeDevice('device', BlueZAddressType.public);
    await endpoint.open('device', 25);
    expect(calls.map((call) => call.addressType), [
      BDADDR_LE_RANDOM,
      BDADDR_LE_PUBLIC,
    ]);
  });

  test(
    'PSM is forwarded unchanged, including dynamic and out-of-range values',
    () async {
      devices['device'] = _FakeDevice('device', BlueZAddressType.public);
      for (final psm in [0, -1, 65536]) {
        await endpoint.open('device', psm);
      }
      expect(calls.map((call) => call.psm), [0, -1, 65536]);
    },
  );

  test(
    'channel open failure logs and rethrows original error and stack',
    () async {
      final error = StateError('native connect failed');
      final stack = StackTrace.current;
      channel.failure = error;
      channel.failureStack = stack;
      final records = <LogRecord>[];
      final subscription = logger.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final device = _FakeDevice('device', BlueZAddressType.random);
      client.currentDevices = [device];
      try {
        await endpoint.open('device', 25);
        fail('Expected native error');
      } catch (actual, actualStack) {
        expect(actual, same(error));
        expect(actualStack.toString(), stack.toString());
      }
      expect(records.single.level, Level.SEVERE);
      expect(records.single.message, 'Unable to open L2CAP channel to device');
      expect(records.single.error, same(error));
      expect(records.single.stackTrace.toString(), stack.toString());
      expect(devices['device'], same(device));
      channel.failure = null;
      expect(await endpoint.open('device', 25), same(channel.socket));
      expect(channel.openCount, 2);
    },
  );

  test(
    'factory failure propagates before the channel-open logging boundary',
    () async {
      final error = StateError('library loading failed');
      devices['device'] = _FakeDevice('device', BlueZAddressType.public);
      final records = <LogRecord>[];
      final subscription = logger.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final failingEndpoint = LinuxL2capEndpoint(
        client: client,
        devices: devices,
        logger: logger,
        channelFactory:
            ({
              required deviceId,
              required psm,
              required addressType,
              required logger,
            }) => throw error,
      );
      await expectLater(
        failingEndpoint.open('device', 25),
        throwsA(same(error)),
      );
      expect(records, isEmpty);
    },
  );

  test(
    'public openL2cap waits for BlueZ initialization before lookup',
    () async {
      final platform = QuickBlueLinux.withClient(client);
      final result = platform.openL2cap('missing', 25);
      final assertion = expectLater(
        result,
        throwsA(
          isA<QuickBlueException>().having(
            (e) => e.operation,
            'operation',
            'openL2cap',
          ),
        ),
      );
      await pumpEventQueue();
      expect(client.connectCount, 1);
      expect(client.deviceLookups, 0);
      client.connection.complete();
      await assertion;
      expect(client.deviceLookups, 2);
    },
  );

  test(
    'public openL2cap propagates initialization failure before lookup',
    () async {
      final platform = QuickBlueLinux.withClient(client);
      final error = StateError('BlueZ unavailable');
      final assertion = expectLater(
        platform.openL2cap('missing', 25),
        throwsA(same(error)),
      );
      client.connection.completeError(error);
      await assertion;
      expect(client.deviceLookups, 0);
    },
  );
}

class _FakeChannel implements L2capChannel {
  final outgoing = StreamController<Uint8List>();
  late final socket = BleL2capSocket(
    sink: outgoing.sink,
    stream: const Stream<BleL2CapSocketEvent>.empty(),
  );
  int openCount = 0;
  Object? failure;
  StackTrace? failureStack;

  @override
  Future<BleL2capSocket> open() async {
    openCount++;
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack ?? StackTrace.current);
    }
    return socket;
  }

  Future<void> dispose() async {
    // Listen before closing the single-subscription controller.
    final subscription = outgoing.stream.listen((_) {});
    await outgoing.close();
    await subscription.cancel();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDevice implements BlueZDevice {
  _FakeDevice(this.address, this.addressType);

  @override
  final String address;
  @override
  final BlueZAddressType addressType;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements BlueZClient {
  final connection = Completer<void>();
  int connectCount = 0;
  int deviceLookups = 0;
  List<BlueZDevice> currentDevices = [];

  @override
  Future<void> connect() {
    connectCount++;
    return connection.future;
  }

  @override
  List<BlueZDevice> get devices {
    deviceLookups++;
    return currentDevices;
  }

  @override
  List<BlueZAdapter> get adapters => [];
  @override
  Stream<BlueZDevice> get deviceAdded => const Stream.empty();
  @override
  Stream<BlueZDevice> get deviceRemoved => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
