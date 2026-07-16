import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models.dart';
import 'bluetooth_uuid.dart';
import 'bluetooth_device.dart';
import 'callbacks.dart';
import 'quick_blue_exception.dart';
import 'scan_filter.dart';
import 'service_discovery_event.dart';
import 'unimplemented_quick_blue_platform.dart';

class _ConnectionOperation {
  _ConnectionOperation(this.name);

  final String name;
  final cancellation = _ConnectionOperationCancellation();
  late final Future<void> completed;
}

class _ConnectionOperationCancellation {
  final _completer = Completer<void>();

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  Future<T> untilCancelled<T>(
    Future<T> operation, {
    required QuickBlueException error,
  }) {
    return Future.any<T>(<Future<T>>[
      operation,
      _completer.future.then<T>((_) => throw error),
    ]);
  }
}

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

  _ScanConfiguration? _activeScanConfiguration;
  var _activeScanListeners = 0;
  var _activeScanStarted = false;
  Future<void> _scanLifecycle = Future<void>.value();

  /// Starts scanning on listen and stops when the stream is canceled.
  ///
  /// Concurrent listeners must use the same scan configuration. RSSI,
  /// service-data filtering, and duplicate suppression are also applied in
  /// Dart for consistent behavior across platforms.
  Stream<BlueScanResult> scanResults({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) async* {
    final configuration = _ScanConfiguration(
      scanFilter: _copyScanFilter(scanFilter),
      scanOptions: _copyScanOptions(scanOptions),
    );

    await _acquireScan(configuration);
    try {
      final seenDeviceIds = <String>{};
      yield* scanResultStream.where(
        (result) =>
            _matchesScanConfiguration(result, configuration, seenDeviceIds),
      );
    } finally {
      await _releaseScan();
    }
  }

  bool _matchesScanConfiguration(
    BlueScanResult result,
    _ScanConfiguration configuration,
    Set<String> seenDeviceIds,
  ) {
    if (!matchesServiceDataFilter(
      configuration.scanFilter.serviceData,
      result.serviceData,
    )) {
      return false;
    }

    final rssi = configuration.scanFilter.rssi;
    if (rssi != null && result.rssi < rssi) {
      return false;
    }

    if (configuration.scanOptions.allowDuplicates == false &&
        !seenDeviceIds.add(result.deviceId)) {
      return false;
    }

    return true;
  }

  Future<void> _acquireScan(_ScanConfiguration configuration) {
    return _queueScanLifecycle(() async {
      final activeConfiguration = _activeScanConfiguration;
      if (_activeScanListeners == 0) {
        _activeScanConfiguration = configuration;
        try {
          await startScan(
            scanFilter: configuration.scanFilter,
            scanOptions: configuration.scanOptions,
          );
          _activeScanStarted = true;
        } catch (_) {
          _activeScanConfiguration = null;
          rethrow;
        }
      } else if (activeConfiguration == null ||
          activeConfiguration != configuration) {
        throw QuickBlueException(
          code: QuickBlueErrorCode.invalidState,
          operation: 'scanResults',
          message:
              'Cannot start scanning with a different scan configuration while '
              'another scanResults stream is active.',
        );
      }

      _activeScanListeners++;
    });
  }

  ScanFilter _copyScanFilter(ScanFilter scanFilter) {
    return ScanFilter(
      serviceUuids: scanFilter.serviceUuids,
      serviceData: scanFilter.serviceData,
      manufacturerData: scanFilter.manufacturerData,
      rssi: scanFilter.rssi,
    );
  }

  ScanOptions _copyScanOptions(ScanOptions scanOptions) {
    return ScanOptions(
      allowDuplicates: scanOptions.allowDuplicates,
      scanMode: scanOptions.scanMode,
      android: scanOptions.android,
      darwin: DarwinScanOptions(
        allowDuplicates: scanOptions.darwin.allowDuplicates,
        solicitedServiceUuids: scanOptions.darwin.solicitedServiceUuids,
      ),
      linux: scanOptions.linux,
      windows: scanOptions.windows,
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

      _activeScanConfiguration = null;
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
      discoverServices: _discoverServicesForDevice,
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

  final StreamController<BluetoothConnectionStateChange>
  _connectionStateController =
      StreamController<BluetoothConnectionStateChange>.broadcast();
  final _activeConnectionOperations = <String, _ConnectionOperation>{};
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
    return _runConnectionOperation(
      deviceId: deviceId,
      operationName: 'connect',
      targetState: BlueConnectionState.connected,
      failureMessage: 'Failed to connect to Bluetooth device $deviceId.',
      operation: (cancellation) =>
          _connectWhenAvailable(deviceId, cancellation),
    );
  }

  Future<void> _connectWhenAvailable(
    String deviceId,
    _ConnectionOperationCancellation cancellation,
  ) async {
    const busyTimeout = Duration(seconds: 30);
    final stopwatch = Stopwatch()..start();
    while (true) {
      try {
        await cancellation.untilCancelled(
          connect(deviceId),
          error: _cancelledConnectionException(deviceId, 'connect'),
        );
        return;
      } on QuickBlueException catch (error) {
        if (error.code != QuickBlueErrorCode.deviceBusy) {
          rethrow;
        }
        if (stopwatch.elapsed >= busyTimeout) {
          throw QuickBlueException(
            code: QuickBlueErrorCode.deviceBusy,
            operation: 'connect',
            deviceId: deviceId,
            details: busyTimeout,
            message:
                'Timed out waiting for the shared connection to $deviceId '
                'to finish disconnecting.',
          );
        }
        await cancellation.untilCancelled(
          Future<void>.delayed(const Duration(milliseconds: 100)),
          error: _cancelledConnectionException(deviceId, 'connect'),
        );
      }
    }
  }

  /// Disconnects from [deviceId] and waits for the disconnected state event.
  ///
  /// A pending connect for the same device is cancelled first. Other
  /// overlapping connection operations are rejected.
  Future<void> disconnectDevice(String deviceId) async {
    final activeOperation = _activeConnectionOperations[deviceId];
    if (activeOperation?.name == 'connect') {
      activeOperation!.cancellation.cancel();
      try {
        await activeOperation.completed;
      } on Object {
        // The disconnect is the authoritative cleanup request even if the
        // superseded connect happened to fail while cancellation was racing.
      }
    }

    return _runConnectionOperation(
      deviceId: deviceId,
      operationName: 'disconnect',
      targetState: BlueConnectionState.disconnected,
      failureMessage: 'Failed to disconnect Bluetooth device $deviceId.',
      operation: (_) => disconnect(deviceId),
    );
  }

  Future<void> _runConnectionOperation({
    required String deviceId,
    required String operationName,
    required BlueConnectionState targetState,
    required String failureMessage,
    required Future<void> Function(
      _ConnectionOperationCancellation cancellation,
    )
    operation,
  }) {
    final activeOperation = _activeConnectionOperations[deviceId];
    if (activeOperation != null) {
      return Future<void>.error(
        QuickBlueException(
          code: QuickBlueErrorCode.invalidState,
          operation: operationName,
          deviceId: deviceId,
          details: activeOperation.name,
          message:
              'Cannot $operationName Bluetooth device $deviceId while '
              '${activeOperation.name} is pending.',
        ),
      );
    }
    final connectionOperation = _ConnectionOperation(operationName);
    _activeConnectionOperations[deviceId] = connectionOperation;
    connectionOperation.completed = _executeConnectionOperation(
      deviceId: deviceId,
      connectionOperation: connectionOperation,
      targetState: targetState,
      failureMessage: failureMessage,
      operation: operation,
    );
    return connectionOperation.completed;
  }

  Future<void> _executeConnectionOperation({
    required String deviceId,
    required _ConnectionOperation connectionOperation,
    required BlueConnectionState targetState,
    required String failureMessage,
    required Future<void> Function(
      _ConnectionOperationCancellation cancellation,
    )
    operation,
  }) async {
    final operationName = connectionOperation.name;
    final cancellation = connectionOperation.cancellation;

    final stateCompleter = Completer<BluetoothConnectionStateChange>();
    final stateSubscription = connectionStateStream
        .where(
          (event) =>
              event.deviceId == deviceId &&
              (event.status == BleStatus.failure || event.state == targetState),
        )
        .listen((state) {
          if (!stateCompleter.isCompleted) {
            stateCompleter.complete(state);
          }
        });

    try {
      final cancellationError = _cancelledConnectionException(
        deviceId,
        operationName,
      );
      await cancellation.untilCancelled(
        operation(cancellation),
        error: cancellationError,
      );
      final state = await cancellation.untilCancelled(
        stateCompleter.future,
        error: cancellationError,
      );
      if (state.status == BleStatus.failure) {
        if (state.error != null) {
          throw state.error!;
        }
        throw QuickBlueException(
          code: QuickBlueErrorCode.operationFailed,
          operation: operationName,
          deviceId: deviceId,
          details: state.status,
          message: failureMessage,
        );
      }
    } finally {
      await stateSubscription.cancel();
      if (_activeConnectionOperations[deviceId] == connectionOperation) {
        _activeConnectionOperations.remove(deviceId);
      }
    }
  }

  QuickBlueException _cancelledConnectionException(
    String deviceId,
    String operationName,
  ) {
    return QuickBlueException(
      code: QuickBlueErrorCode.cancelled,
      operation: operationName,
      deviceId: deviceId,
      message:
          '${operationName[0].toUpperCase()}${operationName.substring(1)} '
          'for Bluetooth device $deviceId was cancelled.',
    );
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

  final StreamController<BluetoothService> _serviceDiscoveryController =
      StreamController<BluetoothService>.broadcast();
  final StreamController<String> _serviceDiscoveryCompleteController =
      StreamController<String>.broadcast();
  final _serviceDiscoveryEventController =
      StreamController<ServiceDiscoveryEvent>.broadcast();
  final _pendingServiceDiscoveries = <String, Future<List<BluetoothService>>>{};

  /// Discovered services for all devices.
  ///
  /// Events may arrive before discovery completes.
  Stream<BluetoothService> get serviceDiscoveryStream {
    return _serviceDiscoveryController.stream;
  }

  /// Emits a device identifier when service discovery completes.
  Stream<String> get serviceDiscoveryCompleteStream {
    return _serviceDiscoveryCompleteController.stream;
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

  final StreamController<BluetoothCharacteristicValue>
  _characteristicValueController =
      StreamController<BluetoothCharacteristicValue>.broadcast();
  final _characteristicValueStreams =
      <_CharacteristicValueKey, StreamController<Uint8List>>{};
  final _activeNotifications = <_CharacteristicValueKey, _ActiveNotification>{};
  final _notificationLifecycles = <_CharacteristicValueKey, Future<void>>{};

  /// Characteristic value updates for all devices.
  Stream<BluetoothCharacteristicValue> get characteristicValueStream {
    return _characteristicValueController.stream;
  }

  /// Value updates for one characteristic.
  ///
  /// This avoids per-packet global stream filtering for hot notification paths.
  Stream<Uint8List> characteristicValueStreamFor(
    String deviceId,
    String service,
    String characteristic,
  ) {
    final key = _CharacteristicValueKey.fromParts(
      deviceId,
      service,
      characteristic,
    );
    final existing = _characteristicValueStreams[key];
    if (existing != null) {
      return existing.stream;
    }

    late StreamController<Uint8List> controller;
    controller = StreamController<Uint8List>.broadcast(
      onCancel: () {
        if (!controller.hasListener) {
          _characteristicValueStreams.remove(key);
        }
      },
    );
    _characteristicValueStreams[key] = controller;
    return controller.stream;
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
    late StreamSubscription<Uint8List> valueSubscription;
    late Future<void> setUpNotification;
    var valueSubscriptionCanceled = false;
    var acquired = false;
    final controller = StreamController<Uint8List>();

    Future<void> cancelValueSubscription() async {
      if (valueSubscriptionCanceled) {
        return;
      }
      valueSubscriptionCanceled = true;
      await valueSubscription.cancel();
    }

    controller.onListen = () {
      valueSubscription =
          characteristicValueStreamFor(
            deviceId,
            service,
            characteristic,
          ).listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
      valueSubscription.pause();
      setUpNotification = () async {
        try {
          await _acquireNotification(
            deviceId,
            service,
            characteristic,
            bleInputProperty,
          );
          acquired = true;
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
      if (acquired) {
        await _releaseNotification(deviceId, service, characteristic);
      }
    };

    return controller.stream;
  }

  Future<void> _acquireNotification(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    final key = _CharacteristicValueKey.fromParts(
      deviceId,
      service,
      characteristic,
    );
    return _queueNotificationLifecycle(key, () async {
      final active = _activeNotifications[key];
      if (active != null) {
        if (active.bleInputProperty != bleInputProperty) {
          throw QuickBlueException(
            code: QuickBlueErrorCode.invalidState,
            operation: 'notifications',
            deviceId: deviceId,
            serviceId: service,
            characteristicId: characteristic,
            message:
                'Cannot listen with ${bleInputProperty.value} while '
                '${active.bleInputProperty.value} is already active.',
          );
        }
        active.listenerCount++;
        return;
      }

      await runWithSecurityRecovery(
        deviceId,
        () =>
            setNotifiable(deviceId, service, characteristic, bleInputProperty),
      );
      _activeNotifications[key] = _ActiveNotification(bleInputProperty);
    });
  }

  Future<void> _releaseNotification(
    String deviceId,
    String service,
    String characteristic,
  ) {
    final key = _CharacteristicValueKey.fromParts(
      deviceId,
      service,
      characteristic,
    );
    return _queueNotificationLifecycle(key, () async {
      final active = _activeNotifications[key];
      if (active == null) {
        return;
      }
      active.listenerCount--;
      if (active.listenerCount != 0) {
        return;
      }

      _activeNotifications.remove(key);
      await setNotifiable(
        deviceId,
        service,
        characteristic,
        BleInputProperty.disabled,
      );
    });
  }

  Future<void> _queueNotificationLifecycle(
    _CharacteristicValueKey key,
    Future<void> Function() action,
  ) {
    final previous = _notificationLifecycles[key] ?? Future<void>.value();
    final next = previous.then((_) => action());
    final recovered = next.catchError((Object _) {});
    _notificationLifecycles[key] = recovered;
    recovered.then((_) {
      if (identical(_notificationLifecycles[key], recovered)) {
        _notificationLifecycles.remove(key);
      }
    });
    return next;
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

  Future<List<BluetoothService>> _discoverServicesForDevice(String deviceId) {
    final pending = _pendingServiceDiscoveries[deviceId];
    if (pending != null) {
      return pending;
    }

    late Future<List<BluetoothService>> discovery;
    discovery = () async {
      try {
        return await _runServiceDiscovery(deviceId);
      } finally {
        if (identical(_pendingServiceDiscoveries[deviceId], discovery)) {
          _pendingServiceDiscoveries.remove(deviceId);
        }
      }
    }();
    _pendingServiceDiscoveries[deviceId] = discovery;
    return discovery;
  }

  Future<List<BluetoothService>> _runServiceDiscovery(String deviceId) async {
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

      throw QuickBlueException(
        code: QuickBlueErrorCode.operationFailed,
        operation: 'discoverServices',
        deviceId: deviceId,
        message:
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
    _dispatchCharacteristicValue(
      _CharacteristicValueKey.fromParts(deviceId, serviceId, characteristicId),
      value,
    );
    if (serviceId.isEmpty) {
      _dispatchLegacyCharacteristicValue(deviceId, characteristicId, value);
    }

    if (_characteristicValueController.hasListener) {
      _characteristicValueController.add(
        BluetoothCharacteristicValue(
          deviceId: deviceId,
          serviceId: serviceId,
          characteristicId: characteristicId,
          value: value,
        ),
      );
    }
    _onValueChanged?.call(deviceId, characteristicId, value);
  }

  void _dispatchCharacteristicValue(
    _CharacteristicValueKey key,
    Uint8List value,
  ) {
    _characteristicValueStreams[key]?.add(value);
  }

  void _dispatchLegacyCharacteristicValue(
    String deviceId,
    String characteristicId,
    Uint8List value,
  ) {
    final characteristic = bluetoothUuidKey(characteristicId);
    for (final entry in _characteristicValueStreams.entries) {
      final key = entry.key;
      if (key.service.isNotEmpty &&
          key.deviceId == deviceId &&
          key.characteristic == characteristic) {
        entry.value.add(value);
      }
    }
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

class _ScanConfiguration {
  const _ScanConfiguration({
    required this.scanFilter,
    required this.scanOptions,
  });

  final ScanFilter scanFilter;
  final ScanOptions scanOptions;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _ScanConfiguration &&
            other.scanFilter == scanFilter &&
            other.scanOptions == scanOptions;
  }

  @override
  int get hashCode => Object.hash(scanFilter, scanOptions);
}

class _CharacteristicValueKey {
  const _CharacteristicValueKey({
    required this.deviceId,
    required this.service,
    required this.characteristic,
  });

  factory _CharacteristicValueKey.fromParts(
    String deviceId,
    String service,
    String characteristic,
  ) {
    return _CharacteristicValueKey(
      deviceId: deviceId,
      service: bluetoothUuidKey(service),
      characteristic: bluetoothUuidKey(characteristic),
    );
  }

  final String deviceId;
  final String service;
  final String characteristic;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _CharacteristicValueKey &&
            other.deviceId == deviceId &&
            other.service == service &&
            other.characteristic == characteristic;
  }

  @override
  int get hashCode => Object.hash(deviceId, service, characteristic);
}

class _ActiveNotification {
  _ActiveNotification(this.bleInputProperty);

  final BleInputProperty bleInputProperty;
  var listenerCount = 1;
}
