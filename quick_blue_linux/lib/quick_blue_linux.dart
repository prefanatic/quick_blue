import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'generated_bindings.dart';
import 'src/l2cap_channel.dart';
import 'src/native_libraries.dart';
import 'src/scan_filter.dart';

typedef _BlueZPropertySubscription = StreamSubscription<List<String>>;
typedef _DevicePropertySubscriptions = Map<String, _BlueZPropertySubscription>;
typedef _NotificationSubscriptions = Map<String, _DevicePropertySubscriptions>;

class QuickBlueLinux extends QuickBluePlatform {
  QuickBlueLinux() : this.withClient(BlueZClient());

  @visibleForTesting
  QuickBlueLinux.withClient(this._client) {
    _scanResultController = StreamController<BlueScanResult>.broadcast(
      onListen: _emitKnownScanResults,
    );
  }

  static const _scanResultProperties = <String>{
    'Alias',
    'ManufacturerData',
    'Name',
    'RSSI',
    'ServiceData',
    'UUIDs',
  };

  static void registerWith() {
    QuickBluePlatform.instance = QuickBlueLinux();
  }

  var _isInitialized = false;
  Future<void>? _initialization;

  /// Whether the BlueZ client has finished initializing.
  ///
  /// This implementation detail is retained as a read-only compatibility
  /// getter. Applications should use [isBluetoothAvailable] instead.
  @Deprecated('Use isBluetoothAvailable() instead.')
  bool get isInitialized => _isInitialized;

  // Platform clients.
  final BlueZClient _client;
  final Logger _logger = Logger('QuickBlueLinux');
  late final Libc _libc = Libc();
  LibBluetooth? _libBluetooth;

  // Cached BlueZ objects and active subscriptions.
  final Map<String, BlueZDevice> _devices = <String, BlueZDevice>{};
  final _DevicePropertySubscriptions _devicePropertySubscriptions =
      <String, _BlueZPropertySubscription>{};
  final _NotificationSubscriptions _notificationSubscriptions =
      <String, _DevicePropertySubscriptions>{};
  final _DevicePropertySubscriptions _scanDevicePropertySubscriptions =
      <String, _BlueZPropertySubscription>{};
  final Map<String, Future<void>> _serviceDiscoveryEmits =
      <String, Future<void>>{};
  final Map<String, bool> _lastConnectionState = <String, bool>{};
  final Map<String, _ResolvedCharacteristic> _resolvedCharacteristics =
      <String, _ResolvedCharacteristic>{};

  StreamSubscription<BlueZDevice>? _deviceAddedSubscription;
  StreamSubscription<BlueZDevice>? _deviceRemovedSubscription;

  // Active scan state.
  BlueZAdapter? _activeAdapter;
  Set<String> _activeScanServiceUuids = const <String>{};
  Map<int, Uint8List>? _activeScanManufacturerData;
  int? _activeScanRssi;
  LinuxScanOptions _activeScanOptions = const LinuxScanOptions();
  var _isScanning = false;

  late final StreamController<BlueScanResult> _scanResultController;

  @override
  Stream<BlueScanResult> get scanResultStream => _scanResultController.stream;

  Future<void> _ensureInitialized() {
    final existing = _initialization;
    if (existing != null) {
      return existing;
    }

    final initialization = _initialize();
    _initialization = initialization;
    return initialization;
  }

