import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models.dart';
import 'bluetooth_device.dart';
import 'callbacks.dart';
import 'characteristic_lifecycle.dart';
import 'connection_lifecycle.dart';
import 'quick_blue_exception.dart';
import 'scan_lifecycle.dart';
import 'service_discovery_lifecycle.dart';
import 'unimplemented_quick_blue_platform.dart';

/// Platform interface for `quick_blue` implementations.
abstract class QuickBluePlatform extends PlatformInterface {
  QuickBluePlatform() : super(token: _token);

  static final Object _token = Object();

  static QuickBluePlatform _instance = UnimplementedQuickBluePlatform();

  /// The active platform implementation.
  static QuickBluePlatform get instance => _instance;

  /// Sets the active platform implementation.
  static set instance(QuickBluePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Configures platform behavior before starting Bluetooth work.
  ///
  /// Call this before other `QuickBlue` APIs. Platforms that do not support a
  /// requested option may ignore it when there is no native equivalent.
  Future<void> configure({bool maintainState = false}) async {}

  /// Returns whether Bluetooth is currently powered on and usable.
  Future<bool> isBluetoothAvailable();

  BlueBluetoothState? _latestBluetoothState;
  Stream<BlueBluetoothState>? _bluetoothStateStream;
  StreamController<BlueBluetoothState>? _bluetoothStateController;
  StreamSubscription<BlueBluetoothState>? _bluetoothStateSubscription;

  /// Emits the latest known Bluetooth state to each listener, then emits later
  /// state changes when the platform supports live state updates.
  ///
  /// Platforms without live state monitoring may emit only the current
  /// availability snapshot.
  Stream<BlueBluetoothState> get bluetoothStateStream {
    return _bluetoothStateStream ??= Stream.multi((controller) {
      var lastDelivered = _latestBluetoothState;
      if (lastDelivered != null) {
        controller.add(lastDelivered);
      }

      final subscription = _sharedBluetoothStateEvents.listen((state) {
        if (state == lastDelivered) {
          return;
        }
        lastDelivered = state;
        controller.add(state);
      }, onError: controller.addError);
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  /// Raw platform Bluetooth state events.
  ///
  /// Platform implementations should override this instead of
  /// [bluetoothStateStream] so all listeners share the same replay and
  /// concurrent-listener behavior.
  Stream<BlueBluetoothState> get bluetoothStateEvents async* {
    yield await isBluetoothAvailable()
        ? BlueBluetoothState.poweredOn
        : BlueBluetoothState.poweredOff;
  }

  Stream<BlueBluetoothState> get _sharedBluetoothStateEvents {
    final existing = _bluetoothStateController;
    if (existing != null) {
      return existing.stream;
    }

    final controller = StreamController<BlueBluetoothState>.broadcast(
      onListen: _startBluetoothStateEvents,
      onCancel: _stopBluetoothStateEvents,
    );
    _bluetoothStateController = controller;
    return controller.stream;
  }

  void _startBluetoothStateEvents() {
    if (_bluetoothStateSubscription != null) {
      return;
    }

    var completedSynchronously = false;
    final subscription = bluetoothStateEvents.listen(
      (state) {
        _latestBluetoothState = state;
        _bluetoothStateController?.add(state);
      },
      onError: (Object error, StackTrace stackTrace) {
        _bluetoothStateController?.addError(error, stackTrace);
      },
      onDone: () {
        if (_bluetoothStateSubscription == null) {
          completedSynchronously = true;
        } else {
          _bluetoothStateSubscription = null;
        }
      },
    );
    _bluetoothStateSubscription = completedSynchronously ? null : subscription;
  }

  Future<void> _stopBluetoothStateEvents() async {
    final subscription = _bluetoothStateSubscription;
    _bluetoothStateSubscription = null;
    await subscription?.cancel();
  }

  /// Starts the platform scan lifecycle.
  ///
  /// Implementations should apply supported [scanFilter] and [scanOptions]
  /// natively. Any filter that cannot be applied during discovery must be
  /// applied before emitting results through [scanResultStream].
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  });

  /// Stops the platform scan lifecycle.
  ///
  /// Called after the last managed scan listener is canceled.
  Future<void> stopScan();

  /// Raw scan results from the platform scan lifecycle.
  ///
  /// This stream does not manage scan ownership by itself; use [scanResults]
  /// for automatic start/stop behavior.
  Stream<BlueScanResult> get scanResultStream;

  late final _scanLifecycleCoordinator = ScanLifecycleCoordinator(
    startScan: ({required scanFilter, required scanOptions}) =>
        startScan(scanFilter: scanFilter, scanOptions: scanOptions),
    stopScan: stopScan,
    scanResultStream: () => scanResultStream,
  );

  /// Starts scanning on listen and stops when the stream is canceled.
  ///
  /// Concurrent listeners must use the same scan configuration. RSSI,
  /// service-data filtering, and duplicate suppression are also applied in
  /// Dart for consistent behavior across platforms.
  Stream<BlueScanResult> scanResults({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) {
    return _scanLifecycleCoordinator.results(
      scanFilter: scanFilter,
      scanOptions: scanOptions,
    );
  }

  /// Scans for device handles.
  ///
  /// Advertisement payloads are dropped; use [scanResults] when those are
  /// needed.
  Stream<BluetoothDevice> scan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) {
    return scanResults(
      scanFilter: scanFilter,
      scanOptions: scanOptions,
    ).map((result) => device(result.deviceId));
  }

  /// Legacy stream of scanned device handles.
  Stream<BluetoothDevice> get bluetoothDeviceStream {
    return scan();
  }

  /// Returns a handle for a platform Bluetooth device identifier.
  BluetoothDevice device(String deviceId) {
    return BluetoothDevice.internal(
      deviceId: deviceId,
      platform: this,
      discoverServices: _serviceDiscoveryLifecycleCoordinator.discover,
    );
  }

  /// Returns handles for devices already connected at the system level.
  ///
  /// Some platforms, notably CoreBluetooth, require service UUIDs to look up
  /// connected peripherals.
  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  });

