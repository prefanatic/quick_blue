import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:quick_blue_linux/quick_blue_linux.dart';

String uuid(String short) =>
    '0000${short.toLowerCase()}-0000-1000-8000-00805f9b34fb';

/// Linux-local fake dependencies: no system bus, adapter, or native BLE calls.
class AdapterFixture {
  AdapterFixture() {
    a.gattServices = [
      ContractService('180f', battery),
      ContractService('180a', info),
    ];
    b.gattServices = [ContractService('180f', other)];
    client = ContractClient([a, b]);
    platform = QuickBlueLinux.withClient(client, connectionLease: lease);
  }

  final a = ContractDevice('AA:BB:CC:DD:EE:01');
  final b = ContractDevice('AA:BB:CC:DD:EE:02');
  final battery = ContractCharacteristic();
  final info = ContractCharacteristic();
  final other = ContractCharacteristic();
  final lease = ContractLease();
  late final ContractClient client;
  late final QuickBlueLinux platform;

  Future<void> close() async {
    for (final device in [a, b]) {
      if (lease.owned.contains(device.address)) {
        await platform.disconnect(device.address);
      }
      await device.properties.close();
    }
    for (final characteristic in [battery, info, other]) {
      await characteristic.properties.close();
    }
  }
}

class ContractDevice implements BlueZDevice {
  ContractDevice(this.address);
  @override
  final String address;
  @override
  bool connected = true;
  @override
  bool servicesResolved = true;
  @override
  bool paired = false;
  int pairs = 0;
  int disconnects = 0;
  @override
  List<BlueZUUID> get uuids => gattServices.map((s) => s.uuid).toList();
  @override
  List<BlueZGattService> gattServices = [];
  final properties = StreamController<List<String>>.broadcast();
  @override
  Stream<List<String>> get propertiesChanged => properties.stream;
  @override
  Future<void> pair() async {
    pairs++;
    paired = true;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    connected = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ContractService implements BlueZGattService {
  ContractService(String short, BlueZGattCharacteristic characteristic)
    : uuid = BlueZUUID.fromString(AdapterUuid.canonical(short)),
      characteristics = [characteristic];
  @override
  final BlueZUUID uuid;
  @override
  final List<BlueZGattCharacteristic> characteristics;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdapterUuid {
  static String canonical(String short) => uuid(short);
}

class ContractCharacteristic implements BlueZGattCharacteristic {
  @override
  final uuid = BlueZUUID.fromString(AdapterUuid.canonical('2a19'));
  @override
  Set<BlueZGattCharacteristicFlag> flags = {
    BlueZGattCharacteristicFlag.read,
    BlueZGattCharacteristicFlag.write,
    BlueZGattCharacteristicFlag.writeWithoutResponse,
    BlueZGattCharacteristicFlag.notify,
    BlueZGattCharacteristicFlag.indicate,
  };
  @override
  bool notifying = false;
  @override
  List<int> value = [0];
  final properties = StreamController<List<String>>.broadcast();
  final writes = <(List<int>, BlueZGattCharacteristicWriteType?)>[];
  Completer<List<int>>? pendingRead;
  Completer<void>? pendingStart;
  final readEntered = Completer<void>();
  final startEntered = Completer<void>();
  Object? error;
  int reads = 0;
  int starts = 0;
  int stops = 0;
  @override
  Stream<List<String>> get propertiesChanged => properties.stream;
  void checkError() {
    final e = error;
    if (e != null) throw e;
  }

  void emit(List<int> bytes) {
    value = bytes;
    properties.add(['Value']);
  }

  @override
  Future<List<int>> readValue({int? offset}) async {
    reads++;
    if (!readEntered.isCompleted) readEntered.complete();
    checkError();
    return pendingRead == null ? [1, 2] : await pendingRead!.future;
  }

  @override
  Future<void> writeValue(
    Iterable<int> data, {
    int? offset,
    BlueZGattCharacteristicWriteType? type,
    bool? prepareAuthorize,
  }) async {
    checkError();
    writes.add((data.toList(), type));
  }

  @override
  Future<void> startNotify() async {
    starts++;
    if (!startEntered.isCompleted) startEntered.complete();
    checkError();
    await pendingStart?.future;
    notifying = true;
  }

  @override
  Future<void> stopNotify() async {
    stops++;
    checkError();
    notifying = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ContractClient implements BlueZClient {
  ContractClient(this.devices);
  int connects = 0;
  @override
  final List<BlueZDevice> devices;
  @override
  Future<void> connect() async {
    connects++;
  }

  @override
  List<BlueZAdapter> get adapters => [];
  // Finite streams intentionally avoid pretending the plugin has a dispose API.
  @override
  Stream<BlueZDevice> get deviceAdded => const Stream.empty();
  @override
  Stream<BlueZDevice> get deviceRemoved => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ContractLease implements QuickBlueLinuxConnectionLease {
  final owned = <String>{};
  final attaches = <String>[];
  final detaches = <String>[];
  @override
  Future<void> attach(String deviceId) async {
    attaches.add(deviceId);
    owned.add(deviceId);
  }

  @override
  Future<void> detach(
    String deviceId,
    Future<void> Function() onLastClient,
  ) async {
    detaches.add(deviceId);
    owned.remove(deviceId);
    await onLastClient();
  }
}
