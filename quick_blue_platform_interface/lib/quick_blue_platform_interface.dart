library quick_blue_platform_interface;

import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models.dart';

export 'models.dart';

typedef OnConnectionChanged =
    void Function(String deviceId, BlueConnectionState state, BleStatus status);

typedef OnServiceDiscovered =
    void Function(
      String deviceId,
      String serviceId,
      List<String> characteristicIds,
    );

typedef OnValueChanged =
    void Function(String deviceId, String characteristicId, Uint8List value);

typedef OnServiceDiscoveryComplete = void Function(String deviceId);

abstract class QuickBluePlatform extends PlatformInterface {
  QuickBluePlatform() : super(token: _token);

  static final Object _token = Object();

  static QuickBluePlatform _instance = _UnimplementedQuickBluePlatform();

  static QuickBluePlatform get instance => _instance;

  static set instance(QuickBluePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns whether Bluetooth is currently powered on and usable.
  Future<bool> isBluetoothAvailable();

  /// Emits the current Bluetooth state first, then emits later state changes
  /// when the platform supports live state updates.
  ///
  /// Platforms without live state monitoring may emit only the current
  /// availability snapshot.
  Stream<BlueBluetoothState> get bluetoothStateStream async* {
    yield await isBluetoothAvailable()
        ? BlueBluetoothState.poweredOn
        : BlueBluetoothState.poweredOff;
  }

  Future<void> startScan({ScanFilter scanFilter = ScanFilter.empty});

  Future<void> stopScan();

  Stream<BlueScanResult> get scanResultStream;

  ScanFilter? _activeScanFilter;
  var _activeScanListeners = 0;
  var _activeScanStarted = false;
  Future<void> _scanLifecycle = Future<void>.value();

  Stream<BlueScanResult> scanResults({
    ScanFilter scanFilter = ScanFilter.empty,
  }) async* {
    final filter = _copyScanFilter(scanFilter);

    await _acquireScan(filter);
    try {
      yield* scanResultStream;
    } finally {
      await _releaseScan();
    }
  }

  Future<void> _acquireScan(ScanFilter filter) {
    return _queueScanLifecycle(() async {
      final activeFilter = _activeScanFilter;
      if (_activeScanListeners == 0) {
        _activeScanFilter = filter;
        try {
          await startScan(scanFilter: filter);
          _activeScanStarted = true;
        } catch (_) {
          _activeScanFilter = null;
          rethrow;
        }
      } else if (activeFilter == null || activeFilter != filter) {
        throw StateError(
          'Cannot start scanning with a different ScanFilter while another '
          'scanResults stream is active.',
        );
      }

      _activeScanListeners++;
    });
  }

  ScanFilter _copyScanFilter(ScanFilter scanFilter) {
    return ScanFilter(
      serviceUuids: scanFilter.serviceUuids,
      manufacturerData: scanFilter.manufacturerData,
    );
  }

  Future<void> _releaseScan() {
    return _queueScanLifecycle(() async {
      if (_activeScanListeners == 0) {
        return;
      }

      _activeScanListeners--;
      if (_activeScanListeners != 0) {
        return;
      }

      _activeScanFilter = null;
      if (_activeScanStarted) {
        _activeScanStarted = false;
        await stopScan();
      }
    });
  }

  Future<void> _queueScanLifecycle(Future<void> Function() action) {
    final next = _scanLifecycle.then((_) => action());
    _scanLifecycle = next.catchError((Object _) {});
    return next;
  }

  Stream<BluetoothDevice> scan({ScanFilter scanFilter = ScanFilter.empty}) {
    return scanResults(
      scanFilter: scanFilter,
    ).map((result) => device(result.deviceId));
  }

  Stream<BluetoothDevice> get bluetoothDeviceStream {
    return scan();
  }

  BluetoothDevice device(String deviceId) {
    return BluetoothDevice._(deviceId: deviceId, platform: this);
  }

  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  });

  Future<void> connect(String deviceId);

  Future<void> disconnect(String deviceId);

  Future<bool> isCompanionAssociationSupported();

  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  );

  Future<void> companionDisassociate(int associationId);

  Future<List<CompanionAssociation>> getCompanionAssociations();

  final StreamController<BluetoothConnectionStateChange>
  _connectionStateController =
      StreamController<BluetoothConnectionStateChange>.broadcast();

  Stream<BluetoothConnectionStateChange> get connectionStateStream {
    return _connectionStateController.stream;
  }

  OnConnectionChanged? _onConnectionChanged;

  OnConnectionChanged? get onConnectionChanged => _handleConnectionChanged;

  set onConnectionChanged(OnConnectionChanged? handler) {
    _onConnectionChanged = handler;
  }

  Future<void> discoverServices(String deviceId);

  final StreamController<BluetoothService> _serviceDiscoveryController =
      StreamController<BluetoothService>.broadcast();
  final StreamController<String> _serviceDiscoveryCompleteController =
      StreamController<String>.broadcast();
  final _serviceDiscoveryEventController =
      StreamController<_ServiceDiscoveryEvent>.broadcast();

  Stream<BluetoothService> get serviceDiscoveryStream {
    return _serviceDiscoveryController.stream;
  }

  Stream<String> get serviceDiscoveryCompleteStream {
    return _serviceDiscoveryCompleteController.stream;
  }

  OnServiceDiscovered? _onServiceDiscovered;

  OnServiceDiscovered? get onServiceDiscovered {
    return (deviceId, serviceId, characteristicIds) {
      _handleServiceDiscovered(deviceId, serviceId, characteristicIds, null);
    };
  }

  set onServiceDiscovered(OnServiceDiscovered? handler) {
    _onServiceDiscovered = handler;
  }

  OnServiceDiscoveryComplete get onServiceDiscoveryComplete {
    return _handleServiceDiscoveryComplete;
  }

  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  );

  final StreamController<BluetoothCharacteristicValue>
  _characteristicValueController =
      StreamController<BluetoothCharacteristicValue>.broadcast();

  Stream<BluetoothCharacteristicValue> get characteristicValueStream {
    return _characteristicValueController.stream;
  }

  OnValueChanged? _onValueChanged;

  OnValueChanged? get onValueChanged {
    return (deviceId, characteristicId, value) {
      _handleValueChanged(deviceId, '', characteristicId, value);
    };
  }

  set onValueChanged(OnValueChanged? handler) {
    _onValueChanged = handler;
  }

  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  );

  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  );

  Future<int> requestMtu(String deviceId, int expectedMtu);

  Future<BleL2capSocket> openL2cap(String deviceId, int psm);

  void _handleConnectionChanged(
    String deviceId,
    BlueConnectionState state,
    BleStatus status,
  ) {
    _connectionStateController.add(
      BluetoothConnectionStateChange(
        deviceId: deviceId,
        state: state,
        status: status,
      ),
    );
    _onConnectionChanged?.call(deviceId, state, status);
  }

  void _handleServiceDiscovered(
    String deviceId,
    String serviceId,
    List<String> characteristicIds,
    List<BluetoothCharacteristicInfo>? characteristicDetails,
  ) {
    final details =
        characteristicDetails ??
        characteristicIds
            .map((uuid) => BluetoothCharacteristicInfo(uuid: uuid))
            .toList(growable: false);
    final service = BluetoothService(
      deviceId: deviceId,
      uuid: serviceId,
      characteristics: characteristicIds,
      characteristicDetails: details,
    );

    _serviceDiscoveryEventController.add(
      _ServiceDiscoveredEvent(deviceId, service),
    );
    _serviceDiscoveryController.add(service);
    _onServiceDiscovered?.call(deviceId, serviceId, characteristicIds);
  }

  void _handleServiceDiscoveryComplete(String deviceId) {
    _serviceDiscoveryEventController.add(
      _ServiceDiscoveryCompleteEvent(deviceId),
    );
    _serviceDiscoveryCompleteController.add(deviceId);
  }

  Stream<_ServiceDiscoveryEvent> _serviceDiscoveryEvents(String deviceId) {
    return _serviceDiscoveryEventController.stream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  void _handleValueChanged(
    String deviceId,
    String serviceId,
    String characteristicId,
    Uint8List value,
  ) {
    _characteristicValueController.add(
      BluetoothCharacteristicValue(
        deviceId: deviceId,
        serviceId: serviceId,
        characteristicId: characteristicId,
        value: value,
      ),
    );
    _onValueChanged?.call(deviceId, characteristicId, value);
  }

  void handleServiceDiscovered(
    String deviceId,
    String serviceId,
    List<BluetoothCharacteristicInfo> characteristics,
  ) {
    _handleServiceDiscovered(
      deviceId,
      serviceId,
      characteristics
          .map((characteristic) => characteristic.uuid)
          .toList(growable: false),
      characteristics,
    );
  }

  void handleCharacteristicValueChanged(
    String deviceId,
    String serviceId,
    String characteristicId,
    Uint8List value,
  ) {
    _handleValueChanged(deviceId, serviceId, characteristicId, value);
  }
}

