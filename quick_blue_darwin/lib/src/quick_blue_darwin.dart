import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart' as memory;
import 'package:objective_c/objective_c.dart' as objc;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'darwin_models.dart' as models;
import 'third_party/accessory_setup_kit.g.dart' as accessory;
import 'third_party/core_bluetooth.g.dart' as cb;
import 'third_party/quick_blue_dispatch.g.dart' as dispatch;

part 'darwin_ffi_api.dart';
part 'darwin_shared_api.dart';

Stream<T> _eventsWithHistory<T>(List<T> history, Stream<T> live) {
  return Stream<T>.multi((controller) {
    final snapshot = List<T>.of(history);
    final subscription = live.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    for (final event in snapshot) {
      controller.add(event);
    }
    controller.onCancel = subscription.cancel;
  });
}

class QuickBlueDarwin extends QuickBluePlatform {
  QuickBlueDarwin({DarwinApi? api}) {
    _api = api ?? _createDarwinApi(this);
  }

  late final DarwinApi _api;
  StreamSubscription<models.PlatformDarwinRestorationEvent>?
  _restorationEventSubscription;
  late final Stream<BlueBluetoothState> _bluetoothStateEvents = _api
      .bluetoothStateEvents
      .map((state) => state.toBlueBluetoothState());
  late final Stream<BlueScanResult> _scanResultStream = _api.scanResults
      .map(_scanResultFromPlatformResult)
      .where(_matchesActiveServiceDataFilter);
  Map<String, Uint8List>? _activeScanServiceData;

  bool _matchesActiveServiceDataFilter(BlueScanResult result) {
    return matchesServiceDataFilter(_activeScanServiceData, result.serviceData);
  }

  late final Stream<models.PlatformL2CapSocketEvent> _l2CapEventStream =
      _api.l2CapEvents;

  static void registerWith() {
    final platform = QuickBlueDarwin();
    QuickBluePlatform.instance = platform;
    platform._api.bootstrapIfEnabled();
    if (QuickBlueInstrumentation.observer
        is QuickBlueDarwinRestorationObserver) {
      platform.startObservingDarwinRestoration();
    }
  }

  void _ensureInitialized() {
    if (_restorationEventSubscription != null) return;
    _restorationEventSubscription = _api.restorationEvents.listen(
      _handleRestorationEvent,
      onError: (Object _, StackTrace _) {
        // Restoration telemetry must not affect Bluetooth behavior.
      },
    );
  }

  @override
  void startObservingDarwinRestoration() {
    _ensureInitialized();
  }

  void _handleRestorationEvent(models.PlatformDarwinRestorationEvent event) {
    QuickBlueInstrumentation.recordDarwinRestoration(
      QuickBlueDarwinRestorationEvent(
        restoredPeripheralCount: event.restoredPeripheralCount,
        disconnectedPeripheralCount: event.disconnectedPeripheralCount,
        connectingPeripheralCount: event.connectingPeripheralCount,
        connectedPeripheralCount: event.connectedPeripheralCount,
        disconnectingPeripheralCount: event.disconnectingPeripheralCount,
        unknownPeripheralCount: event.unknownPeripheralCount,
        scanningRestored: event.scanningRestored,
        restoredScanServiceCount: event.restoredScanServiceCount,
      ),
    );
  }

  @override
  Future<QuickBlueCapabilities> capabilities() async {
    return QuickBlueCapabilities(
      bonding: BluetoothBondingCapability.unsupported,
      mtu: BluetoothMtuCapability.readNegotiated,
      gattServiceChanges:
          BluetoothGattServiceChangeCapability.invalidatedServices,
      connectedDeviceLookup:
          BluetoothConnectedDeviceLookupCapability.requiresServiceUuids,
      supportsL2capSockets: true,
      supportsCompanionAssociation: false,
      supportsAppleAccessorySetup: await isAppleAccessorySetupSupported(),
    );
  }

  // This API remains Android-specific. Apple AccessorySetupKit is exposed
  // separately because its picker items and identifiers have different shapes.
  static const _companionUnsupported =
      'Companion device association is not supported on iOS/macOS '
      '(use QuickBlue.appleAccessorySetup on supported iOS versions).';

