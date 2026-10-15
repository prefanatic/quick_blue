import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:logging/logging.dart';
import 'package:quick_blue_core/quick_blue_core.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart'
    show QuickBluePlatform;

import 'src/l2cap_endpoint.dart';
import 'src/connection_ownership.dart';
import 'src/dbus_connection_lease.dart';
import 'src/scan_session.dart';
import 'src/gatt_session.dart';
import 'src/device_property.dart';
import 'src/uuid_rules.dart';

export 'src/connection_ownership.dart' show QuickBlueLinuxConnectionLease;
export 'src/dbus_connection_lease.dart' show DbusConnectionLease;

typedef _BlueZPropertySubscription = StreamSubscription<List<String>>;
typedef _DevicePropertySubscriptions = Map<String, _BlueZPropertySubscription>;

class QuickBlueLinux extends QuickBluePlatform {
  QuickBlueLinux() : this.withClient(BlueZClient());

  @visibleForTesting
  QuickBlueLinux.withClient(
    this._client, {
    QuickBlueLinuxConnectionLease? connectionLease,
  }) : _connectionOwnership = ConnectionOwnership(
         connectionLease ?? DbusConnectionLease(),
       ) {
    _scanSession = LinuxScanSession(
      client: _client,
      onTrackDevice: (device) => _devices[device.address] = device,
      logger: _logger,
    );
    _gattSession = LinuxGattSession(
      getDevice: _getDeviceOrThrow,
      ensureConnected: _ensureConnectedDevice,
      handleServiceDiscovered: handleServiceDiscovered,
      onServiceDiscoveryComplete: (deviceId) =>
          onServiceDiscoveryComplete(deviceId),
      handleCharacteristicValueChanged: handleCharacteristicValueChanged,
      handleGattServicesChanged: handleGattServicesChanged,
      logger: _logger,
    );
    _l2capEndpoint = LinuxL2capEndpoint(
      client: _client,
      devices: _devices,
      logger: _logger,
    );
  }

  static void registerWith() {
    QuickBluePlatform.instance = QuickBlueLinux();
  }

  @override
  Future<QuickBlueCapabilities> capabilities() async {
    return const QuickBlueCapabilities(
      bonding: BluetoothBondingCapability.queryAndPair,
      mtu: BluetoothMtuCapability.unsupported,
      gattServiceChanges: BluetoothGattServiceChangeCapability.databaseOnly,
      connectedDeviceLookup:
          BluetoothConnectedDeviceLookupCapability.unrestricted,
      supportsL2capSockets: true,
      supportsCompanionAssociation: false,
      supportsAppleAccessorySetup: false,
    );
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
  final ConnectionOwnership _connectionOwnership;
  final Logger _logger = Logger('QuickBlueLinux');

  // Cached BlueZ objects and active subscriptions.
  final Map<String, BlueZDevice> _devices = <String, BlueZDevice>{};
  final _DevicePropertySubscriptions _devicePropertySubscriptions =
      <String, _BlueZPropertySubscription>{};
  final Map<String, bool> _lastConnectionState = <String, bool>{};

  StreamSubscription<BlueZDevice>? _deviceAddedSubscription;
  StreamSubscription<BlueZDevice>? _deviceRemovedSubscription;

  BlueZAdapter? _activeAdapter;
  late final LinuxScanSession _scanSession;
  late final LinuxGattSession _gattSession;
  late final LinuxL2capEndpoint _l2capEndpoint;

  @override
  Stream<BlueScanResult> get scanResultStream => _scanSession.results;

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

    await _scanSession.start(adapter, scanFilter, scanOptions);
  }

  @override
  Future<void> stopScan() async {
    await _ensureInitialized();
    await _scanSession.stop(_activeAdapter);
  }

  void _onDeviceAdd(BlueZDevice device) {
    _scanSession.deviceAdded(device);
  }