  /// Connects to [deviceId].
  Future<void> connect(String deviceId);

  /// Disconnects from [deviceId].
  Future<void> disconnect(String deviceId);

  /// Returns the current pairing/bonding state for [deviceId].
  Future<BluetoothBondState> bondState(String deviceId);

  final StreamController<BluetoothBondStateChange> _bondStateController =
      StreamController<BluetoothBondStateChange>.broadcast();

  /// Pairing/bonding state transitions for all devices.
  ///
  /// Platforms without observable bond state do not emit events. Use
  /// [bondState] for a current-state snapshot.
  Stream<BluetoothBondStateChange> get bondStateStream {
    return _bondStateController.stream;
  }

  /// Reports a native pairing/bonding state transition.
  void handleBondStateChanged(
    String deviceId,
    BluetoothBondState state,
    BluetoothBondState previousState,
  ) {
    _bondStateController.add(
      BluetoothBondStateChange(
        deviceId: deviceId,
        state: state,
        previousState: previousState,
      ),
    );
  }

  /// Starts pairing/bonding with [deviceId].
  Future<void> pair(String deviceId);

  /// Attempts the active platform's best recovery for a security failure.
  ///
  /// Platform implementations may override this hook when their operating
  /// system has a recovery mechanism beyond normal pairing.
  Future<QuickBlueSecurityRecoveryResult> performSecurityRecovery(
    String deviceId,
    QuickBlueSecurityException error,
  ) async {
    BluetoothBondState state;
    try {
      state = await bondState(deviceId);
    } on QuickBlueException catch (bondError) {
      if (bondError.code == QuickBlueErrorCode.unsupported) {
        return QuickBlueSecurityRecoveryResult.unsupported;
      }
      return QuickBlueSecurityRecoveryResult.userActionRequired;
    } on Object {
      return QuickBlueSecurityRecoveryResult.userActionRequired;
    }

    switch (state) {
      case BluetoothBondState.notBonded:
      case BluetoothBondState.bonding:
        try {
          await pair(deviceId);
          return QuickBlueSecurityRecoveryResult.recovered;
        } on QuickBlueException catch (pairError) {
          if (pairError.code == QuickBlueErrorCode.unsupported) {
            return QuickBlueSecurityRecoveryResult.unsupported;
          }
          return QuickBlueSecurityRecoveryResult.userActionRequired;
        } on Object {
          return QuickBlueSecurityRecoveryResult.userActionRequired;
        }
      case BluetoothBondState.bonded:
        return QuickBlueSecurityRecoveryResult.userActionRequired;
      case BluetoothBondState.unknown:
        return QuickBlueSecurityRecoveryResult.unsupported;
    }
  }