  Future<void> _initialize() async {
    try {
      await _client.connect();

      _activeAdapter = _selectPoweredAdapter();

      _deviceAddedSubscription ??= _client.deviceAdded.listen(
        _onDeviceAdd,
        onError: (Object error, StackTrace stackTrace) {
          _logger.warning('Device add stream error', error, stackTrace);
        },
      );
      _deviceRemovedSubscription ??= _client.deviceRemoved.listen(
        _onDeviceRemoved,
        onError: (Object error, StackTrace stackTrace) {
          _logger.warning('Device remove stream error', error, stackTrace);
        },
      );

      for (final device in _client.devices) {
        _devices[device.address] = device;
      }

      _isInitialized = true;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    await _ensureInitialized();
    _activeAdapter = _selectPoweredAdapter();
    return _activeAdapter != null;
  }

  @override
  Stream<BlueBluetoothState> get bluetoothStateEvents {
    return Stream.multi((controller) {
      final adapterSubscriptions = <StreamSubscription<List<String>>>[];
      final watchedAdapterAddresses = <String>{};
      StreamSubscription<BlueZAdapter>? adapterAddedSubscription;
      StreamSubscription<BlueZAdapter>? adapterRemovedSubscription;
      var canceled = false;

      void emitState() {
        final adapters = _client.adapters;
        _activeAdapter = _selectPoweredAdapter();
        if (adapters.isEmpty) {
          controller.add(BlueBluetoothState.unavailable);
        } else if (_activeAdapter != null) {
          controller.add(BlueBluetoothState.poweredOn);
        } else {
          controller.add(BlueBluetoothState.poweredOff);
        }
      }

      void watchAdapter(BlueZAdapter adapter) {
        if (!watchedAdapterAddresses.add(adapter.address)) {
          return;
        }
        adapterSubscriptions.add(
          adapter.propertiesChanged.listen((properties) {
            if (properties.contains('Powered')) {
              emitState();
            }
          }, onError: controller.addError),
        );
      }

      void watchAdapters() {
        for (final adapter in _client.adapters) {
          watchAdapter(adapter);
        }
      }

      () async {
        try {
          await _ensureInitialized();
          if (!canceled) {
            watchAdapters();
            emitState();

            adapterAddedSubscription = _client.adapterAdded.listen((_) {
              watchAdapters();
              emitState();
            }, onError: controller.addError);
            adapterRemovedSubscription = _client.adapterRemoved.listen((_) {
              watchAdapters();
              emitState();
            }, onError: controller.addError);
          }
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
        }
      }();

      controller.onCancel = () async {
        canceled = true;
        await adapterAddedSubscription?.cancel();
        await adapterRemovedSubscription?.cancel();
        for (final subscription in adapterSubscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  @override
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) async {
    await _ensureInitialized();

    _activeAdapter = _selectPoweredAdapter();
    final adapter = _activeAdapter;
    if (adapter == null) {
      throw const QuickBlueException(
        code: QuickBlueErrorCode.unavailable,
        operation: 'startScan',
        message: 'No active Bluetooth adapter available.',
      );
    }

    _activeScanServiceUuids = scanFilter.serviceUuids
        .map(_canonicalizeUuid)
        .toSet();
    _activeScanManufacturerData = scanFilter.manufacturerData;
    _activeScanRssi = scanFilter.rssi ?? scanOptions.linux.rssi;
    _activeScanOptions = scanOptions.linux;
    await _setDiscoveryFilter(adapter, scanFilter, scanOptions);
    await adapter.startDiscovery();
    _isScanning = true;
  }

  @override
  Future<void> stopScan() async {
    await _ensureInitialized();
    _isScanning = false;

    final adapter = _activeAdapter;
    if (adapter == null) {
      await _clearScanDevicePropertySubscriptions();
      _activeScanServiceUuids = const <String>{};
      _activeScanManufacturerData = null;
      _activeScanRssi = null;
      _activeScanOptions = const LinuxScanOptions();
      return;
    }
    try {
      await adapter.stopDiscovery();
    } finally {
      await _clearScanDevicePropertySubscriptions();
      _activeScanServiceUuids = const <String>{};
      _activeScanManufacturerData = null;
      _activeScanRssi = null;
      _activeScanOptions = const LinuxScanOptions();
    }
  }

  void _emitKnownScanResults() {
    if (!_isScanning) {
      return;
    }

    for (final device in _client.devices) {
      _trackDevice(device);
      _emitScanResult(device);
    }
  }

  void _onDeviceAdd(BlueZDevice device) {
    _trackDevice(device);
    _emitScanResult(device);
  }

  void _trackDevice(BlueZDevice device) {
    _devices[device.address] = device;
    if (_isScanning) {
      _watchScanDeviceProperties(device);
    }
  }

  void _emitScanResult(BlueZDevice device) {
    if (!_isScanning) {
      return;
    }
    if (!_matchesScanFilter(device)) {
      return;
    }

    final manufacturerData = device.advertisedManufacturerData;
    _scanResultController.add(
      BlueScanResult(
        deviceId: device.address,
        name: device.alias.isEmpty ? device.name : device.alias,
        manufacturerDataHead: manufacturerData.head,
        manufacturerData: manufacturerData.payload,
        rssi: device.rssi,
        serviceUuids: device.uuids
            .map((uuid) => _formatUuid(uuid))
            .toList(growable: false),
        serviceData: device.serviceData.map(
          (uuid, value) =>
              MapEntry(_formatUuid(uuid), Uint8List.fromList(value)),
        ),
      ),
    );
  }

  void _onDeviceRemoved(BlueZDevice device) {
    _observeBackgroundOperation(
      _clearDeviceState(device.address, removeDevice: true),
      'Unable to clear removed device ${device.address}',
    );
  }

  void _watchScanDeviceProperties(BlueZDevice device) {
    final deviceId = device.address;
    if (_scanDevicePropertySubscriptions.containsKey(deviceId)) {
      return;
    }

    _scanDevicePropertySubscriptions[deviceId] = device.propertiesChanged
        .listen(
          (properties) {
            if (properties.any(_scanResultProperties.contains)) {
              _emitScanResult(device);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _logger.warning(
              'Scan property stream error for $deviceId',
              error,
              stackTrace,
            );
          },
        );
  }

  @override
  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  }) async {
    await _ensureInitialized();
    for (final device in _client.devices) {
      _devices[device.address] = device;
    }

    final canonicalServiceUuids = serviceUuids.map(_canonicalizeUuid).toSet();
    return _devices.values
        .where((device) => device.connected)
        .where(
          (device) =>
              canonicalServiceUuids.isEmpty ||
              device.uuids
                  .map(_bluezUuidToCanonical)
                  .toSet()
                  .containsAll(canonicalServiceUuids),
        )
        .map((device) => this.device(device.address))
        .toList(growable: false);
  }

  @override
  Future<void> connect(String deviceId) async {
    await _ensureInitialized();
    final device = _getDeviceOrThrow(deviceId);

    try {
      await _ensureConnectedDevice(device);
      _emitConnectionState(
        deviceId,
        BlueConnectionState.connected,
        BleStatus.success,
      );
    } on Object catch (error, stackTrace) {
      _logger.severe('Failed to connect to $deviceId', error, stackTrace);
      _emitConnectionState(
        deviceId,
        BlueConnectionState.disconnected,
        BleStatus.failure,
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _ensureInitialized();
    final device = _getDeviceOrThrow(deviceId);

    try {
      await device.disconnect();
    } on BlueZNotConnectedException {
      // Already disconnected, ignore.
    } on Object catch (error, stackTrace) {
      _logger.severe('Failed to disconnect from $deviceId', error, stackTrace);
      rethrow;
    } finally {
      _emitConnectionState(
        deviceId,
        BlueConnectionState.disconnected,
        BleStatus.success,
      );
      await _clearDeviceState(deviceId, removeDevice: false);
    }
  }

  @override
  Future<BluetoothBondState> bondState(String deviceId) async {
    await _ensureInitialized();
    final device = _getDeviceOrThrow(deviceId);
    return device.paired
        ? BluetoothBondState.bonded
        : BluetoothBondState.notBonded;
  }

  @override
  Future<void> pair(String deviceId) async {
    await _ensureInitialized();
    final device = _getDeviceOrThrow(deviceId);
    if (device.paired) {
      return;
    }
    await device.pair();
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    await _ensureInitialized();
    final device = _getDeviceOrThrow(deviceId);

    await _ensureConnectedDevice(device);
    await _emitServiceDiscovery(device);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    await _ensureInitialized();
    final resolved = await _resolveCharacteristic(
      deviceId,
      service,
      characteristic,
    );
    final device = resolved.device;
    final targetCharacteristic = resolved.characteristic;

    final key = _characteristicKey(service, characteristic);

    if (bleInputProperty == BleInputProperty.disabled) {
      if (targetCharacteristic.notifying) {
        await targetCharacteristic.stopNotify();
      }
      await _removeNotificationSubscription(deviceId, key);
      return;
    }

    final requiredFlag = bleInputProperty == BleInputProperty.indication
        ? BlueZGattCharacteristicFlag.indicate
        : BlueZGattCharacteristicFlag.notify;
    if (!targetCharacteristic.flags.contains(requiredFlag)) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.unsupported,
        operation: 'setNotifiable',
        deviceId: deviceId,
        serviceId: service,
        characteristicId: characteristic,
        message:
            'Characteristic $characteristic on $service does not support '
            '${bleInputProperty.value}.',
      );
    }

    if (!targetCharacteristic.notifying) {
      try {
        await targetCharacteristic.startNotify();
      } on BlueZAlreadyExistsException {
        // Notifications already active, ignore.
      }
    }

    await _removeNotificationSubscription(deviceId, key);

    final subscription = targetCharacteristic.propertiesChanged.listen(
      (changed) {
        if (changed.contains('Value')) {
          _emitCharacteristicValue(
            device.address,
            resolved.serviceId,
            resolved.characteristicId,
            targetCharacteristic,
          );
        }
        if (changed.contains('Notifying') && !targetCharacteristic.notifying) {
          _observeBackgroundOperation(
            _removeNotificationSubscription(device.address, key),
            'Unable to remove notification subscription for $deviceId',
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning(
          'Notification stream error for $deviceId ($service/$characteristic)',
          error,
          stackTrace,
        );
      },
    );

    final deviceSubscriptions = _notificationSubscriptions.putIfAbsent(
      deviceId,
      () => <String, _BlueZPropertySubscription>{},
    );
    deviceSubscriptions[key] = subscription;

    _emitCharacteristicValue(
      device.address,
      resolved.serviceId,
      resolved.characteristicId,
      targetCharacteristic,
    );
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    await readCharacteristicValue(deviceId, service, characteristic);
  }

  @override
  Future<Uint8List> readCharacteristicValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    await _ensureInitialized();
    final resolved = await _resolveCharacteristic(
      deviceId,
      service,
      characteristic,
    );
    final device = resolved.device;
    final targetCharacteristic = resolved.characteristic;

    final data = await targetCharacteristic.readValue();
    final value = _emitCharacteristicValue(
      device.address,
      resolved.serviceId,
      resolved.characteristicId,
      targetCharacteristic,
      overrideValue: data,
    );
    return value;
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    await _ensureInitialized();
    final resolved = await _resolveCharacteristic(
      deviceId,
      service,
      characteristic,
    );
    final targetCharacteristic = resolved.characteristic;

    final writeType = bleOutputProperty == BleOutputProperty.withResponse
        ? BlueZGattCharacteristicWriteType.request
        : BlueZGattCharacteristicWriteType.command;

    await targetCharacteristic.writeValue(value, type: writeType);
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    throw QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'requestMtu',
      deviceId: deviceId,
      details: expectedMtu,
      message:
          'BlueZ negotiates the ATT MTU automatically and does not expose the '
          'negotiated value through this implementation.',
    );
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) async {
    await _ensureInitialized();

    final device =
        _devices[deviceId] ??
        _client.devices.firstWhereOrNull((d) => d.address == deviceId);

    if (device == null) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.notFound,
        operation: 'openL2cap',
        deviceId: deviceId,
        message: 'Bluetooth device $deviceId is not known.',
      );
    }

    _devices[deviceId] = device;

    final bluetooth = _libBluetooth ??= LibBluetooth();

    final channel = L2capChannel(
      deviceId: deviceId,
      psm: psm,
      addressType: _resolveAddressType(device),
      libc: _libc,
      bluetooth: bluetooth,
      logger: _logger,
    );

    try {
      return await channel.open();
    } on Object catch (error, stackTrace) {
      _logger.severe(
        'Unable to open L2CAP channel to $deviceId',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<bool> isCompanionAssociationSupported() async => false;

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'getCompanionAssociations',
      message: 'Companion device association is not supported on Linux.',
    );
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'companionAssociate',
      message: 'Companion device association is not supported on Linux.',
    );
  }

  @override
  Future<void> companionDisassociate(int associationId) async {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'companionDisassociate',
      message: 'Companion device association is not supported on Linux.',
    );
  }

  BlueZAdapter? _selectPoweredAdapter() {
    return _client.adapters.firstWhereOrNull((adapter) => adapter.powered);
  }

  Future<void> _setDiscoveryFilter(
    BlueZAdapter adapter,
    ScanFilter scanFilter,
    ScanOptions scanOptions,
  ) {
    final serviceUuids = scanFilter.serviceUuids
        .map(_canonicalizeUuid)
        .map(_canonicalToDashed)
        .toList(growable: false);

    final linuxOptions = scanOptions.linux;
    return adapter.setDiscoveryFilter(
      uuids: serviceUuids.isEmpty ? null : serviceUuids,
      rssi: scanFilter.rssi ?? linuxOptions.rssi,
      pathloss: linuxOptions.pathloss,
      transport: linuxOptions.transport.bluezValue,
      duplicateData:
          linuxOptions.duplicateData ?? scanOptions.allowDuplicates ?? false,
      discoverable: linuxOptions.discoverable,
      pattern: linuxOptions.pattern,
    );
  }

  bool _matchesScanFilter(BlueZDevice device) {
    if (_activeScanServiceUuids.isNotEmpty) {
      final matchesService = device.uuids
          .map(_bluezUuidToCanonical)
          .any(_activeScanServiceUuids.contains);
      if (!matchesService) {
        return false;
      }
    }

    final manufacturerData = _activeScanManufacturerData;
    if (manufacturerData != null && manufacturerData.isNotEmpty) {
      for (final entry in manufacturerData.entries) {
        final advertisedData = device.manufacturerData.entries
            .firstWhereOrNull(
              (advertisedEntry) => advertisedEntry.key.id == entry.key,
            )
            ?.value;
        if (advertisedData == null ||
            !_startsWith(advertisedData, entry.value)) {
          return false;
        }
      }
    }

    final scanOptions = _activeScanOptions;
    final rssi = _activeScanRssi;
    if (!meetsRssiThreshold(device.rssi, rssi)) {
      return false;
    }

    final pathloss = scanOptions.pathloss;
    if (pathloss != null && device.txPower != 0) {
      final computedPathloss = device.txPower - device.rssi;
      if (computedPathloss >= pathloss) {
        return false;
      }
    }

    final pattern = scanOptions.pattern;
    if (pattern != null &&
        !device.address.startsWith(pattern) &&
        !device.name.startsWith(pattern)) {
      return false;
    }

    return true;
  }

  bool _startsWith(List<int> data, Uint8List prefix) {
    if (prefix.length > data.length) {
      return false;
    }
    for (var index = 0; index < prefix.length; index++) {
      if (data[index] != prefix[index]) {
        return false;
      }
    }
    return true;
  }

  int _resolveAddressType(BlueZDevice device) {
    final addressType = device.addressType;
    if (addressType == BlueZAddressType.random) {
      return BDADDR_LE_RANDOM;
    }
    return BDADDR_LE_PUBLIC;
  }

  BlueZDevice _getDeviceOrThrow(String deviceId) {
    final device =
        _devices[deviceId] ??
        _client.devices.firstWhereOrNull((d) => d.address == deviceId);
    if (device == null) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.notFound,
        deviceId: deviceId,
        message: 'Bluetooth device $deviceId was not found.',
      );
    }
    _devices[deviceId] = device;
    return device;
  }

  Future<void> _ensureConnectedDevice(BlueZDevice device) async {
    if (device.connected) {
      await _watchDeviceProperties(device);
      return;
    }

    try {
      await device.connect();
    } on BlueZAlreadyConnectedException {
      // Already connected, nothing to do.
    } on BlueZInProgressException {
      await _waitForConnected(device);
    }

    await _waitForConnected(device);
    await _watchDeviceProperties(device);
  }

  Future<void> _watchDeviceProperties(BlueZDevice device) async {
    final deviceId = device.address;
    await _cancelMappedSubscription(_devicePropertySubscriptions, deviceId);

    final subscription = device.propertiesChanged.listen(
      (properties) {
        if (properties.contains('Connected')) {
          final state = device.connected
              ? BlueConnectionState.connected
              : BlueConnectionState.disconnected;
          _emitConnectionState(deviceId, state, BleStatus.success);
          if (!device.connected) {
            _observeBackgroundOperation(
              _clearNotificationSubscriptions(deviceId),
              'Unable to clear notification subscriptions for $deviceId',
            );
            _clearResolvedCharacteristics(deviceId);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning(
          'Property stream error for $deviceId',
          error,
          stackTrace,
        );
      },
    );

    _devicePropertySubscriptions[deviceId] = subscription;
  }

  Future<void> _emitServiceDiscovery(BlueZDevice device) async {
    final existing = _serviceDiscoveryEmits[device.address];
    if (existing != null) {
      return existing;
    }

    final emit = () async {
      await _waitForServicesResolved(device);
      _emitResolvedServices(device);
    }();
    _serviceDiscoveryEmits[device.address] = emit;
    try {
      await emit;
    } finally {
      if (identical(_serviceDiscoveryEmits[device.address], emit)) {
        _serviceDiscoveryEmits.remove(device.address);
      }
    }
  }

  void _emitResolvedServices(BlueZDevice device) {
    for (final service in device.gattServices) {
      final serviceId = _formatUuid(service.uuid);
      final characteristics = service.characteristics
          .map(
            (characteristic) => BluetoothCharacteristicInfo(
              uuid: _formatUuid(characteristic.uuid),
              canRead: characteristic.flags.contains(
                BlueZGattCharacteristicFlag.read,
              ),
              canWriteWithResponse: characteristic.flags.contains(
                BlueZGattCharacteristicFlag.write,
              ),
              canWriteWithoutResponse: characteristic.flags.contains(
                BlueZGattCharacteristicFlag.writeWithoutResponse,
              ),
              canNotify: characteristic.flags.contains(
                BlueZGattCharacteristicFlag.notify,
              ),
              canIndicate: characteristic.flags.contains(
                BlueZGattCharacteristicFlag.indicate,
              ),
            ),
          )
          .toList(growable: false);
      handleServiceDiscovered(device.address, serviceId, characteristics);
    }
    onServiceDiscoveryComplete(device.address);
  }

  Future<void> _waitForConnected(
    BlueZDevice device, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return _waitForDeviceProperty(
      device,
      propertyName: 'Connected',
      isReady: () => device.connected,
      timeout: timeout,
    );
  }

  Future<void> _waitForServicesResolved(
    BlueZDevice device, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return _waitForDeviceProperty(
      device,
      propertyName: 'ServicesResolved',
      isReady: () => device.servicesResolved,
      timeout: timeout,
    );
  }

  Future<void> _waitForDeviceProperty(
    BlueZDevice device, {
    required String propertyName,
    required bool Function() isReady,
    required Duration timeout,
  }) async {
    if (isReady()) {
      return;
    }

    final completer = Completer<void>();
    late final StreamSubscription<List<String>> subscription;
    subscription = device.propertiesChanged.listen(
      (properties) {
        if (properties.contains(propertyName) &&
            isReady() &&
            !completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    try {
      await completer.future.timeout(timeout);
    } finally {
      await subscription.cancel();
    }
  }

  Future<_ResolvedCharacteristic> _resolveCharacteristic(
    String deviceId,
    String serviceId,
    String characteristicId,
  ) async {
    final device = _getDeviceOrThrow(deviceId);
    await _ensureConnectedDevice(device);
    await _waitForServicesResolved(device);

    final canonicalService = _canonicalizeUuid(serviceId);
    final canonicalCharacteristic = _canonicalizeUuid(characteristicId);
    final key = '$deviceId|$canonicalService|$canonicalCharacteristic';
    final cached = _resolvedCharacteristics[key];
    if (cached != null) {
      return cached;
    }

    final service = device.gattServices.firstWhereOrNull(
      (candidate) => _bluezUuidToCanonical(candidate.uuid) == canonicalService,
    );
    if (service == null) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.notFound,
        operation: 'resolveCharacteristic',
        deviceId: deviceId,
        serviceId: serviceId,
        message: 'Service $serviceId not found on $deviceId.',
      );
    }

    final characteristic = service.characteristics.firstWhereOrNull(
      (candidate) =>
          _bluezUuidToCanonical(candidate.uuid) == canonicalCharacteristic,
    );
    if (characteristic == null) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.notFound,
        operation: 'resolveCharacteristic',
        deviceId: deviceId,
        serviceId: serviceId,
        characteristicId: characteristicId,
        message:
            'Characteristic $characteristicId not found on $serviceId for '
            '$deviceId.',
      );
    }

    final resolved = _ResolvedCharacteristic(
      device: device,
      serviceId: _formatUuid(service.uuid),
      characteristicId: _formatUuid(characteristic.uuid),
      characteristic: characteristic,
    );
    _resolvedCharacteristics[key] = resolved;
    return resolved;
  }

  Uint8List _emitCharacteristicValue(
    String deviceId,
    String serviceId,
    String characteristicId,
    BlueZGattCharacteristic characteristic, {
    List<int>? overrideValue,
  }) {
    final data = overrideValue ?? characteristic.value;
    final value = data is Uint8List ? data : Uint8List.fromList(data);
    handleCharacteristicValueChanged(
      deviceId,
      serviceId,
      characteristicId,
      value,
    );
    return value;
  }

  void _emitConnectionState(
    String deviceId,
    BlueConnectionState state,
    BleStatus status,
  ) {
    final handler = onConnectionChanged;
    if (handler == null) {
      return;
    }

    final isConnected = state == BlueConnectionState.connected;
    final lastState = _lastConnectionState[deviceId];
    if (status == BleStatus.success && lastState == isConnected) {
      return;
    }

    _lastConnectionState[deviceId] = isConnected;
    handler(deviceId, state, status);
  }

  Future<void> _clearDeviceState(
    String deviceId, {
    required bool removeDevice,
  }) async {
    if (removeDevice) {
      _devices.remove(deviceId);
    }

    _lastConnectionState.remove(deviceId);
    _serviceDiscoveryEmits.remove(deviceId);
    _clearResolvedCharacteristics(deviceId);

    await _clearNotificationSubscriptions(deviceId);
    await _cancelMappedSubscription(_scanDevicePropertySubscriptions, deviceId);
    await _cancelMappedSubscription(_devicePropertySubscriptions, deviceId);
  }

  void _clearResolvedCharacteristics(String deviceId) {
    _resolvedCharacteristics.removeWhere(
      (key, _) => key.startsWith('$deviceId|'),
    );
  }

  Future<void> _clearScanDevicePropertySubscriptions() async {
    await _clearSubscriptions(_scanDevicePropertySubscriptions);
  }

  Future<void> _clearNotificationSubscriptions(String deviceId) async {
    final subscriptions = _notificationSubscriptions.remove(deviceId);
    if (subscriptions == null) {
      return;
    }
    await _cancelSubscriptions(subscriptions.values);
  }

  Future<void> _removeNotificationSubscription(
    String deviceId,
    String key,
  ) async {
    final subscriptions = _notificationSubscriptions[deviceId];
    if (subscriptions == null) {
      return;
    }
    await _cancelMappedSubscription(subscriptions, key);
    if (subscriptions.isEmpty) {
      _notificationSubscriptions.remove(deviceId);
    }
  }

  Future<void> _cancelMappedSubscription<T>(
    Map<String, StreamSubscription<T>> subscriptions,
    String key,
  ) async {
    final subscription = subscriptions.remove(key);
    await _cancelSubscription(subscription);
  }

  Future<void> _clearSubscriptions<T>(
    Map<String, StreamSubscription<T>> subscriptions,
  ) async {
    final removedSubscriptions = subscriptions.values.toList();
    subscriptions.clear();
    await _cancelSubscriptions(removedSubscriptions);
  }

  Future<void> _cancelSubscriptions<T>(
    Iterable<StreamSubscription<T>> subscriptions,
  ) async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> _cancelSubscription<T>(
    StreamSubscription<T>? subscription,
  ) async {
    await subscription?.cancel();
  }

  void _observeBackgroundOperation(
    Future<void> operation,
    String failureMessage,
  ) {
    operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning(failureMessage, error, stackTrace);
      },
    );
  }

  String _characteristicKey(String serviceId, String characteristicId) {
    final serviceCanonical = _canonicalizeUuid(serviceId);
    final characteristicCanonical = _canonicalizeUuid(characteristicId);
    return '$serviceCanonical|$characteristicCanonical';
  }

  String _canonicalizeUuid(String uuid) {
    final cleaned = uuid.replaceAll('-', '').toLowerCase();
    if (cleaned.length == 4) {
      return '0000${cleaned}00001000800000805f9b34fb';
    }
    if (cleaned.length == 8) {
      return '${cleaned}00001000800000805f9b34fb';
    }
    if (cleaned.length == 32) {
      return cleaned;
    }
    throw ArgumentError.value(uuid, 'uuid', 'Unsupported UUID format');
  }

  String _bluezUuidToCanonical(BlueZUUID uuid) {
    return uuid.toString().replaceAll('-', '').toLowerCase();
  }

  String _formatUuid(BlueZUUID uuid) {
    return _canonicalToDashed(_bluezUuidToCanonical(uuid));
  }

  String _canonicalToDashed(String canonical) {
    if (canonical.length != 32) {
      return canonical;
    }
    return '${canonical.substring(0, 8)}-${canonical.substring(8, 12)}-${canonical.substring(12, 16)}-${canonical.substring(16, 20)}-${canonical.substring(20)}';
  }
}

