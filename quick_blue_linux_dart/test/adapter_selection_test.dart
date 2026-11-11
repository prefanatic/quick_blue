import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  test(
    'same remote address on foreign adapter cannot overwrite selection',
    () async {
      final first = Adapter('02:00:00:00:00:01');
      final second = Adapter('02:00:00:00:00:02');
      const remote = '02:00:00:00:00:03';
      final selected = Device(first, remote);
      final foreign = Device(second, remote);
      final client = Client([first, second])..deviceList = [selected, foreign];
      addTearDown(client.removed.close);
      final lease = Lease();
      final platform = QuickBlueLinux.withClient(
        client,
        adapterAddress: first.address,
        connectionLease: lease,
      );
      expect((await platform.connectedDevices()).map((d) => d.id), [remote]);
      expect((await platform.connectedDevices()).map((d) => d.id), [remote]);
      expect(selected.connects, 0);
      expect(foreign.connects, 0);
      selected.connected = false;
      await platform.connect(remote).timeout(const Duration(seconds: 1));
      expect(selected.connects, 1);
      expect(foreign.connects, 0);
      client.removed.add(foreign);
      await pumpEventQueue();
      expect((await platform.connectedDevices()).map((d) => d.id), [remote]);
      expect(selected.connected, isTrue);
      expect(selected.disconnects, 0);
      expect(foreign.disconnects, 0);
      expect(lease.attaches, ['${first.address}/$remote']);
      expect(lease.detaches, isEmpty);
      await platform.close();
    },
  );
  test(
    'explicit adapter scopes connected lookup and rejects foreign IO',
    () async {
      final first = Adapter('02:00:00:00:00:01');
      final second = Adapter('02:00:00:00:00:02');
      final client = Client([first, second])
        ..deviceList = [Device(first), Device(second)];
      final platform = QuickBlueLinux.withClient(
        client,
        adapterAddress: first.address,
      );
      expect((await platform.connectedDevices()).map((d) => d.id), [
        first.address,
      ]);
      await expectLater(
        platform.connect(second.address),
        throwsA(
          isA<QuickBlueException>().having(
            (e) => e.code,
            'code',
            QuickBlueErrorCode.notFound,
          ),
        ),
      );
      expect(client.deviceList.last.connects, 0);
      await expectLater(
        platform.openL2cap(second.address, 129),
        throwsA(
          isA<QuickBlueException>().having(
            (e) => e.code,
            'code',
            QuickBlueErrorCode.notFound,
          ),
        ),
      );
      await platform.close();
    },
  );

  test(
    'default selects first powered adapter; explicit selection never falls back',
    () async {
      final first = Adapter('02:00:00:00:00:01', powered: false);
      final second = Adapter('02:00:00:00:00:02');
      final client = Client([first, second]);
      final defaultPlatform = QuickBlueLinux.withClient(client);
      await defaultPlatform.startScan();
      expect(second.calls, ['filter', 'start']);
      await defaultPlatform.stopScan();
      expect(second.calls.last, 'stop');
      final selected = QuickBlueLinux.withClient(
        client,
        adapterAddress: first.address,
      );
      expect(await selected.isBluetoothAvailable(), isFalse);
      await expectLater(
        selected.startScan(),
        throwsA(isA<QuickBlueException>()),
      );
      expect(first.calls, isEmpty);
      first.powered = true;
      await selected.startScan();
      expect(first.calls, ['filter', 'start']);
      first.powered = false;
      await selected.isBluetoothAvailable();
      await selected.stopScan();
      expect(first.calls.last, 'stop');
      expect(second.calls, ['filter', 'start', 'stop']);
      await selected.close();
      await defaultPlatform.close();
    },
  );

  test(
    'list snapshots and missing/removed adapter do not select another',
    () async {
      final first = Adapter('02:00:00:00:00:01');
      final second = Adapter('02:00:00:00:00:02');
      final client = Client([first, second]);
      final platform = QuickBlueLinux.withClient(
        client,
        adapterAddress: first.address,
      );
      final adapters = await platform.adapters();
      expect(adapters.map((a) => a.address), [first.address, second.address]);
      expect(adapters.first.powered, isTrue);
      client.adapters.remove(first);
      expect(await platform.isBluetoothAvailable(), isFalse);
      await expectLater(
        platform.startScan(),
        throwsA(isA<QuickBlueException>()),
      );
      expect(second.calls, isEmpty);
      expect(adapters.length, 2);
      expect(() => adapters.clear(), throwsUnsupportedError);
      await platform.close();
    },
  );
}

class Client implements BlueZClient {
  Client(this.adapters);
  @override
  final List<BlueZAdapter> adapters;
  @override
  Future<void> connect() async {}
  @override
  Future<void> close() async {}
  List<Device> deviceList = [];
  final removed = StreamController<BlueZDevice>.broadcast();
  @override
  List<BlueZDevice> get devices => deviceList;
  @override
  Stream<BlueZDevice> get deviceAdded => const Stream.empty();
  @override
  Stream<BlueZDevice> get deviceRemoved => removed.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Device implements BlueZDevice {
  Device(this.adapter, [this.remoteAddress]);
  final String? remoteAddress;
  @override
  final BlueZAdapter adapter;
  @override
  String get address => remoteAddress ?? adapter.address;
  @override
  bool connected = true;
  @override
  bool get servicesResolved => true;
  @override
  List<BlueZGattService> get gattServices => [];
  @override
  Stream<List<String>> get propertiesChanged => const Stream.empty();
  int connects = 0;
  int disconnects = 0;
  @override
  Future<void> connect() async {
    connects++;
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    connected = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Lease implements QuickBlueLinuxConnectionLease {
  final attaches = <String>[];
  final detaches = <String>[];
  @override
  Future<void> attach(String deviceId) async {
    attaches.add(deviceId);
  }

  @override
  Future<void> detach(
    String deviceId,
    Future<void> Function() onLastClient,
  ) async {
    detaches.add(deviceId);
    await onLastClient();
  }
}

class Adapter implements BlueZAdapter {
  Adapter(this.address, {this.powered = true});
  @override
  final String address;
  @override
  bool powered;
  final calls = <String>[];
  @override
  Future<void> startDiscovery() async {
    calls.add('start');
  }

  @override
  Future<void> stopDiscovery() async {
    calls.add('stop');
  }

  @override
  Future<void> setDiscoveryFilter({
    List<String>? uuids,
    int? rssi,
    int? pathloss,
    String? transport,
    bool? duplicateData,
    bool? discoverable,
    String? pattern,
  }) async {
    calls.add('filter');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