  static const _pairingUnsupported =
      'App-initiated Bluetooth LE pairing is not supported on iOS/macOS. '
      'CoreBluetooth pairs automatically when a protected attribute is used.';

  @override
  Future<void> configure({bool maintainState = false}) {
    _ensureInitialized();

    return _api.configure(
      models.PlatformDarwinConfiguration(maintainState: maintainState),
    );
  }

  @override
  Future<bool> isAppleAccessorySetupSupported() {
    _ensureInitialized();
    return _api.isAppleAccessorySetupSupported();
  }

  @override
  Future<AppleAccessory?> showAppleAccessoryPicker(
    List<AppleAccessoryPickerItem> items,
  ) async {
    _ensureInitialized();
    final accessory = await _api.showAppleAccessoryPicker(
      items.map(_toPlatformAppleAccessoryPickerItem).toList(growable: false),
    );
    return accessory == null ? null : _toAppleAccessory(accessory);
  }

  @override
  Future<List<AppleAccessory>> getAppleAccessories() async {
    _ensureInitialized();
    final accessories = await _api.getAppleAccessories();
    return accessories.map(_toAppleAccessory).toList(growable: false);
  }

  @override
  Future<void> removeAppleAccessory(String deviceId) {
    _ensureInitialized();
    return _api.removeAppleAccessory(deviceId);
  }

  @override
  Future<bool> isCompanionAssociationSupported() async => false;

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'companionAssociate',
      message: _companionUnsupported,
    );
  }

  @override
  Future<void> companionDisassociate(int associationId) {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'companionDisassociate',
      message: _companionUnsupported,
    );
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'getCompanionAssociations',
      message: _companionUnsupported,
    );
  }

  @override
  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  }) async {
    _ensureInitialized();

    final peripherals = await _api.getConnectedPeripherals(serviceUuids);
    return peripherals
        .map((peripheral) => device(peripheral.id))
        .toList(growable: false);
  }

  @override
  Future<void> connect(String deviceId) {
    _ensureInitialized();
    return _api.connect(deviceId);
  }

  @override
  Future<void> disconnect(String deviceId) {
    _ensureInitialized();

    return _api.disconnect(deviceId);
  }

  @override
  Future<BluetoothBondState> bondState(String deviceId) async {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'bondState',
      message: _pairingUnsupported,
    );
  }

  @override
  Future<void> pair(String deviceId) {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'pair',
      message: _pairingUnsupported,
    );
  }

  @override
  Future<QuickBlueSecurityRecoveryResult> performSecurityRecovery(
    String deviceId,
    QuickBlueSecurityException error,
  ) async {
    if (error.reason ==
        QuickBlueSecurityErrorReason.peerRemovedPairingInformation) {
      return QuickBlueSecurityRecoveryResult.userActionRequired;
    }
    // CoreBluetooth owns pairing and encryption negotiation. Retrying the
    // rejected operation gives it one bounded opportunity to renegotiate.
    return QuickBlueSecurityRecoveryResult.recovered;
  }

  @override
  Future<void> discoverServices(String deviceId) {
    _ensureInitialized();

    return _api.discoverServices(deviceId);
  }

  @override
  Future<bool> isBluetoothAvailable() {
    _ensureInitialized();

    return _api.isBluetoothAvailable();
  }

  @override
  Stream<BlueBluetoothState> get bluetoothStateEvents {
    _ensureInitialized();

    return _bluetoothStateEvents;
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) async {
    _ensureInitialized();
    final result = Completer<models.PlatformL2CapSocketEvent>();
    final subscription = _l2CapEventStream.listen((event) {
      if (event.deviceId == deviceId &&
          (event.opened == true ||
              event.error != null ||
              event.closed == true) &&
          !result.isCompleted) {
        result.complete(event);
      }
    });
    models.PlatformL2CapSocketEvent event;
    try {
      await _api.openL2cap(deviceId, psm);
      event = await result.future.timeout(const Duration(seconds: 5));
    } finally {
      await subscription.cancel();
    }
    if (event.opened != true) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.operationFailed,
        operation: 'openL2cap',
        deviceId: deviceId,
        message: event.error ?? 'The L2CAP channel closed before it opened.',
      );
    }

    return BleL2capSocket(
      sink: _L2capSink(api: _api, deviceId: deviceId),
      stream: _l2CapEventStream
          .where((event) => event.deviceId == deviceId)
          .map(_l2capEventFromPlatformEvent),
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
  ) {
    _ensureInitialized();

    return _runDarwinGattOperation(
      operation: 'readValue',
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      action: () => _api.readValue(deviceId, service, characteristic),
    );
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    _ensureInitialized();

    return _api.requestMtu(deviceId, expectedMtu);
  }

  @override
  Stream<BlueScanResult> get scanResultStream => _scanResultStream;

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    _ensureInitialized();

    return _runDarwinGattOperation(
      operation: 'setNotifiable',
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      action: () => _api.setNotifiable(
        deviceId,
        service,
        characteristic,
        bleInputProperty.toPlatformBleInputProperty(),
      ),
    );
  }

  @override
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) async {
    _ensureInitialized();
    _activeScanServiceData = scanFilter.serviceData;

    final serviceUuids = scanFilter.serviceUuids.isEmpty
        ? null
        : scanFilter.serviceUuids;
    final manufacturerData = scanFilter.manufacturerData?.isEmpty == true
        ? null
        : scanFilter.manufacturerData;

    try {
      await _api.startScan(
        serviceUuids: serviceUuids,
        manufacturerData: manufacturerData,
        rssi: scanFilter.rssi,
        options: scanOptions.toPlatformDarwinScanOptions(),
      );
    } catch (_) {
      _activeScanServiceData = null;
      rethrow;
    }
  }

  @override
  Future<void> stopScan() async {
    _ensureInitialized();

    try {
      await _api.stopScan();
    } finally {
      _activeScanServiceData = null;
    }
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    _ensureInitialized();

    return _runDarwinGattOperation(
      operation: 'writeValue',
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      action: () => _api.writeValue(
        deviceId,
        service,
        characteristic,
        value,
        bleOutputProperty.toPlatformBleOutputProperty(),
      ),
    );
  }
}