class _UnimplementedQuickBluePlatform extends QuickBluePlatform {
  static UnsupportedError _unsupported() {
    return UnsupportedError(
      'No QuickBlue platform implementation has been registered.',
    );
  }

  @override
  Future<bool> isBluetoothAvailable() => Future<bool>.error(_unsupported());

  @override
  Future<void> startScan({ScanFilter scanFilter = ScanFilter.empty}) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<void> stopScan() => Future<void>.error(_unsupported());

  @override
  Stream<BlueScanResult> get scanResultStream {
    return Stream<BlueScanResult>.error(_unsupported());
  }

  @override
  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  }) {
    return Future<List<BluetoothDevice>>.error(_unsupported());
  }

  @override
  Future<void> connect(String deviceId) => Future<void>.error(_unsupported());

  @override
  Future<void> disconnect(String deviceId) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<bool> isCompanionAssociationSupported() {
    return Future<bool>.error(_unsupported());
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) {
    return Future<CompanionAssociation?>.error(_unsupported());
  }

  @override
  Future<void> companionDisassociate(int associationId) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() {
    return Future<List<CompanionAssociation>>.error(_unsupported());
  }

  @override
  Future<void> discoverServices(String deviceId) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    return Future<int>.error(_unsupported());
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) {
    return Future<BleL2capSocket>.error(_unsupported());
  }
}