  void _onDeviceRemoved(BlueZDevice device) {
    _observeBackgroundOperation(
      _clearDeviceState(device.address, removeDevice: true),
      'Unable to clear removed device ${device.address}',
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

    final canonicalServiceUuids = serviceUuids.map(canonicalizeUuid).toSet();
    return _devices.values
        .where((device) => device.connected)
        .where(
          (device) =>
              canonicalServiceUuids.isEmpty ||
              device.uuids
                  .map(bluezUuidToCanonical)
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

    await _connectionOwnership.attach(deviceId);

    try {
      await _ensureConnectedDevice(device);
      _emitConnectionState(
        deviceId,
        BlueConnectionState.connected,
        BleStatus.success,
      );
    } on Object catch (error, stackTrace) {
      try {
        await _connectionOwnership.detach(deviceId, onLastClient: () async {});
      } on Object catch (releaseError, releaseStackTrace) {
        _logger.warning(
          'Failed to release the connection lease for $deviceId',
          releaseError,
          releaseStackTrace,
        );
      }
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
    if (!_connectionOwnership.owns(deviceId)) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.invalidState,
        operation: 'disconnect',
        deviceId: deviceId,
        message: 'This Flutter engine is not connected to $deviceId.',
      );
    }
    final device = _getDeviceOrThrow(deviceId);

    try {
      await _gattSession.stopNotificationsForClient(deviceId);
      await runDisconnectRequest(deviceId, () async {
        await _connectionOwnership.detach(
          deviceId,
          onLastClient: () async {
            try {
              await device.disconnect();
            } on BlueZNotConnectedException {
              // Already disconnected, ignore.
            }
          },
        );
      });

      _emitConnectionState(
        deviceId,
        BlueConnectionState.disconnected,
        BleStatus.success,
      );
      await _clearDeviceState(deviceId, removeDevice: false);
    } on Object catch (error, stackTrace) {
      _logger.severe('Failed to disconnect from $deviceId', error, stackTrace);
      rethrow;
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
    await _gattSession.discoverServices(device);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    await _ensureInitialized();
    await _gattSession.setNotifiable(
      deviceId,
      service,
      characteristic,
      bleInputProperty,
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
    return _gattSession.readCharacteristicValue(
      deviceId,
      service,
      characteristic,
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
    await _ensureInitialized();
    await _gattSession.writeValue(
      deviceId,
      service,
      characteristic,
      value,
      bleOutputProperty,
    );
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
    return _l2capEndpoint.open(deviceId, psm);
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
    _gattSession.watchDevice(device);

    final subscription = device.propertiesChanged.listen(
      (properties) {
        if (properties.contains('Connected')) {
          final state = device.connected
              ? BlueConnectionState.connected
              : BlueConnectionState.disconnected;
          _emitConnectionState(deviceId, state, BleStatus.success);
          if (!device.connected) {
            _observeBackgroundOperation(
              _connectionOwnership.detach(deviceId, onLastClient: () async {}),
              'Unable to detach the connection client for $deviceId',
            );
            _observeBackgroundOperation(
              _gattSession.clearNotificationSubscriptions(deviceId),
              'Unable to clear notification subscriptions for $deviceId',
            );
            _gattSession.clearResolvedCharacteristics(deviceId);
          }
        }
        if (properties.contains('ServicesResolved') && device.connected) {
          _gattSession.servicesResolvedChanged(device);
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

  Future<void> _waitForConnected(
    BlueZDevice device, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return waitForDeviceProperty(
      device,
      propertyName: 'Connected',
      isReady: () => device.connected,
      timeout: timeout,
    );
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
    await _gattSession.clearDevice(deviceId);
    await _scanSession.removeDevice(deviceId);
    await _cancelMappedSubscription(_devicePropertySubscriptions, deviceId);
  }

  Future<void> _cancelMappedSubscription<T>(
    Map<String, StreamSubscription<T>> subscriptions,
    String key,
  ) async {
    final subscription = subscriptions.remove(key);
    await _cancelSubscription(subscription);
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
}
