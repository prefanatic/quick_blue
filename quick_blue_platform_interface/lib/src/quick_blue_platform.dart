import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models.dart';
import 'bluetooth_device.dart';
import 'callbacks.dart';
import 'service_discovery_event.dart';
import 'unimplemented_quick_blue_platform.dart';

abstract class QuickBluePlatform extends PlatformInterface {
  QuickBluePlatform() : super(token: _token);

  static final Object _token = Object();

  static QuickBluePlatform _instance = UnimplementedQuickBluePlatform();

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
    return BluetoothDevice.internal(
      deviceId: deviceId,
      platform: this,
      discoverServices: _discoverServicesForDevice,
    );
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
      StreamController<ServiceDiscoveryEvent>.broadcast();

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
      ServiceDiscoveredEvent(deviceId, service),
    );
    _serviceDiscoveryController.add(service);
    _onServiceDiscovered?.call(deviceId, serviceId, characteristicIds);
  }

  void _handleServiceDiscoveryComplete(String deviceId) {
    _serviceDiscoveryEventController.add(
      ServiceDiscoveryCompleteEvent(deviceId),
    );
    _serviceDiscoveryCompleteController.add(deviceId);
  }

  Future<List<BluetoothService>> _discoverServicesForDevice(
    String deviceId,
  ) async {
    final services = <BluetoothService>[];
    final events = StreamQueue(_serviceDiscoveryEvents(deviceId));

    try {
      await discoverServices(deviceId);

      while (await events.hasNext) {
        switch (await events.next) {
          case ServiceDiscoveredEvent(:final service):
            services.add(service);
          case ServiceDiscoveryCompleteEvent():
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

  Stream<ServiceDiscoveryEvent> _serviceDiscoveryEvents(String deviceId) {
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