Future<T> _runDarwinGattOperation<T>({
  required String operation,
  required String deviceId,
  required String serviceId,
  required String characteristicId,
  required Future<T> Function() action,
}) async {
  try {
    return await action();
  } on PlatformException catch (error, stackTrace) {
    final details = error.details;
    if (details is Map<Object?, Object?>) {
      final nativeDomain = details['domain'];
      final nativeCode = details['code'];
      if (nativeDomain is String && nativeCode is num) {
        final reason = _securityErrorReason(nativeDomain, nativeCode.toInt());
        if (reason != null) {
          Error.throwWithStackTrace(
            _securityException(
              nativeDomain: nativeDomain,
              nativeCode: nativeCode.toInt(),
              reason: reason,
              operation: operation,
              deviceId: deviceId,
              serviceId: serviceId,
              characteristicId: characteristicId,
              message:
                  error.message ??
                  '$operation failed with $nativeDomain error $nativeCode.',
            ),
            stackTrace,
          );
        }
      }
    }
    Error.throwWithStackTrace(
      QuickBlueException(
        code: _darwinErrorCode(error.code),
        operation: operation,
        deviceId: deviceId,
        serviceId: serviceId,
        characteristicId: characteristicId,
        message: error.message ?? '$operation failed on CoreBluetooth.',
        details: <String, Object?>{
          'platformCode': error.code,
          'native': ?details,
        },
      ),
      stackTrace,
    );
  }
}

QuickBlueErrorCode _darwinErrorCode(String code) {
  return switch (code) {
    'Unsupported' => QuickBlueErrorCode.unsupported,
    'NotFound' => QuickBlueErrorCode.notFound,
    'InvalidState' ||
    'Busy' ||
    'Disconnected' ||
    'IllegalArgument' ||
    'InvalidArgument' ||
    'InvalidConfiguration' => QuickBlueErrorCode.invalidState,
    _ => QuickBlueErrorCode.operationFailed,
  };
}

QuickBlueSecurityErrorReason? _securityErrorReason(
  String nativeDomain,
  int nativeCode,
) {
  if (nativeDomain == 'CBATTErrorDomain') {
    return switch (nativeCode) {
      5 => QuickBlueSecurityErrorReason.insufficientAuthentication,
      8 => QuickBlueSecurityErrorReason.insufficientAuthorization,
      12 => QuickBlueSecurityErrorReason.insufficientEncryptionKeySize,
      15 => QuickBlueSecurityErrorReason.insufficientEncryption,
      _ => null,
    };
  }
  if (nativeDomain == 'CBErrorDomain') {
    return switch (nativeCode) {
      14 => QuickBlueSecurityErrorReason.peerRemovedPairingInformation,
      15 => QuickBlueSecurityErrorReason.encryptionTimedOut,
      _ => null,
    };
  }
  return null;
}