class _ResolvedCharacteristic {
  _ResolvedCharacteristic({
    required this.device,
    required this.serviceId,
    required this.characteristicId,
    required this.characteristic,
  });

  final BlueZDevice device;
  final String serviceId;
  final String characteristicId;
  final BlueZGattCharacteristic characteristic;
}

class _BlueZManufacturerData {
  _BlueZManufacturerData({required this.head, required this.payload});

  final Uint8List head;
  final Uint8List payload;
}

extension _LinuxScanTransportExtension on LinuxScanTransport {
  String get bluezValue {
    return switch (this) {
      LinuxScanTransport.auto => 'auto',
      LinuxScanTransport.bredr => 'bredr',
      LinuxScanTransport.le => 'le',
    };
  }
}

extension _BlueZDeviceExtension on BlueZDevice {
  _BlueZManufacturerData get advertisedManufacturerData {
    if (manufacturerData.isEmpty) {
      return _BlueZManufacturerData(head: Uint8List(0), payload: Uint8List(0));
    }

    final sorted = manufacturerData.entries.toList()
      ..sort((a, b) => a.key.id - b.key.id);
    final payloadLength = sorted.fold<int>(
      0,
      (length, entry) => length + entry.value.length,
    );
    final payload = Uint8List(payloadLength);
    var offset = 0;
    for (final entry in sorted) {
      payload.setRange(offset, offset + entry.value.length, entry.value);
      offset += entry.value.length;
    }

    return _BlueZManufacturerData(
      head: Uint8List.fromList(sorted.first.value),
      payload: payload,
    );
  }
}
