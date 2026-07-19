import 'dart:async';
import 'dart:typed_data';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

class FakeQuickBluePlatform extends QuickBluePlatform {
  final List<String> calls = <String>[];
  var isAvailable = true;
  var connectsImmediately = true;
  var disconnectsImmediately = true;
  var emitInitialBluetoothState = false;
  var bluetoothState = BlueBluetoothState.poweredOn;
  var currentBondState = BluetoothBondState.notBonded;
  var readValueResult = Uint8List(0);
  var discoveredServices = <BluetoothService>[];
  var connectedDeviceIds = <String>[];
  ScanFilter? lastScanFilter;
  ScanOptions? lastScanOptions;
  Completer<void>? nextSetNotifiable;
  Completer<void>? pendingConnect;
  final pendingConnects = <String, Completer<void>>{};
  CompanionAssociation? companionAssociation;
  List<CompanionAssociation> companionAssociations =
      const <CompanionAssociation>[];
  CompanionAssociationRequest? lastCompanionAssociateRequest;
  AppleAccessory? selectedAppleAccessory;
  List<AppleAccessory> appleAccessories = const <AppleAccessory>[];
  List<AppleAccessoryPickerItem>? lastAppleAccessoryPickerItems;
  final _scanResultController = StreamController<BlueScanResult>.broadcast();
  final _bluetoothStateController =
      StreamController<BlueBluetoothState>.broadcast();

  Future<void> dispose() async {
    await _scanResultController.close();
    await _bluetoothStateController.close();
  }

  void addScanResult(Object result) {
    _scanResultController.add(switch (result) {
      final BlueScanResult scanResult => scanResult,
      final String deviceId => BlueScanResult(
        name: 'Device $deviceId',
        deviceId: deviceId,
        rssi: -40,
      ),
      _ => throw ArgumentError.value(result, 'result'),
    });
  }

  void addBluetoothState(BlueBluetoothState state) {
    bluetoothState = state;
    _bluetoothStateController.add(state);
  }

  void addBondStateChange(
    String deviceId,
    BluetoothBondState state, {
    required BluetoothBondState previousState,
  }) {
    currentBondState = state;
    handleBondStateChanged(deviceId, state, previousState);
  }

  @override
  Future<void> configure({bool maintainState = false}) async {
    calls.add('configure $maintainState');
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    calls.add('isBluetoothAvailable');
    return isAvailable && bluetoothState == BlueBluetoothState.poweredOn;
  }

  @override
  Stream<BlueBluetoothState> get bluetoothStateEvents {
    calls.add('bluetoothStateStream');
    if (!emitInitialBluetoothState) {
      return _bluetoothStateController.stream;
    }
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
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) async {
    lastScanFilter = scanFilter;
    lastScanOptions = scanOptions;
    calls.add('startScan');
  }

  @override
  Future<void> stopScan() async {
    calls.add('stopScan');
  }

  @override
  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  }) async {
    calls.add('connectedDevices $serviceUuids');
    return connectedDeviceIds.map(device).toList(growable: false);
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
    if (connectsImmediately) {
      onConnectionChanged!(
        deviceId,
        BlueConnectionState.connected,
        BleStatus.success,
      );
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    calls.add('disconnect $deviceId');
    final pending = pendingConnects[deviceId];
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    if (disconnectsImmediately) {
      onConnectionChanged!(
        deviceId,
        BlueConnectionState.disconnected,
        BleStatus.success,
      );
    }
  }

  @override
  Future<BluetoothBondState> bondState(String deviceId) async {
    calls.add('bondState $deviceId');
    return currentBondState;
  }

  @override
  Future<void> pair(String deviceId) async {
    calls.add('pair $deviceId');
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
    return true;
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async {
    lastCompanionAssociateRequest = request;
    final filter = request.filters.isEmpty ? null : request.filters.first;
    calls.add(
      'companionAssociate ${filter?.deviceId} '
      '${filter?.serviceUuids ?? <String>[]}',
    );
    return companionAssociation;
  }

  @override
  Future<void> companionDisassociate(int associationId) async {
    calls.add('companionDisassociate $associationId');
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    calls.add('getCompanionAssociations');
    return companionAssociations;
  }

  @override
  Future<bool> isAppleAccessorySetupSupported() async {
    calls.add('isAppleAccessorySetupSupported');
    return true;
  }

  @override
  Future<AppleAccessory?> showAppleAccessoryPicker(
    List<AppleAccessoryPickerItem> items,
  ) async {
    lastAppleAccessoryPickerItems = items;
    calls.add('showAppleAccessoryPicker');
    return selectedAppleAccessory;
  }

  @override
  Future<List<AppleAccessory>> getAppleAccessories() async {
    calls.add('getAppleAccessories');
    return appleAccessories;
  }

  @override
  Future<void> removeAppleAccessory(String deviceId) async {
    calls.add('removeAppleAccessory $deviceId');
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    calls.add('discoverServices $deviceId');
    for (final service in discoveredServices) {
      handleServiceDiscovered(
        deviceId,
        service.uuid,
        service.characteristicDetails,
      );
    }
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
    final completer = nextSetNotifiable;
    if (completer != null) {
      nextSetNotifiable = null;
      await completer.future;
    }
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
      readValueResult,
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
    calls.add(
      'writeValue $deviceId $service $characteristic '
      '${bleOutputProperty.value} ${value.toList()}',
    );
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