abstract class _ServiceDiscoveryEvent {
  const _ServiceDiscoveryEvent(this.deviceId);

  final String deviceId;
}

class _ServiceDiscoveredEvent extends _ServiceDiscoveryEvent {
  const _ServiceDiscoveredEvent(super.deviceId, this.service);

  final BluetoothService service;
}

class _ServiceDiscoveryCompleteEvent extends _ServiceDiscoveryEvent {
  const _ServiceDiscoveryCompleteEvent(super.deviceId);
}

class BluetoothDevice {
  BluetoothDevice._({
    required this.deviceId,
    required QuickBluePlatform platform,
  }) : _platform = platform;

  final String deviceId;
  final QuickBluePlatform _platform;

  String get id => deviceId;

  Stream<BluetoothConnectionStateChange> get connectionStateStream {
    return _platform.connectionStateStream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  Stream<BluetoothService> get serviceDiscoveryStream {
    return _platform.serviceDiscoveryStream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  Stream<BluetoothCharacteristicValue> get characteristicValueStream {
    return _platform.characteristicValueStream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  Future<void> connect() async {
    await _runConnectionOperation(
      targetState: BlueConnectionState.connected,
      failureMessage: 'Failed to connect to Bluetooth device $deviceId.',
      operation: () => _platform.connect(deviceId),
    );
  }

  Future<void> disconnect() async {
    await _runConnectionOperation(
      targetState: BlueConnectionState.disconnected,
      failureMessage: 'Failed to disconnect Bluetooth device $deviceId.',
      operation: () => _platform.disconnect(deviceId),
    );
  }

  Future<void> _runConnectionOperation({
    required BlueConnectionState targetState,
    required String failureMessage,
    required Future<void> Function() operation,
  }) async {
    final stateEvents = StreamQueue(
      connectionStateStream.where(
        (event) =>
            event.status == BleStatus.failure || event.state == targetState,
      ),
    );

    try {
      await operation();
      final state = await stateEvents.next;
      if (state.status == BleStatus.failure) {
        throw StateError(failureMessage);
      }
    } finally {
      await stateEvents.cancel();
    }
  }

  Future<List<BluetoothService>> discoverServices() async {
    final services = <BluetoothService>[];
    final events = StreamQueue<_ServiceDiscoveryEvent>(
      _platform._serviceDiscoveryEvents(deviceId),
    );

    try {
      await _platform.discoverServices(deviceId);

      while (await events.hasNext) {
        switch (await events.next) {
          case _ServiceDiscoveredEvent(:final service):
            services.add(service);
          case _ServiceDiscoveryCompleteEvent():
            return List<BluetoothService>.unmodifiable(services);
        }
      }

      throw StateError(
        'Service discovery ended before completion for Bluetooth device '
        '$deviceId.',
      );
    } finally {
      await events.cancel();
    }
  }

  Future<BluetoothGatt> discoverGatt() async {
    return BluetoothGatt._(device: this, services: await discoverServices());
  }

  BluetoothCharacteristic characteristic(
    String service,
    String characteristic,
  ) {
    return BluetoothCharacteristic._(
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      platform: _platform,
    );
  }

  Future<void> setNotifiable(
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    return _platform.setNotifiable(
      deviceId,
      service,
      characteristic,
      bleInputProperty,
    );
  }

  Future<Uint8List> readValue(String service, String characteristic) async {
    return this.characteristic(service, characteristic).read();
  }

  Future<void> writeValue(
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    return this
        .characteristic(service, characteristic)
        .write(value, bleOutputProperty);
  }

  Future<int> requestMtu(int expectedMtu) {
    return _platform.requestMtu(deviceId, expectedMtu);
  }

  Future<BleL2capSocket> openL2cap(int psm) {
    return _platform.openL2cap(deviceId, psm);
  }
}

class BluetoothGatt {
  BluetoothGatt._({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  }) : _device = device,
       services = List<BluetoothService>.unmodifiable(services);

  final BluetoothDevice _device;
  final List<BluetoothService> services;

  String get deviceId => _device.deviceId;

  BluetoothCharacteristic characteristic(
    String characteristic, {
    String? service,
  }) {
    final resolved = _resolveCharacteristic(characteristic, service: service);
    return _device.characteristic(
      resolved.service.uuid,
      resolved.characteristic.uuid,
    );
  }

  BluetoothCharacteristicInfo characteristicInfo(
    String characteristic, {
    String? service,
  }) {
    return _resolveCharacteristic(
      characteristic,
      service: service,
    ).characteristic;
  }

  _BluetoothGattCharacteristic _resolveCharacteristic(
    String characteristic, {
    String? service,
  }) {
    final matches = <_BluetoothGattCharacteristic>[];
    for (final discoveredService in services) {
      if (service != null &&
          !_matchesBluetoothUuid(discoveredService.uuid, service)) {
        continue;
      }
      for (final discoveredCharacteristic
          in discoveredService.characteristicDetails) {
        if (_matchesBluetoothUuid(
          discoveredCharacteristic.uuid,
          characteristic,
        )) {
          matches.add(
            _BluetoothGattCharacteristic(
              service: discoveredService,
              characteristic: discoveredCharacteristic,
            ),
          );
        }
      }
    }

    if (matches.isEmpty) {
      final serviceContext = service == null ? '' : ' under service $service';
      throw StateError(
        'Characteristic $characteristic not found$serviceContext on '
        'Bluetooth device $deviceId.',
      );
    }
    if (matches.length > 1) {
      final services = matches
          .map((match) => match.service.uuid)
          .toSet()
          .join(', ');
      throw StateError(
        'Characteristic $characteristic was found under multiple services on '
        'Bluetooth device $deviceId: $services. Specify a service UUID.',
      );
    }

    return matches.single;
  }
}

class _BluetoothGattCharacteristic {
  _BluetoothGattCharacteristic({
    required this.service,
    required this.characteristic,
  });

  final BluetoothService service;
  final BluetoothCharacteristicInfo characteristic;
}

class BluetoothCharacteristic {
  BluetoothCharacteristic._({
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
    required QuickBluePlatform platform,
  }) : _platform = platform;

  final String deviceId;
  final String serviceId;
  final String characteristicId;
  final QuickBluePlatform _platform;

  Stream<Uint8List> get valueStream {
    return _platform.characteristicValueStream
        .where(
          (event) =>
              event.deviceId == deviceId &&
              (event.serviceId.isEmpty ||
                  _matchesBluetoothUuid(event.serviceId, serviceId)) &&
              _matchesBluetoothUuid(event.characteristicId, characteristicId),
        )
        .map((event) => event.value);
  }

  Stream<Uint8List> notifications({
    BleInputProperty bleInputProperty = BleInputProperty.notification,
  }) {
    late StreamSubscription<Uint8List> valueSubscription;
    late Future<void> setUpNotification;
    var valueSubscriptionCanceled = false;
    var enabled = false;
    final controller = StreamController<Uint8List>();

    Future<void> cancelValueSubscription() async {
      if (valueSubscriptionCanceled) {
        return;
      }
      valueSubscriptionCanceled = true;
      await valueSubscription.cancel();
    }

    controller.onListen = () {
      valueSubscription = valueStream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      valueSubscription.pause();
      setUpNotification = () async {
        try {
          await _platform.setNotifiable(
            deviceId,
            serviceId,
            characteristicId,
            bleInputProperty,
          );
          enabled = true;
          valueSubscription.resume();
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await cancelValueSubscription();
        }
      }();
    };

    controller.onCancel = () async {
      await setUpNotification;
      await cancelValueSubscription();
      if (enabled) {
        await _platform.setNotifiable(
          deviceId,
          serviceId,
          characteristicId,
          BleInputProperty.disabled,
        );
      }
    };

    return controller.stream;
  }

  Future<Uint8List> read() async {
    final values = StreamQueue(valueStream);

    try {
      await _platform.readValue(deviceId, serviceId, characteristicId);
      return await values.next;
    } finally {
      await values.cancel();
    }
  }

  Future<void> write(Uint8List value, BleOutputProperty bleOutputProperty) {
    return _platform.writeValue(
      deviceId,
      serviceId,
      characteristicId,
      value,
      bleOutputProperty,
    );
  }
}

bool _matchesBluetoothUuid(String left, String right) {
  if (left == right) {
    return true;
  }

  final normalizedLeft = _normalizeBluetoothUuid(left);
  final normalizedRight = _normalizeBluetoothUuid(right);
  return normalizedLeft != null &&
      normalizedRight != null &&
      normalizedLeft == normalizedRight;
}

String? _normalizeBluetoothUuid(String uuid) {
  final cleaned = uuid.replaceAll('-', '').toLowerCase();
  if (cleaned.length == 4) {
    return '0000$cleaned'
        '00001000800000805f9b34fb';
  }
  if (cleaned.length == 8) {
    return '$cleaned'
        '00001000800000805f9b34fb';
  }
  if (cleaned.length == 32) {
    return cleaned;
  }
  return null;
}