  /// Returns whether companion-device association is supported.
  Future<bool> isCompanionAssociationSupported();

  /// Starts a companion-device association request.
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  );

  /// Removes the association with [associationId].
  Future<void> companionDisassociate(int associationId);

  /// Returns current companion-device associations.
  Future<List<CompanionAssociation>> getCompanionAssociations();

  /// Returns whether Apple AccessorySetupKit is available.
  Future<bool> isAppleAccessorySetupSupported() async => false;

  /// Presents the Apple AccessorySetupKit picker.
  Future<AppleAccessory?> showAppleAccessoryPicker(
    List<AppleAccessoryPickerItem> items,
  ) {
    return Future<AppleAccessory?>.error(
      const QuickBlueException(
        code: QuickBlueErrorCode.unsupported,
        operation: 'showAppleAccessoryPicker',
        message: 'Apple AccessorySetupKit is not supported on this platform.',
      ),
    );
  }

  /// Returns Bluetooth accessories authorized through AccessorySetupKit.
  Future<List<AppleAccessory>> getAppleAccessories() {
    return Future<List<AppleAccessory>>.error(
      const QuickBlueException(
        code: QuickBlueErrorCode.unsupported,
        operation: 'getAppleAccessories',
        message: 'Apple AccessorySetupKit is not supported on this platform.',
      ),
    );
  }

  /// Removes the AccessorySetupKit accessory with [deviceId].
  Future<void> removeAppleAccessory(String deviceId) {
    return Future<void>.error(
      const QuickBlueException(
        code: QuickBlueErrorCode.unsupported,
        operation: 'removeAppleAccessory',
        message: 'Apple AccessorySetupKit is not supported on this platform.',
      ),
    );
  }

  final StreamController<BluetoothConnectionStateChange>
  _connectionStateController =
      StreamController<BluetoothConnectionStateChange>.broadcast();
  late final _connectionLifecycleCoordinator = ConnectionLifecycleCoordinator(
    connect: connect,
    disconnect: disconnect,
    connectionStateStream: () => connectionStateStream,
  );
  final _securityRecoveryOperations =
      <String, Future<QuickBlueSecurityRecoveryResult>>{};

  /// Coordinates one security recovery attempt per device.
  Future<QuickBlueSecurityRecoveryResult> recoverSecurity(
    String deviceId,
    QuickBlueSecurityException error,
  ) {
    final activeRecovery = _securityRecoveryOperations[deviceId];
    if (activeRecovery != null) {
      return activeRecovery;
    }

    late final Future<QuickBlueSecurityRecoveryResult> recovery;
    recovery = () async {
      try {
        return await performSecurityRecovery(deviceId, error);
      } finally {
        if (identical(_securityRecoveryOperations[deviceId], recovery)) {
          _securityRecoveryOperations.remove(deviceId);
        }
      }
    }();
    _securityRecoveryOperations[deviceId] = recovery;
    return recovery;
  }

  /// Runs [operation], attempts security recovery once, and retries on success.
  Future<T> runWithSecurityRecovery<T>(
    String deviceId,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on QuickBlueSecurityException catch (error, stackTrace) {
      final recoveryResult = await recoverSecurity(deviceId, error);
      if (recoveryResult != QuickBlueSecurityRecoveryResult.recovered) {
        Error.throwWithStackTrace(
          error.withRecoveryResult(recoveryResult),
          stackTrace,
        );
      }

      try {
        return await operation();
      } on QuickBlueSecurityException catch (retryError, retryStackTrace) {
        Error.throwWithStackTrace(
          retryError.withRecoveryResult(
            QuickBlueSecurityRecoveryResult.userActionRequired,
          ),
          retryStackTrace,
        );
      }
    }
  }

  /// Connection state changes for all devices.
  Stream<BluetoothConnectionStateChange> get connectionStateStream {
    return _connectionStateController.stream;
  }

  /// Connects to [deviceId] and waits for the connected state event.
  ///
  /// A second connection operation for the same device is rejected while the
  /// first is pending so failure events cannot be consumed by the wrong call.
  Future<void> connectDevice(String deviceId) {
    return _connectionLifecycleCoordinator.connectDevice(deviceId);
  }

  /// Disconnects from [deviceId] and waits for the disconnected state event.
  ///
  /// A pending connect for the same device is cancelled first. Other
  /// overlapping connection operations are rejected.
  Future<void> disconnectDevice(String deviceId) {
    return _connectionLifecycleCoordinator.disconnectDevice(deviceId);
  }

  OnConnectionChanged? _onConnectionChanged;

  /// Legacy global connection callback.
  OnConnectionChanged? get onConnectionChanged => _handleConnectionChanged;

  /// Sets the legacy global connection callback.
  set onConnectionChanged(OnConnectionChanged? handler) {
    _onConnectionChanged = handler;
  }

  /// Starts service discovery for [deviceId].
  ///
  /// Implementations should report each service and then call
  /// [onServiceDiscoveryComplete].
  Future<void> discoverServices(String deviceId);

  late final _serviceDiscoveryLifecycleCoordinator =
      ServiceDiscoveryLifecycleCoordinator(startDiscovery: discoverServices);

  /// Discovered services for all devices.
  ///
  /// Events may arrive before discovery completes.
  Stream<BluetoothService> get serviceDiscoveryStream {
    return _serviceDiscoveryLifecycleCoordinator.serviceStream;
  }

  /// Emits a device identifier when service discovery completes.
  Stream<String> get serviceDiscoveryCompleteStream {
    return _serviceDiscoveryLifecycleCoordinator.completeStream;
  }

  OnServiceDiscovered? _onServiceDiscovered;

  /// Legacy global service discovery callback.
  OnServiceDiscovered? get onServiceDiscovered {
    return (deviceId, serviceId, characteristicIds) {
      _handleServiceDiscovered(deviceId, serviceId, characteristicIds, null);
    };
  }

  /// Sets the legacy global service discovery callback.
  set onServiceDiscovered(OnServiceDiscovered? handler) {
    _onServiceDiscovered = handler;
  }

  /// Callback used by platform code to report service discovery completion.
  OnServiceDiscoveryComplete get onServiceDiscoveryComplete {
    return _handleServiceDiscoveryComplete;
  }

  /// Enables or disables notifications or indications for a characteristic.
  ///
  /// The returned future should complete after the platform has accepted or
  /// rejected the notification state change.
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  );

  late final _characteristicLifecycleCoordinator =
      CharacteristicLifecycleCoordinator(
        setNotifiable: setNotifiable,
        setNotifiableWithSecurityRecovery:
            (deviceId, service, characteristic, bleInputProperty) {
              return runWithSecurityRecovery(
                deviceId,
                () => setNotifiable(
                  deviceId,
                  service,
                  characteristic,
                  bleInputProperty,
                ),
              );
            },
      );

  /// Characteristic value updates for all devices.
  Stream<BluetoothCharacteristicValue> get characteristicValueStream {
    return _characteristicLifecycleCoordinator.valueStream;
  }

  /// Value updates for one characteristic.
  ///
  /// This avoids per-packet global stream filtering for hot notification paths.
  Stream<Uint8List> characteristicValueStreamFor(
    String deviceId,
    String service,
    String characteristic,
  ) {
    return _characteristicLifecycleCoordinator.valueStreamFor(
      deviceId,
      service,
      characteristic,
    );
  }

  /// Enables notifications while the returned stream has listeners.
  ///
  /// Streams for the same characteristic share one native notification
  /// lifecycle. The first listener enables updates and the last listener to
  /// cancel disables them.
  Stream<Uint8List> characteristicNotifications(
    String deviceId,
    String service,
    String characteristic, {
    BleInputProperty bleInputProperty = BleInputProperty.notification,
  }) {
    return _characteristicLifecycleCoordinator.notifications(
      deviceId,
      service,
      characteristic,
      bleInputProperty: bleInputProperty,
    );
  }

  OnValueChanged? _onValueChanged;

  /// Legacy global characteristic value callback.
  OnValueChanged? get onValueChanged {
    return (deviceId, characteristicId, value) {
      _handleValueChanged(deviceId, '', characteristicId, value);
    };
  }

  /// Sets the legacy global characteristic value callback.
  set onValueChanged(OnValueChanged? handler) {
    _onValueChanged = handler;
  }

  /// Starts a characteristic read.
  ///
  /// Implementations should report the value through
  /// [handleCharacteristicValueChanged].
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  );

  /// Reads a characteristic value and completes with the value bytes.
  ///
  /// Platform implementations may override this to return native read results
  /// directly. The default preserves the older [readValue] event contract.
  Future<Uint8List> readCharacteristicValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    final values = StreamQueue(
      characteristicValueStreamFor(deviceId, service, characteristic),
    );

    try {
      await readValue(deviceId, service, characteristic);
      return await values.next;
    } finally {
      await values.cancel();
    }
  }

  /// Writes a characteristic value.
  ///
  /// Completion should reflect the platform write result when available.
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  );

  /// Requests or returns the negotiated MTU, depending on platform support.
  Future<int> requestMtu(String deviceId, int expectedMtu);

  /// Opens a BLE L2CAP socket for [deviceId].
  Future<BleL2capSocket> openL2cap(String deviceId, int psm);

  void _handleConnectionChanged(
    String deviceId,
    BlueConnectionState state,
    BleStatus status, [
    QuickBlueException? error,
  ]) {
    if (state == BlueConnectionState.disconnected) {
      _serviceDiscoveryLifecycleCoordinator.handleDisconnected(deviceId);
    }
    _connectionStateController.add(
      BluetoothConnectionStateChange(
        deviceId: deviceId,
        state: state,
        status: status,
        error: error,
      ),
    );
    _onConnectionChanged?.call(deviceId, state, status);
  }

  /// Reports a connection state and optional structured platform failure.
  void handleConnectionStateChanged(
    String deviceId,
    BlueConnectionState state,
    BleStatus status, {
    QuickBlueException? error,
  }) {
    _handleConnectionChanged(deviceId, state, status, error);
  }

  void _handleServiceDiscovered(
    String deviceId,
    String serviceId,
    List<String> characteristicIds,
    List<BluetoothCharacteristicInfo>? characteristicDetails,
  ) {
    _serviceDiscoveryLifecycleCoordinator.handleDiscovered(
      deviceId,
      serviceId,
      characteristicIds,
      characteristicDetails,
    );
    _onServiceDiscovered?.call(deviceId, serviceId, characteristicIds);
  }

  void _handleServiceDiscoveryComplete(String deviceId) {
    _serviceDiscoveryLifecycleCoordinator.handleComplete(deviceId);
  }

  void _handleValueChanged(
    String deviceId,
    String serviceId,
    String characteristicId,
    Uint8List value,
  ) {
    _characteristicLifecycleCoordinator.handleValueChanged(
      deviceId,
      serviceId,
      characteristicId,
      value,
    );
    _onValueChanged?.call(deviceId, characteristicId, value);
  }

  /// Reports a discovered service from platform wrapper code.
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

  /// Reports a characteristic value from platform wrapper code.
  void handleCharacteristicValueChanged(
    String deviceId,
    String serviceId,
    String characteristicId,
    Uint8List value,
  ) {
    _handleValueChanged(deviceId, serviceId, characteristicId, value);
  }
}
