import 'dart:async';
import 'dart:typed_data';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

class FakeQuickBluePlatform extends QuickBluePlatform {
  FakeQuickBluePlatform({
    Uint8List? readValueResult,
    List<BluetoothService> discoveredServices = const <BluetoothService>[],
    this.connectedDeviceIds = const <String>[],
    this.startScanError,
    List<Completer<void>> startScanCompletions = const <Completer<void>>[],
    List<Completer<void>> setNotifiableCompletions = const <Completer<void>>[],
    this.discoverServicesCompletion,
    this.discoverServicesError,
    this.setNotifiableError,
    this.readValueError,
    this.writeValueError,
    this.currentBondState = BluetoothBondState.notBonded,
    this.clearSecurityErrorsOnPair = false,
    this.securityRecoveryResult,
    this.securityRecoveryCompleter,
    this.connectsImmediately = true,
    this.disconnectsImmediately = true,
    List<Object> connectErrors = const <Object>[],
  }) : readValueResult = readValueResult ?? Uint8List(0),
       discoveredServices = discoveredServices,
       startScanCompletions = startScanCompletions,
       setNotifiableCompletions = setNotifiableCompletions,
       connectErrors = List<Object>.of(connectErrors);

  final StreamController<BlueScanResult> _scanResultController =
      StreamController<BlueScanResult>.broadcast();
  final List<String> calls = <String>[];
  final Uint8List readValueResult;
  final List<BluetoothService> discoveredServices;
  final List<String> connectedDeviceIds;
  final Object? startScanError;
  final List<Completer<void>> startScanCompletions;
  final List<Completer<void>> setNotifiableCompletions;
  final Completer<void>? discoverServicesCompletion;
  Object? discoverServicesError;
  Object? setNotifiableError;
  Object? readValueError;
  Object? writeValueError;
  BluetoothBondState currentBondState;
  final bool clearSecurityErrorsOnPair;
  final QuickBlueSecurityRecoveryResult? securityRecoveryResult;
  final Completer<void>? securityRecoveryCompleter;
  final bool connectsImmediately;
  final bool disconnectsImmediately;
  final List<Object> connectErrors;
  ScanFilter? lastScanFilter;
  ScanOptions? lastScanOptions;
  int _startScanCallCount = 0;
  int _setNotifiableCallCount = 0;

  void addScanResult(
    String deviceId, {
    int rssi = -40,
    Map<String, Uint8List> serviceData = const <String, Uint8List>{},
  }) {
    _scanResultController.add(
      BlueScanResult(
        name: 'Device $deviceId',
        deviceId: deviceId,
        rssi: rssi,
        serviceData: serviceData,
      ),
    );
  }

  void addBondStateChange(
    String deviceId,
    BluetoothBondState state, {
    required BluetoothBondState previousState,
  }) {
    if (deviceId == 'device-a') {
      currentBondState = state;
    }
    handleBondStateChanged(deviceId, state, previousState);
  }

  Future<void> dispose() {
    return _scanResultController.close();
  }

  @override
  Stream<BlueScanResult> get scanResultStream => _scanResultController.stream;

  @override
  Future<bool> isBluetoothAvailable() async => true;

  @override
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) async {
    lastScanFilter = scanFilter;
    lastScanOptions = scanOptions;
    calls.add('startScan');
    final error = startScanError;
    if (error != null) {
      if (error is Error) {
        throw error;
      }
      throw StateError(error.toString());
    }
    if (_startScanCallCount < startScanCompletions.length) {
      await startScanCompletions[_startScanCallCount++].future;
    }
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
    if (connectErrors.isNotEmpty) {
      throw connectErrors.removeAt(0);
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
    if (clearSecurityErrorsOnPair) {
      readValueError = null;
      writeValueError = null;
      setNotifiableError = null;
    }
  }

  @override
  Future<QuickBlueSecurityRecoveryResult> performSecurityRecovery(
    String deviceId,
    QuickBlueSecurityException error,
  ) async {
    final result = securityRecoveryResult;
    if (result == null) {
      return super.performSecurityRecovery(deviceId, error);
    }
    calls.add('performSecurityRecovery $deviceId ${error.reason.name}');
    await securityRecoveryCompleter?.future;
    return result;
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
    final error = discoverServicesError;
    if (error != null) {
      throw error;
    }
    await discoverServicesCompletion?.future;
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
      'setNotifiable $deviceId $service $characteristic ${bleInputProperty.value}',
    );
    final error = setNotifiableError;
    if (error != null) {
      throw error;
    }
    if (_setNotifiableCallCount < setNotifiableCompletions.length) {
      await setNotifiableCompletions[_setNotifiableCallCount++].future;
    }
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    calls.add('readValue $deviceId $service $characteristic');
    final error = readValueError;
    if (error != null) {
      throw error;
    }
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
    final error = writeValueError;
    if (error != null) {
      throw error;
    }
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
      sink: NoopSink(),
      stream: const Stream<BleL2CapSocketEvent>.empty(),
    );
  }
}

class FakeBluetoothStatePlatform extends FakeQuickBluePlatform {
  final _bluetoothStateController =
      StreamController<BlueBluetoothState>.broadcast();
  var bluetoothState = BlueBluetoothState.poweredOn;
  var bluetoothStateEventListenCount = 0;
  var bluetoothStateEventCancelCount = 0;

  void addBluetoothState(BlueBluetoothState state) {
    bluetoothState = state;
    _bluetoothStateController.add(state);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await _bluetoothStateController.close();
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    return bluetoothState == BlueBluetoothState.poweredOn;
  }

  @override
  Stream<BlueBluetoothState> get bluetoothStateEvents {
    return Stream.multi((controller) {
      bluetoothStateEventListenCount += 1;
      final subscription = _bluetoothStateController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller
        ..add(bluetoothState)
        ..onCancel = () async {
          bluetoothStateEventCancelCount += 1;
          await subscription.cancel();
        };
    });
  }
}

class NoopSink implements EventSink<Uint8List> {
  @override
  void add(Uint8List event) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  void close() {}
}
