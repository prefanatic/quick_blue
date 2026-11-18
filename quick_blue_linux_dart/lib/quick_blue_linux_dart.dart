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
  /// Uses the first powered adapter unless [adapterAddress] is specified.
  /// An explicit address never falls back to another adapter.
  QuickBlueLinux({String? adapterAddress})
    : this.withClient(BlueZClient(), adapterAddress: adapterAddress);

  @visibleForTesting
  QuickBlueLinux.withClient(
    this._client, {
    QuickBlueLinuxConnectionLease? connectionLease,
    this.adapterAddress,
  }) : _connectionOwnership = ConnectionOwnership(
         connectionLease ?? DbusConnectionLease(),
       ) {
    _scanSession = LinuxScanSession(
      client: _client,
      acceptsDevice: (device) =>
          adapterAddress == null || device.adapter.address == adapterAddress,
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

  /// Linux adapter address selected by the operator, or null for the default.
  final String? adapterAddress;

  /// Returns immutable snapshots; this never powers on an adapter.
  Future<List<QuickBlueLinuxAdapter>> adapters() async {
    await _ensureInitialized();
    return List.unmodifiable(
      _client.adapters.map(
        (adapter) => QuickBlueLinuxAdapter(
          address: adapter.address,
          powered: adapter.powered,
        ),
      ),
    );
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
  bool _closed = false;
  Future<void>? _closing;
  bool _clientClosed = false;

  Future<void> _closeClient() async {
    if (_clientClosed) return;
    _clientClosed = true;
    await _client.close();
  }

  /// Releases this client's resources. Callers must first cancel their public
  /// scan/connection/notification subscriptions and await outstanding requests.
  /// Idempotent; a closed instance cannot be reused.
  Future<void> close() {
    return _closing ??= _close();
  }

  Future<void> _close() async {
    _closed = true;
    try {
      await _initialization;
    } catch (_) {
      // Initialization already reports its primary failure.
    }
    Object? failure;
    StackTrace? failureStack;
    Future<void> release(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
        _logger.warning('Linux shutdown cleanup failed', error, stack);
      }
    }

    await release(() => _serializeScan(_stopScan));
    for (final deviceId in _connectionOwnership.deviceIds) {
      await release(() => disconnect(deviceId));
    }
    for (final deviceId in _devices.keys.toList()) {
      await release(() => _clearDeviceState(deviceId, removeDevice: true));
    }
    await release(() async {
      await _deviceAddedSubscription?.cancel();
    });
    await release(() async {
      await _deviceRemovedSubscription?.cancel();
    });
    await release(_scanSession.close);
    await release(_closeClient);
    await release(_connectionOwnership.close);
    _isInitialized = false;
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }

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
  // Native targets follow the held lease, not the refreshable discovery cache.
  final Map<String, BlueZDevice> _ownedDevices = <String, BlueZDevice>{};
  final Map<String, Future<void>> _connecting = <String, Future<void>>{};
  // Explicit disconnect includes notification release and state cleanup, not
  // just the lease detach (which native callbacks may independently reenter).
  final Map<String, Future<void>> _disconnecting = <String, Future<void>>{};
  final _DevicePropertySubscriptions _devicePropertySubscriptions =
      <String, _BlueZPropertySubscription>{};
  final Map<String, bool> _lastConnectionState = <String, bool>{};

  StreamSubscription<BlueZDevice>? _deviceAddedSubscription;
  StreamSubscription<BlueZDevice>? _deviceRemovedSubscription;

  BlueZAdapter? _activeAdapter;
  BlueZAdapter? _scanAdapter;
  Future<void>? _scanOperation;
  late final LinuxScanSession _scanSession;
  late final LinuxGattSession _gattSession;
  late final LinuxL2capEndpoint _l2capEndpoint;

  @override
  Stream<BlueScanResult> get scanResultStream => _scanSession.results;

  Future<void> _ensureInitialized() {
    if (_closed) {
      return Future.error(
        const QuickBlueException(
          code: QuickBlueErrorCode.invalidState,
          operation: 'initialize',
          message: 'Linux client is closed.',
        ),
      );
    }
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
        if (_matchesAdapter(device)) _devices[device.address] = device;
      }

      _isInitialized = true;
    } catch (error, stack) {
      _initialization = null;
      _closed = true;
      for (final subscription in [
        _deviceAddedSubscription,
        _deviceRemovedSubscription,
      ]) {
        try {
          await subscription?.cancel();
        } catch (cleanupError, cleanupStack) {
          _logger.warning(
            'Initialization subscription cleanup failed',
            cleanupError,
            cleanupStack,
          );
        }
      }
      try {
        await _closeClient();
      } catch (cleanupError, cleanupStack) {
        _logger.warning(
          'Initialization transport cleanup failed',
          cleanupError,
          cleanupStack,
        );
      }
      Error.throwWithStackTrace(error, stack);
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
        if (adapters.isEmpty ||
            (adapterAddress != null &&
                !adapters.any(
                  (adapter) => adapter.address == adapterAddress,
                ))) {
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
  }) => _serializeScan(() async {
    await _ensureInitialized();
    // A failed release must finish against its original adapter before a new
    // scan can replace ownership, even when adapter selection has changed.
    if (_scanAdapter != null) await _stopScan();

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
    _scanAdapter = adapter;
  });

  @override
  Future<void> stopScan() => _serializeScan(() async {
    await _ensureInitialized();
    await _stopScan();
  });

  Future<void> _stopScan() async {
    final adapter = _scanAdapter;
    await _scanSession.stop(adapter);
    _scanAdapter = null;
  }

  Future<void> _serializeScan(Future<void> Function() action) async {
    final previous = _scanOperation;
    final done = Completer<void>();
    _scanOperation = done.future;
    try {
      await previous;
      await action();
    } finally {
      done.complete();
      if (identical(_scanOperation, done.future)) _scanOperation = null;
    }
  }

  void _onDeviceAdd(BlueZDevice device) {
    if (!_matchesAdapter(device)) return;
    _scanSession.deviceAdded(device);
  }

  void _onDeviceRemoved(BlueZDevice device) {
    if (!_matchesAdapter(device)) return;
    final owned = _ownedDevices[device.address];
    if (owned != null && !identical(owned, device)) return;
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
      if (_matchesAdapter(device)) _devices[device.address] = device;
    }

    final canonicalServiceUuids = serviceUuids.map(canonicalizeUuid).toSet();
    return _devices.values
        .where(
          (device) =>
              adapterAddress == null ||
              device.adapter.address == adapterAddress,
        )
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
    final existing = _connecting[deviceId];
    if (existing != null) return existing;
    late final Future<void> pending;
    bool isCurrent() => identical(_connecting[deviceId], pending);
    pending = Future<void>.microtask(() async {
      try {
        await _connect(deviceId, isCurrent);
      } finally {
        // A retired native reply must not remove a replacement connect.
        if (isCurrent()) _connecting.remove(deviceId);
      }
    });
    _connecting[deviceId] = pending;
    await pending;
  }

  Future<void> _connect(String deviceId, bool Function() isCurrent) async {
    void checkCurrent() {
      if (!isCurrent()) {
        throw QuickBlueException(
          code: QuickBlueErrorCode.cancelled,
          operation: 'connect',
          deviceId: deviceId,
          message: 'The connection request was superseded by detach.',
        );
      }
    }

    // Settle the whole old transition before selecting a target or touching
    // observers: a held StopNotify or late clear must not destroy a newer link.
    await _disconnecting[deviceId];
    checkCurrent();
    final device = _getDeviceOrThrow(deviceId);

    // This observer belongs to the previous connection. Retire it before lease
    // registration/native connect can suspend, so a delayed disconnected event
    // cannot release the new membership. In-flight detach is joined by attach.
    await _cancelMappedSubscription(_devicePropertySubscriptions, deviceId);
    checkCurrent();

    // Capture the actual BlueZ adapter, including for default selection. Retain
    // this identity through detach even if the cached device is later replaced.
    try {
      await _connectionOwnership.attach(
        deviceId,
        leaseId: '${device.adapter.address}/$deviceId',
        isCurrent: isCurrent,
      );
    } catch (error, stackTrace) {
      // Failed reattach retains the cleanup target. Keep observing it for a
      // later spontaneous disconnect, without hiding the registration error.
      if (isCurrent() && _connectionOwnership.owns(deviceId)) {
        try {
          await _watchDeviceProperties(device, checkCurrent: checkCurrent);
        } catch (watchError, watchStack) {
          _logger.warning(
            'Unable to restore device observer',
            watchError,
            watchStack,
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    checkCurrent();
    _ownedDevices.putIfAbsent(deviceId, () => device);

    try {
      await _ensureConnectedDevice(device, checkCurrent: checkCurrent);
      checkCurrent();
      _emitConnectionState(
        deviceId,
        BlueConnectionState.connected,
        BleStatus.success,
      );
    } on Object catch (error, stackTrace) {
      // Supersession does not abort the submitted native call. Its eventual
      // error still belongs to its caller, not the replacement's ownership.
      if (!isCurrent()) rethrow;
      try {
        await _detachDevice(
          device,
          onLastClient: () async {},
          retireConnect: false,
        );
      } on Object catch (releaseError, releaseStackTrace) {
        _logger.warning(
          'Failed to release the connection lease for $deviceId',
          releaseError,
          releaseStackTrace,
        );
      }
      _logger.severe('Failed to connect to $deviceId', error, stackTrace);
      if (isCurrent()) {
        _emitConnectionState(
          deviceId,
          BlueConnectionState.disconnected,
          BleStatus.failure,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    // Shutdown may detach already-owned devices after closing the public gate.
    if (!_closed) await _ensureInitialized();
    if (!_connectionOwnership.owns(deviceId) &&
        !_disconnecting.containsKey(deviceId)) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.invalidState,
        operation: 'disconnect',
        deviceId: deviceId,
        message: 'This Flutter engine is not connected to $deviceId.',
      );
    }
    // Each explicit disconnect is new intent, even when joining old teardown.
    // Retire only the connect preceding this request, before cleanup suspends;
    // a later reconnect may intentionally wait for that same teardown.
    _connecting.remove(deviceId);
    final device = _getDeviceOrThrow(deviceId);
    await _disconnecting.putIfAbsent(
      deviceId,
      () => Future<void>.microtask(() => _disconnect(deviceId, device)),
    );
    // A joining facade request may have subscribed after the native event.
    // Publish completion after clear, before waiting reconnects can emit state.
    _emitConnectionState(
      deviceId,
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
  }

  Future<void> _disconnect(String deviceId, BlueZDevice device) async {
    try {
      await _gattSession.stopNotificationsForClient(deviceId);
      await runDisconnectRequest(deviceId, () async {
        await _detachDevice(
          device,
          onLastClient: () async {
            try {
              await device.disconnect();
            } on BlueZNotConnectedException {
              // Already disconnected, ignore.
            }
          },
          retireConnect: false,
        );
      });

      await _clearDeviceState(deviceId, removeDevice: false);
    } on Object catch (error, stackTrace) {
      _logger.severe('Failed to disconnect from $deviceId', error, stackTrace);
      if (!device.connected) {
        // Native disconnect may have succeeded before lease cleanup failed.
        // Reconcile the facade even when BlueZ emits no property event, while
        // preserving the teardown error and the retained lease/target for retry.
        _emitConnectionState(
          deviceId,
          BlueConnectionState.disconnected,
          BleStatus.success,
        );
      }
      rethrow;
    } finally {
      _disconnecting.remove(deviceId);
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
    _getDeviceOrThrow(deviceId, operation: 'openL2cap');
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
    return _client.adapters.firstWhereOrNull(
      (adapter) =>
          adapter.powered &&
          (adapterAddress == null || adapter.address == adapterAddress),
    );
  }

  BlueZDevice _getDeviceOrThrow(String deviceId, {String? operation}) {
    final device =
        _ownedDevices[deviceId] ??
        _devices[deviceId] ??
        _client.devices.firstWhereOrNull(
          (d) => d.address == deviceId && _matchesAdapter(d),
        );
    if (device == null ||
        (adapterAddress != null && device.adapter.address != adapterAddress)) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.notFound,
        deviceId: deviceId,
        operation: operation,
        message: 'Bluetooth device $deviceId was not found.',
      );
    }
    _devices[deviceId] = device;
    return device;
  }

  bool _matchesAdapter(BlueZDevice device) =>
      adapterAddress == null || device.adapter.address == adapterAddress;

  Future<void> _detachDevice(
    BlueZDevice device, {
    required Future<void> Function() onLastClient,
    bool retireConnect = true,
  }) async {
    final deviceId = device.address;
    // Native events join the complete explicit transition, including a pending
    // StopNotify. They must not retire a reconnect waiting behind that cleanup.
    final disconnecting = _disconnecting[deviceId];
    if (retireConnect && disconnecting != null) return disconnecting;
    if (!identical(_ownedDevices[deviceId], device)) return;
    // A fresh connect must acquire membership, even if the retired native
    // Connect reply is still outstanding. Failed detach remains retryable too.
    await _connectionOwnership.detach(
      deviceId,
      onLastClient: onLastClient,
      onStart: retireConnect ? () => _connecting.remove(deviceId) : null,
    );
    if (!_connectionOwnership.owns(deviceId) &&
        identical(_ownedDevices[deviceId], device)) {
      _ownedDevices.remove(deviceId);
    }
  }

  Future<void> _ensureConnectedDevice(
    BlueZDevice device, {
    void Function()? checkCurrent,
  }) async {
    checkCurrent?.call();
    if (device.connected) {
      await _watchDeviceProperties(device, checkCurrent: checkCurrent);
      return;
    }

    try {
      await device.connect();
    } on BlueZAlreadyConnectedException {
      // Already connected, nothing to do.
    } on BlueZInProgressException {
      checkCurrent?.call();
      await _waitForConnected(device);
    }

    checkCurrent?.call();
    await _waitForConnected(device);
    checkCurrent?.call();
    await _watchDeviceProperties(device, checkCurrent: checkCurrent);
  }

  Future<void> _watchDeviceProperties(
    BlueZDevice device, {
    void Function()? checkCurrent,
  }) async {
    final deviceId = device.address;
    checkCurrent?.call();
    await _cancelMappedSubscription(_devicePropertySubscriptions, deviceId);
    checkCurrent?.call();
    _gattSession.watchDevice(device);

    final subscription = device.propertiesChanged.listen(
      (properties) {
        final owned = _ownedDevices[deviceId];
        if (owned != null && !identical(owned, device)) return;
        if (properties.contains('Connected')) {
          final state = device.connected
              ? BlueConnectionState.connected
              : BlueConnectionState.disconnected;
          _emitConnectionState(deviceId, state, BleStatus.success);
          if (!device.connected) {
            _observeBackgroundOperation(
              _detachDevice(device, onLastClient: () async {}),
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

    await _gattSession.clearDevice(deviceId);
    await _scanSession.removeDevice(deviceId);
    await _cancelMappedSubscription(_devicePropertySubscriptions, deviceId);
    // The native observer can emit while earlier cleanup is suspended. Forget
    // its state only after it is retired, so terminal disconnect replay cannot
    // be suppressed for a facade request that joined after that native event.
    _lastConnectionState.remove(deviceId);
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

/// Snapshot of a Linux adapter's identity and power state.
class QuickBlueLinuxAdapter {
  const QuickBlueLinuxAdapter({required this.address, required this.powered});
  final String address;
  final bool powered;
}