QuickBlueSecurityException _securityException({
  required String nativeDomain,
  required int nativeCode,
  required QuickBlueSecurityErrorReason reason,
  required String operation,
  required String deviceId,
  String? serviceId,
  String? characteristicId,
  required String message,
}) {
  return QuickBlueSecurityException(
    reason: reason,
    nativeDomain: nativeDomain,
    nativeCode: nativeCode,
    operation: operation,
    deviceId: deviceId,
    serviceId: serviceId,
    characteristicId: characteristicId,
    message: message,
  );
}

extension on ScanOptions {
  models.PlatformDarwinScanOptions toPlatformDarwinScanOptions() {
    return models.PlatformDarwinScanOptions(
      allowDuplicates: darwin.allowDuplicates ?? allowDuplicates ?? true,
      solicitedServiceUuids: darwin.solicitedServiceUuids,
    );
  }
}

BlueScanResult _scanResultFromPlatformResult(models.PlatformScanResult result) {
  return BlueScanResult(
    deviceId: result.deviceId,
    name: result.name,
    rssi: result.rssi,
    serviceUuids: result.serviceUuids,
    manufacturerDataHead: result.manufacturerDataHead,
    manufacturerData: result.manufacturerData,
    serviceData: result.serviceData,
  );
}

models.PlatformAppleAccessoryPickerItem _toPlatformAppleAccessoryPickerItem(
  AppleAccessoryPickerItem item,
) {
  final discovery = item.discovery;
  return models.PlatformAppleAccessoryPickerItem(
    displayName: item.displayName,
    productImage: item.productImage,
    migrationDeviceId: item.migrationDeviceId,
    discovery: models.PlatformAppleAccessoryDiscovery(
      serviceUuid: discovery.serviceUuid,
      nameSubstring: discovery.nameSubstring,
      serviceData: discovery.serviceData,
      serviceDataMask: discovery.serviceDataMask,
      immediate: discovery.immediate,
    ),
  );
}

AppleAccessory _toAppleAccessory(models.PlatformAppleAccessory accessory) {
  return AppleAccessory(
    deviceId: accessory.deviceId,
    displayName: accessory.displayName,
  );
}

BleL2CapSocketEvent _l2capEventFromPlatformEvent(
  models.PlatformL2CapSocketEvent event,
) {
  if (event.data != null) {
    return BleL2CapSocketEventData(deviceId: event.deviceId, data: event.data!);
  } else if (event.error != null) {
    return BleL2CapSocketEventError(
      deviceId: event.deviceId,
      error: event.error,
    );
  } else if (event.opened == true) {
    return BleL2CapSocketEventOpened(deviceId: event.deviceId);
  } else if (event.closed == true) {
    return BleL2CapSocketEventClosed(deviceId: event.deviceId);
  }

  throw QuickBlueException(
    code: QuickBlueErrorCode.invalidState,
    operation: 'openL2cap',
    deviceId: event.deviceId,
    details: event,
    message: 'Unknown L2CAP event.',
  );
}

class _L2capSink implements EventSink<Uint8List> {
  _L2capSink({required this.api, required this.deviceId});

  final DarwinApi api;
  final String deviceId;

