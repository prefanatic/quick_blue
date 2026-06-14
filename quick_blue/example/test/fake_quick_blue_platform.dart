import 'dart:async';
import 'dart:typed_data';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

class FakeQuickBluePlatform extends QuickBluePlatform {
  final calls = <String>[];
  final _scanResultController = StreamController<BlueScanResult>.broadcast();
  final _bluetoothStateController =
      StreamController<BlueBluetoothState>.broadcast();
  ScanFilter? lastScanFilter;
  BlueBluetoothState bluetoothState = BlueBluetoothState.poweredOn;
  Completer<void>? pendingConnect;
  final pendingConnects = <String, Completer<void>>{};

  void addScanResult(BlueScanResult result) {
    _scanResultController.add(result);
  }

  void addBluetoothState(BlueBluetoothState state) {
    bluetoothState = state;
    _bluetoothStateController.add(state);
  }

  Future<void> dispose() async {
    await _scanResultController.close();
    await _bluetoothStateController.close();
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    calls.add('isBluetoothAvailable');
    return bluetoothState == BlueBluetoothState.poweredOn;
  }

  @override
  Stream<BlueBluetoothState> get bluetoothStateStream {
    calls.add('bluetoothStateStream');
    return Stream.multi((controller) {
      final subscription = _bluetoothStateController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller
        ..add(bluetoothState)
        ..onCancel = subscription.cancel;
    });
  }

  @override
  Stream<BlueScanResult> get scanResultStream => _scanResultController.stream;

  @override
  Future<void> startScan({ScanFilter scanFilter = ScanFilter.empty}) async {
    lastScanFilter = scanFilter;
    calls.add('startScan');
  }

  @override
  Future<void> stopScan() async {
    calls.add('stopScan');
  }

  @override
  Future<void> connect(String deviceId) async {
    calls.add('connect $deviceId');
    final pending =
        pendingConnects[deviceId] ??
        pendingConnect ??
        _otherPendingConnect(deviceId);
    if (pending != null) {
      await pending.future;
    }
    onConnectionChanged!(
      deviceId,
      BlueConnectionState.connected,
      BleStatus.success,
    );
  }

  @override
  Future<void> disconnect(String deviceId) async {
    calls.add('disconnect $deviceId');
    final pending = pendingConnects[deviceId];
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    onConnectionChanged!(
      deviceId,
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
  }

  Completer<void>? _otherPendingConnect(String deviceId) {
    for (final entry in pendingConnects.entries) {
      if (entry.key != deviceId && !entry.value.isCompleted) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Future<bool> isCompanionAssociationSupported() async {
    calls.add('isCompanionAssociationSupported');
    return false;
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async {
    calls.add('companionAssociate');
    return null;
  }

  @override
  Future<void> companionDisassociate(int associationId) async {
    calls.add('companionDisassociate $associationId');
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    calls.add('getCompanionAssociations');
    return const <CompanionAssociation>[];
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    calls.add('discoverServices $deviceId');
    onServiceDiscoveryComplete(deviceId);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    calls.add(
      'setNotifiable $deviceId $service $characteristic '
      '${bleInputProperty.value}',
    );
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    calls.add('readValue $deviceId $service $characteristic');
    handleCharacteristicValueChanged(
      deviceId,
      service,
      characteristic,
      Uint8List(0),
    );
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    calls.add('writeValue $deviceId $service $characteristic');
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    calls.add('requestMtu $deviceId $expectedMtu');
    return expectedMtu;
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) async {
    calls.add('openL2cap $deviceId $psm');
    return BleL2capSocket(
      sink: _NoopSink(),
      stream: const Stream<BleL2CapSocketEvent>.empty(),
    );
  }
}

class _NoopSink implements EventSink<Uint8List> {
  @override
  void add(Uint8List event) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  void close() {}
}
