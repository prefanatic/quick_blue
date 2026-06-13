library quick_blue_platform_interface;

import 'dart:async';
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:quick_blue_platform_interface/method_channel_quick_blue.dart';

import 'models.dart';

export 'method_channel_quick_blue.dart';
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

  static QuickBluePlatform _instance = MethodChannelQuickBlue();

  static QuickBluePlatform get instance => _instance;

  static set instance(QuickBluePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> isBluetoothAvailable();

  Future<void> startScan({ScanFilter scanFilter = ScanFilter.empty});

  Future<void> stopScan();

  Stream<BlueScanResult> get scanResultStream;

  _ScanFilterKey? _activeScanFilter;
  var _activeScanListeners = 0;
  var _activeScanStarted = false;
  Future<void> _scanLifecycle = Future<void>.value();

  Stream<BlueScanResult> scanResults({
    ScanFilter scanFilter = ScanFilter.empty,
  }) async* {
    final filter = _ScanFilterKey.from(scanFilter);

    await _acquireScan(filter);
    try {
      yield* scanResultStream;
    } finally {
      await _releaseScan();
    }
  }

  Future<void> _acquireScan(_ScanFilterKey filter) {
    return _queueScanLifecycle(() async {
      final activeFilter = _activeScanFilter;
      if (_activeScanListeners == 0) {
        _activeScanFilter = filter;
        try {
          await startScan(scanFilter: filter.toScanFilter());
          _activeScanStarted = true;
        } catch (_) {
          _activeScanFilter = null;
          rethrow;
        }
      } else if (activeFilter == null || !activeFilter.equals(filter)) {
        throw StateError(
          'Cannot start scanning with a different ScanFilter while another '
          'scanResults stream is active.',
        );
      }

      _activeScanListeners++;
    });
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

  Future<void> connect(String deviceId);

  Future<void> disconnect(String deviceId);

  Future<CompanionDevice?> companionAssociate({
    String? deviceId,
    ScanFilter? scanFilter,
  });

  Future<void> companionDisassociate(int associationId);

  Future<List<CompanionDevice>?> getCompanionAssociations();

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

  Stream<BluetoothService> get serviceDiscoveryStream {
    return _serviceDiscoveryController.stream;
  }

  Stream<String> get serviceDiscoveryCompleteStream {
    return _serviceDiscoveryCompleteController.stream;
  }

  OnServiceDiscovered? _onServiceDiscovered;

  OnServiceDiscovered? get onServiceDiscovered => _handleServiceDiscovered;

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

  OnValueChanged? get onValueChanged => _handleValueChanged;

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
  ) {
    _serviceDiscoveryController.add(
      BluetoothService(
        deviceId: deviceId,
        uuid: serviceId,
        characteristics: characteristicIds,
      ),
    );
    _onServiceDiscovered?.call(deviceId, serviceId, characteristicIds);
  }

  void _handleServiceDiscoveryComplete(String deviceId) {
    _serviceDiscoveryCompleteController.add(deviceId);
  }

  void _handleValueChanged(
    String deviceId,
    String characteristicId,
    Uint8List value,
  ) {
    _characteristicValueController.add(
      BluetoothCharacteristicValue(
        deviceId: deviceId,
        characteristicId: characteristicId,
        value: value,
      ),
    );
    _onValueChanged?.call(deviceId, characteristicId, value);
  }
}

class _ScanFilterKey {
  _ScanFilterKey._({
    required this.serviceUuids,
    required this.manufacturerData,
  });

  factory _ScanFilterKey.from(ScanFilter scanFilter) {
    final manufacturerData = scanFilter.manufacturerData;

    return _ScanFilterKey._(
      serviceUuids: List<String>.unmodifiable(scanFilter.serviceUuids),
      manufacturerData: manufacturerData == null || manufacturerData.isEmpty
          ? null
          : Map<int, Uint8List>.unmodifiable(
              manufacturerData.map(
                (manufacturerId, data) =>
                    MapEntry(manufacturerId, Uint8List.fromList(data)),
              ),
            ),
    );
  }

  final List<String> serviceUuids;
  final Map<int, Uint8List>? manufacturerData;

  ScanFilter toScanFilter() {
    final data = manufacturerData;

    return ScanFilter(
      serviceUuids: List<String>.unmodifiable(serviceUuids),
      manufacturerData: data == null
          ? null
          : Map<int, Uint8List>.unmodifiable(
              data.map(
                (manufacturerId, value) =>
                    MapEntry(manufacturerId, Uint8List.fromList(value)),
              ),
            ),
    );
  }

  bool equals(_ScanFilterKey other) {
    return _stringListsEqual(serviceUuids, other.serviceUuids) &&
        _manufacturerDataEqual(manufacturerData, other.manufacturerData);
  }

  bool _stringListsEqual(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }

    return true;
  }

  bool _manufacturerDataEqual(
    Map<int, Uint8List>? left,
    Map<int, Uint8List>? right,
  ) {
    if (left == null || right == null) {
      return left == right;
    }
    if (left.length != right.length) {
      return false;
    }

    for (final key in left.keys) {
      final leftValue = left[key];
      final rightValue = right[key];
      if (leftValue == null ||
          rightValue == null ||
          !_uint8ListsEqual(leftValue, rightValue)) {
        return false;
      }
    }

    return true;
  }

  bool _uint8ListsEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }

    return true;
  }
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
    final stateEvents = StreamIterator(
      connectionStateStream.where(
        (event) =>
            event.status == BleStatus.failure || event.state == targetState,
      ),
    );

    try {
      final stateChanged = stateEvents.moveNext();
      await operation();
      await stateChanged;
      if (stateEvents.current.status == BleStatus.failure) {
        throw StateError(failureMessage);
      }
    } finally {
      await stateEvents.cancel();
    }
  }

  Future<List<BluetoothService>> discoverServices() async {
    final services = <BluetoothService>[];
    final subscription = serviceDiscoveryStream.listen((service) {
      services.add(service);
    });
    final completeEvents = StreamIterator(
      _platform.serviceDiscoveryCompleteStream.where(
        (completedDeviceId) => completedDeviceId == deviceId,
      ),
    );

    try {
      final complete = completeEvents.moveNext();
      await _platform.discoverServices(deviceId);
      await complete;
      return List<BluetoothService>.unmodifiable(services);
    } finally {
      await subscription.cancel();
      await completeEvents.cancel();
    }
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
              event.characteristicId == characteristicId,
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
    final values = StreamIterator(valueStream);

    try {
      final value = values.moveNext();
      await _platform.readValue(deviceId, serviceId, characteristicId);
      await value;
      return values.current;
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