  @override
  void add(Uint8List event) {
    api.writeL2cap(deviceId, event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> close() async {
    api.closeL2cap(deviceId);
  }
}

void _handleCharacteristicValueChanged(
  QuickBluePlatform platform,
  models.PlatformCharacteristicValueChanged valueChanged,
) {
  platform.handleCharacteristicValueChanged(
    valueChanged.deviceId,
    valueChanged.serviceUuid,
    valueChanged.characteristicId,
    valueChanged.value,
  );
}

void _handleConnectionStateChange(
  QuickBluePlatform platform,
  models.PlatformConnectionStateChange stateChange,
) {
  final state = stateChange.state.toBlueConnectionState();
  if (state == null) return;

  platform.handleConnectionStateChanged(
    stateChange.deviceId,
    state,
    stateChange.gattStatus.toBleStatus(),
    error: _connectionError(stateChange),
  );
}

QuickBlueException? _connectionError(
  models.PlatformConnectionStateChange stateChange,
) {
  final nativeDomain = stateChange.errorDomain;
  final nativeCode = stateChange.errorCode;
  if (nativeDomain == null || nativeCode == null) {
    return null;
  }
  final message =
      stateChange.errorMessage ??
      'CoreBluetooth connection failed with $nativeDomain error $nativeCode.';
  final reason = _securityErrorReason(nativeDomain, nativeCode);
  if (reason != null) {
    return _securityException(
      nativeDomain: nativeDomain,
      nativeCode: nativeCode,
      reason: reason,
      operation: 'connection',
      deviceId: stateChange.deviceId,
      message: message,
    );
  }
  return QuickBlueException(
    code: QuickBlueErrorCode.operationFailed,
    operation: 'connection',
    deviceId: stateChange.deviceId,
    details: <String, Object>{'domain': nativeDomain, 'code': nativeCode},
    message: message,
  );
}

void _handleServiceDiscovered(
  QuickBluePlatform platform,
  models.PlatformServiceDiscovered serviceDiscovered,
) {
  platform.handleServiceDiscovered(
    serviceDiscovered.deviceId,
    serviceDiscovered.serviceUuid,
    serviceDiscovered.characteristics
        .map((characteristic) => characteristic.toBluetoothCharacteristicInfo())
        .toList(growable: false),
  );
}

extension _PlatformCharacteristicExtension on models.PlatformCharacteristic {
  BluetoothCharacteristicInfo toBluetoothCharacteristicInfo() {
    return BluetoothCharacteristicInfo(
      uuid: uuid,
      canRead: canRead,
      canWriteWithResponse: canWriteWithResponse,
      canWriteWithoutResponse: canWriteWithoutResponse,
      canNotify: canNotify,
      canIndicate: canIndicate,
    );
  }
}

extension _BleInputPropertyExtension on BleInputProperty {
  models.PlatformBleInputProperty toPlatformBleInputProperty() {
    return switch (this) {
      BleInputProperty.disabled => models.PlatformBleInputProperty.disabled,
      BleInputProperty.notification =>
        models.PlatformBleInputProperty.notification,
      BleInputProperty.indication => models.PlatformBleInputProperty.indication,
      _ => throw ArgumentError('Unknown BleInputProperty: $this'),
    };
  }
}

extension _BleOutputPropertyExtension on BleOutputProperty {
  models.PlatformBleOutputProperty toPlatformBleOutputProperty() {
    return switch (this) {
      BleOutputProperty.withResponse =>
        models.PlatformBleOutputProperty.withResponse,
      BleOutputProperty.withoutResponse =>
        models.PlatformBleOutputProperty.withoutResponse,
      _ => throw ArgumentError('Unknown BleOutputProperty: $this'),
    };
  }
}

extension _BleStatusExtension on models.PlatformGattStatus {
  BleStatus toBleStatus() {
    return switch (this) {
      models.PlatformGattStatus.success => BleStatus.success,
      models.PlatformGattStatus.failure => BleStatus.failure,
    };
  }
}

extension _PlatformConnectionStateExtension on models.PlatformConnectionState {
  BlueConnectionState? toBlueConnectionState() {
    return switch (this) {
      models.PlatformConnectionState.disconnected =>
        BlueConnectionState.disconnected,
      models.PlatformConnectionState.connected => BlueConnectionState.connected,
      _ => null,
    };
  }
}

extension _BluetoothStateExtension on models.PlatformBluetoothState {
  BlueBluetoothState toBlueBluetoothState() {
    return switch (this) {
      models.PlatformBluetoothState.unknown => BlueBluetoothState.unknown,
      models.PlatformBluetoothState.unavailable =>
        BlueBluetoothState.unavailable,
      models.PlatformBluetoothState.unauthorized =>
        BlueBluetoothState.unauthorized,
      models.PlatformBluetoothState.poweredOff => BlueBluetoothState.poweredOff,
      models.PlatformBluetoothState.poweredOn => BlueBluetoothState.poweredOn,
    };
  }
}
