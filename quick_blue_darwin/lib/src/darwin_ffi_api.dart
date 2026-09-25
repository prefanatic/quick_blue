part of 'quick_blue_darwin.dart';

class _DarwinDiscoveryComplete {
  const _DarwinDiscoveryComplete(this.deviceId);
  final String deviceId;
}

class _DarwinGattChanged {
  const _DarwinGattChanged(this.deviceId, this.serviceUuids);
  final String deviceId;
  final List<String> serviceUuids;
}

abstract class DarwinApi {
  Stream<models.PlatformBluetoothState> get bluetoothStateEvents;
  Stream<models.PlatformScanResult> get scanResults;
  Stream<models.PlatformL2CapSocketEvent> get l2CapEvents;
  Stream<models.PlatformDarwinRestorationEvent> get restorationEvents;

  void bootstrapIfEnabled();
  Future<void> configure(models.PlatformDarwinConfiguration configuration);
  Future<bool> isAppleAccessorySetupSupported();
  Future<models.PlatformAppleAccessory?> showAppleAccessoryPicker(
    List<models.PlatformAppleAccessoryPickerItem> items,
  );
  Future<List<models.PlatformAppleAccessory>> getAppleAccessories();
  Future<void> removeAppleAccessory(String deviceId);
  Future<List<models.Peripheral>> getConnectedPeripherals(
    List<String> serviceUuids,
  );
  Future<bool> isBluetoothAvailable();
  Future<void> startScan({
    List<String>? serviceUuids,
    Map<int, Uint8List>? manufacturerData,
    int? rssi,
    models.PlatformDarwinScanOptions? options,
  });
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect(String deviceId);
  Future<void> discoverServices(String deviceId);
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    models.PlatformBleInputProperty property,
  );
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  );
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    models.PlatformBleOutputProperty property,
  );
  Future<int> requestMtu(String deviceId, int expectedMtu);
  Future<void> openL2cap(String deviceId, int psm);
  void closeL2cap(String deviceId);
  void writeL2cap(String deviceId, Uint8List value);
}

class _DarwinFfiApi implements DarwinApi {
  _DarwinFfiApi(this._platform) {
    _centralDelegate = cb.CBCentralManagerDelegate$Builder.implementAsListener(
      centralManagerDidUpdateState_: _onStateChanged,
      centralManager_willRestoreState_: _onRestore,
      centralManager_didDiscoverPeripheral_advertisementData_RSSI_:
          _onDiscovered,
      centralManager_didConnectPeripheral_: _onConnected,
      centralManager_didFailToConnectPeripheral_error_: _onConnectFailed,
      centralManager_didDisconnectPeripheral_error_: _onDisconnected,
    );
    _peripheralDelegate = cb.CBPeripheralDelegate$Builder.implementAsListener(
      peripheral_didDiscoverServices_: _onServices,
      peripheral_didDiscoverCharacteristicsForService_error_:
          _onCharacteristics,
      peripheral_didModifyServices_: _onServicesModified,
      peripheral_didUpdateValueForCharacteristic_error_: _onValue,
      peripheral_didWriteValueForCharacteristic_error_: _onWrite,
      peripheral_didUpdateNotificationStateForCharacteristic_error_:
          _onNotificationState,
      peripheral_didOpenL2CAPChannel_error_: _onL2capOpen,
    );
  }

  final QuickBlueDarwin _platform;
  late final cb.CBCentralManagerDelegate _centralDelegate;
  late final cb.CBPeripheralDelegate _peripheralDelegate;
  cb.CBCentralManager? _manager;
  bool _maintainState = false;
  final Map<String, cb.CBPeripheral> _peripherals = {};
  final Map<String, Set<String>> _pendingServices = {};
  final Map<String, List<Completer<Uint8List>>> _reads = {};
  final Map<String, List<Completer<void>>> _writes = {};
  final Map<String, List<Completer<void>>> _notifications = {};
  final Map<String, _DarwinL2capSocket> _sockets = {};
  final Map<String, Completer<void>> _pendingDisconnects = {};
  final Map<String, DateTime> _lastDisconnects = {};
  Uint8List? _manufacturerFilter;
  int? _rssiFilter;
  final _stateController =
      StreamController<models.PlatformBluetoothState>.broadcast();
  final _scanController =
      StreamController<models.PlatformScanResult>.broadcast();
  final _l2capController =
      StreamController<models.PlatformL2CapSocketEvent>.broadcast();
  final _restorationController =
      StreamController<models.PlatformDarwinRestorationEvent>.broadcast();
  final _platformEventController = StreamController<Object>.broadcast();
  final List<models.PlatformDarwinRestorationEvent> _restorationHistory = [];
  accessory.ASAccessorySession? _accessorySession;
  objc.ObjCBlock<ffi.Void Function(accessory.ASAccessoryEvent)>?
  _accessoryEventHandler;
  Completer<void>? _activation;
  Completer<models.PlatformAppleAccessory?>? _picker;
  accessory.ASAccessory? _pickedAccessory;

  @override
  Stream<models.PlatformBluetoothState> get bluetoothStateEvents async* {
    final manager = _getManager();
    yield _mapState(manager.state);
    yield* _stateController.stream;
  }

  @override
  Stream<models.PlatformScanResult> get scanResults => _scanController.stream;
  @override
  Stream<models.PlatformL2CapSocketEvent> get l2CapEvents =>
      _l2capController.stream;
  @override
  Stream<models.PlatformDarwinRestorationEvent> get restorationEvents =>
      _eventsWithHistory(_restorationHistory, _restorationController.stream);

  @override
  void bootstrapIfEnabled() {
    final value = objc.NSBundle.getMainBundle().infoDictionary?.objectForKey(
      objc.NSString('QuickBlueCoreBluetoothStateRestorationEnabled'),
    );
    if (value != null &&
        objc.NSNumber.isA(value) &&
        objc.NSNumber.as(value).boolValue) {
      _maintainState = true;
      _getManager();
    }
  }

  @override
  Future<void> configure(
    models.PlatformDarwinConfiguration configuration,
  ) async {
    if (configuration.maintainState && _manager != null && !_maintainState) {
      throw PlatformException(
        code: 'InvalidState',
        message: 'QuickBlue.configure must precede other Bluetooth calls.',
      );
    }
    _maintainState = _maintainState || configuration.maintainState;
    if (_maintainState) _getManager();
  }

  @override
  Future<bool> isAppleAccessorySetupSupported() async =>
      Platform.isIOS && objc.checkOSVersion(iOS: objc.Version(18, 0, 0));

  @override
  Future<models.PlatformAppleAccessory?> showAppleAccessoryPicker(
    List<models.PlatformAppleAccessoryPickerItem> items,
  ) async {
    _requireAccessorySupport();
    if (_manager != null || _maintainState) {
      throw PlatformException(
        code: 'InvalidState',
        message: 'AccessorySetupKit must run before CoreBluetooth starts.',
      );
    }
    final displayItems = objc.NSArray.of(items.map(_makeDisplayItem));
    await _ensureAccessorySession();
    if (_picker != null) {
      throw PlatformException(
        code: 'InvalidState',
        message: 'An AccessorySetupKit picker is already active.',
      );
    }
    final picker = Completer<models.PlatformAppleAccessory?>();
    _picker = picker;
    _pickedAccessory = null;
    _accessorySession!.showPickerForDisplayItems(
      displayItems,
      completionHandler: accessory.ObjCBlock_ffiVoid_NSError.listener((error) {
        if (error != null && !picker.isCompleted) {
          _picker = null;
          picker.completeError(_platformError(error, 'PickerFailed'));
        }
      }),
    );
    return picker.future;
  }

  @override
  Future<List<models.PlatformAppleAccessory>> getAppleAccessories() async {
    await _ensureAccessorySession();
    return [
      for (final value in _accessorySession!.accessories.asDart())
        ?_mapAccessory(accessory.ASAccessory.as(value)),
    ];
  }

  @override
  Future<void> removeAppleAccessory(String deviceId) async {
    await _ensureAccessorySession();
    accessory.ASAccessory? target;
    for (final value in _accessorySession!.accessories.asDart()) {
      final item = accessory.ASAccessory.as(value);
      final id = item.bluetoothIdentifier?.UUIDString.toDartString();
      if (id?.toLowerCase() == deviceId.toLowerCase()) {
        target = item;
        break;
      }
    }
    if (target == null) {
      throw PlatformException(code: 'NotFound', message: deviceId);
    }
    final result = Completer<void>();
    _accessorySession!.removeAccessory(
      target,
      completionHandler: accessory.ObjCBlock_ffiVoid_NSError.listener((error) {
        if (error == null) {
          result.complete();
        } else {
          result.completeError(_platformError(error, 'RemoveFailed'));
        }
      }),
    );
    return result.future;
  }

  void _requireAccessorySupport() {
    if (!Platform.isIOS || !objc.checkOSVersion(iOS: objc.Version(18, 0, 0))) {
      throw PlatformException(
        code: 'Unsupported',
        message: 'AccessorySetupKit requires iOS 18 or later.',
      );
    }
  }

  Future<void> _ensureAccessorySession() {
    _requireAccessorySupport();
    final active = _activation;
    if (active != null) return active.future;
    final activation = Completer<void>();
    _activation = activation;
    final session = accessory.ASAccessorySession();
    _accessorySession = session;
    _accessoryEventHandler = accessory
        .ObjCBlock_ffiVoid_ASAccessoryEvent.listener(_onAccessoryEvent);
    final queue = objc.NSObject.fromPointer(
      dispatch.quick_blue_main_queue().cast(),
      retain: true,
      release: true,
    );
    session.activateWithQueue(queue, eventHandler: _accessoryEventHandler!);
    return activation.future;
  }

  void _onAccessoryEvent(accessory.ASAccessoryEvent event) {
    switch (event.eventType) {
      case accessory.ASAccessoryEventType.ASAccessoryEventTypeActivated:
        if (_activation case final activation? when !activation.isCompleted) {
          activation.complete();
        }
      case accessory.ASAccessoryEventType.ASAccessoryEventTypeInvalidated:
        final error = event.error == null
            ? PlatformException(
                code: 'InvalidState',
                message: 'Accessory session ended.',
              )
            : _platformError(event.error!, 'InvalidState');
        if (_activation case final activation? when !activation.isCompleted) {
          activation.completeError(error);
        }
        if (_picker case final picker? when !picker.isCompleted) {
          picker.completeError(error);
        }
        _picker = null;
        _activation = null;
        _accessorySession = null;
      case accessory.ASAccessoryEventType.ASAccessoryEventTypeAccessoryAdded:
        _pickedAccessory = event.accessory;
      case accessory.ASAccessoryEventType.ASAccessoryEventTypePickerDidDismiss:
        final picker = _picker;
        _picker = null;
        if (picker != null && !picker.isCompleted) {
          picker.complete(
            _pickedAccessory == null ? null : _mapAccessory(_pickedAccessory!),
          );
        }
        _pickedAccessory = null;
      case accessory.ASAccessoryEventType.ASAccessoryEventTypePickerSetupFailed:
        final picker = _picker;
        if (picker != null && !picker.isCompleted && event.error != null) {
          _picker = null;
          picker.completeError(_platformError(event.error!, 'PickerFailed'));
        }
      default:
        break;
    }
  }

  models.PlatformAppleAccessory? _mapAccessory(accessory.ASAccessory value) {
    final id = value.bluetoothIdentifier?.UUIDString.toDartString();
    if (id == null) return null;
    return models.PlatformAppleAccessory(
      deviceId: id,
      displayName: value.displayName.toDartString(),
    );
  }

  accessory.ASPickerDisplayItem _makeDisplayItem(
    models.PlatformAppleAccessoryPickerItem item,
  ) {
    final image = accessory.UIImage.imageWithData(item.productImage.toNSData());
    if (image == null) {
      throw PlatformException(
        code: 'InvalidArgument',
        message: 'The product image has invalid data.',
      );
    }
    final discovery = item.discovery;
    _validateAccessoryInfoPlist(discovery);
    final descriptor = accessory.ASDiscoveryDescriptor();
    descriptor.bluetoothServiceUUID = accessory.CBUUID.UUIDWithString(
      objc.NSString(discovery.serviceUuid),
    );
    if (discovery.nameSubstring case final name?) {
      descriptor.bluetoothNameSubstring = objc.NSString(name);
    }
    if (discovery.serviceData case final data?) {
      descriptor.bluetoothServiceDataBlob = data.toNSData();
    }
    if (discovery.serviceDataMask case final mask?) {
      descriptor.bluetoothServiceDataMask = mask.toNSData();
    }
    descriptor.bluetoothRange = discovery.immediate
        ? accessory
              .ASDiscoveryDescriptorRange
              .ASDiscoveryDescriptorRangeImmediate
        : accessory
              .ASDiscoveryDescriptorRange
              .ASDiscoveryDescriptorRangeDefault;
    if (item.migrationDeviceId case final migrationId?) {
      final uuid = accessory.NSUUID.alloc().initWithUUIDString(
        objc.NSString(migrationId),
      );
      if (uuid == null) {
        throw PlatformException(
          code: 'InvalidArgument',
          message: 'migrationDeviceId must be a UUID.',
        );
      }
      final migration = accessory.ASMigrationDisplayItem.alloc().initWithName(
        objc.NSString(item.displayName),
        productImage: image,
        descriptor: descriptor,
      );
      migration.peripheralIdentifier = uuid;
      return accessory.ASPickerDisplayItem.as(migration);
    }
    return accessory.ASPickerDisplayItem.alloc().initWithName(
      objc.NSString(item.displayName),
      productImage: image,
      descriptor: descriptor,
    );
  }

  void _validateAccessoryInfoPlist(
    models.PlatformAppleAccessoryDiscovery discovery,
  ) {
    if (!_infoPlistArrayContains('NSAccessorySetupSupports', 'Bluetooth')) {
      throw PlatformException(
        code: 'InvalidConfiguration',
        message: 'Info.plist NSAccessorySetupSupports must contain Bluetooth.',
      );
    }
    if (!_infoPlistArrayContains(
      'NSAccessorySetupBluetoothServices',
      discovery.serviceUuid,
    )) {
      throw PlatformException(
        code: 'InvalidConfiguration',
        message:
            'Info.plist NSAccessorySetupBluetoothServices must contain '
            '${discovery.serviceUuid}.',
      );
    }
    if (discovery.nameSubstring case final name?
        when !_infoPlistArrayContains('NSAccessorySetupBluetoothNames', name)) {
      throw PlatformException(
        code: 'InvalidConfiguration',
        message:
            'Info.plist NSAccessorySetupBluetoothNames must contain $name.',
      );
    }
  }

  bool _infoPlistArrayContains(String key, String value) {
    final raw = objc.NSBundle.getMainBundle().infoDictionary?.objectForKey(
      objc.NSString(key),
    );
    if (raw == null || !objc.NSArray.isA(raw)) return false;
    return objc.NSArray.as(raw).asDart().any(
      (item) =>
          objc.NSString.isA(item) &&
          objc.NSString.as(item).toDartString().toLowerCase() ==
              value.toLowerCase(),
    );
  }

  cb.CBCentralManager _getManager() {
    final existing = _manager;
    if (existing != null) return existing;
    final bundleId =
        objc.NSBundle.getMainBundle().bundleIdentifier?.toDartString() ??
        'quick_blue';
    final options = _maintainState
        ? objc.NSDictionary.of({
            cb.CBCentralManagerOptionRestoreIdentifierKey: objc.NSString(
              '$bundleId.quick_blue.central',
            ),
          })
        : null;
    final manager = cb.CBCentralManager.alloc().initWithDelegate$1(
      _centralDelegate,
      options: options,
    );
    _manager = manager;
    return manager;
  }

  @override
  Future<bool> isBluetoothAvailable() async =>
      _getManager().state == cb.CBManagerState.CBManagerStatePoweredOn;

  @override
  Future<List<models.Peripheral>> getConnectedPeripherals(
    List<String> serviceUuids,
  ) async {
    final services = objc.NSArray.of(
      serviceUuids.map(
        (value) => cb.CBUUID.UUIDWithString(objc.NSString(value)),
      ),
    );
    final result = _getManager().retrieveConnectedPeripheralsWithServices(
      services,
    );
    return [
      for (final value in result.asDart())
        () {
          final peripheral = cb.CBPeripheral.as(value);
          final id = _deviceId(peripheral);
          _peripherals[id] = peripheral;
          return models.Peripheral(
            id: id,
            name: peripheral.name?.toDartString() ?? '',
          );
        }(),
    ];
  }

  @override
  Future<void> startScan({
    List<String>? serviceUuids,
    Map<int, Uint8List>? manufacturerData,
    int? rssi,
    models.PlatformDarwinScanOptions? options,
  }) async {
    _manufacturerFilter = null;
    if (manufacturerData case final data? when data.isNotEmpty) {
      final entry = data.entries.first;
      _manufacturerFilter = Uint8List.fromList([
        entry.key & 0xff,
        (entry.key >> 8) & 0xff,
        ...entry.value,
      ]);
    }
    _rssiFilter = rssi;
    final nativeOptions = objc.NSDictionary.of({
      cb.CBCentralManagerScanOptionAllowDuplicatesKey: objc
          .NSNumberCreation.numberWithBool(options?.allowDuplicates ?? true),
      if (options != null && options.solicitedServiceUuids.isNotEmpty)
        cb.CBCentralManagerScanOptionSolicitedServiceUUIDsKey: objc.NSArray.of(
          options.solicitedServiceUuids.map(
            (value) => cb.CBUUID.UUIDWithString(objc.NSString(value)),
          ),
        ),
    });
    _getManager().scanForPeripheralsWithServices(
      serviceUuids == null || serviceUuids.isEmpty
          ? null
          : objc.NSArray.of(
              serviceUuids.map(
                (value) => cb.CBUUID.UUIDWithString(objc.NSString(value)),
              ),
            ),
      options: nativeOptions,
    );
  }

  @override
  Future<void> stopScan() async {
    _manufacturerFilter = null;
    _rssiFilter = null;
    _manager?.stopScan();
  }

  @override
  Future<void> connect(String deviceId) async {
    final peripheral = _peripheral(deviceId);
    peripheral.delegate = _peripheralDelegate;
    if (_pendingDisconnects[deviceId] case final pending?) {
      await pending.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw PlatformException(
          code: 'Busy',
          message: 'CoreBluetooth did not finish the previous disconnect.',
        ),
      );
    }
    if (_lastDisconnects[deviceId] case final last?) {
      final remaining =
          const Duration(milliseconds: 100) - DateTime.now().difference(last);
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
    }
    if (peripheral.state == cb.CBPeripheralState.CBPeripheralStateConnected) {
      _emitConnection(peripheral, null);
      return;
    }
    if (peripheral.state == cb.CBPeripheralState.CBPeripheralStateConnecting) {
      return;
    }
    if (peripheral.state ==
        cb.CBPeripheralState.CBPeripheralStateDisconnecting) {
      throw PlatformException(
        code: 'Busy',
        message: 'CoreBluetooth is still disconnecting the peripheral.',
      );
    }
    _getManager().connectPeripheral(peripheral);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final peripheral = _peripheral(deviceId);
    if (peripheral.state ==
        cb.CBPeripheralState.CBPeripheralStateDisconnected) {
      _emitConnection(peripheral, null);
      return;
    }
    _pendingDisconnects.putIfAbsent(deviceId, Completer<void>.new);
    try {
      _getManager().cancelPeripheralConnection(peripheral);
    } catch (_) {
      _pendingDisconnects.remove(deviceId)?.complete();
      rethrow;
    }
    _checkPendingDisconnect(peripheral, 100);
  }

  void _checkPendingDisconnect(cb.CBPeripheral peripheral, int delayMs) {
    Timer(Duration(milliseconds: delayMs), () {
      final id = _deviceId(peripheral);
      if (!_pendingDisconnects.containsKey(id)) return;
      if (peripheral.state ==
          cb.CBPeripheralState.CBPeripheralStateDisconnected) {
        _onDisconnected(_getManager(), peripheral, null);
      } else if (delayMs < 1000) {
        _checkPendingDisconnect(peripheral, delayMs * 2);
      } else {
        _pendingDisconnects.remove(id)?.complete();
      }
    });
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    _connectedPeripheral(deviceId).discoverServices(null);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    models.PlatformBleInputProperty property,
  ) {
    final peripheral = _connectedPeripheral(deviceId);
    final target = _characteristic(peripheral, service, characteristic);
    final supported =
        property == models.PlatformBleInputProperty.disabled ||
        (property == models.PlatformBleInputProperty.notification &&
            target.properties &
                    cb
                        .CBCharacteristicProperties
                        .CBCharacteristicPropertyNotify !=
                0) ||
        (property == models.PlatformBleInputProperty.indication &&
            target.properties &
                    cb
                        .CBCharacteristicProperties
                        .CBCharacteristicPropertyIndicate !=
                0);
    if (!supported) {
      throw PlatformException(
        code: 'Unsupported',
        message: 'The characteristic does not support $property.',
      );
    }
    final completer = Completer<void>();
    _notifications
        .putIfAbsent(_key(deviceId, characteristic), () => [])
        .add(completer);
    peripheral.setNotifyValue(
      property != models.PlatformBleInputProperty.disabled,
      forCharacteristic: target,
    );
    return completer.future;
  }

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) {
    final peripheral = _connectedPeripheral(deviceId);
    final target = _characteristic(peripheral, service, characteristic);
    if (target.properties &
            cb.CBCharacteristicProperties.CBCharacteristicPropertyRead ==
        0) {
      throw PlatformException(
        code: 'Unsupported',
        message: 'The characteristic does not support reads.',
      );
    }
    final completer = Completer<Uint8List>();
    _reads.putIfAbsent(_key(deviceId, characteristic), () => []).add(completer);
    peripheral.readValueForCharacteristic(target);
    return completer.future;
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    models.PlatformBleOutputProperty property,
  ) {
    final peripheral = _connectedPeripheral(deviceId);
    final target = _characteristic(peripheral, service, characteristic);
    final withResponse =
        property == models.PlatformBleOutputProperty.withResponse;
    final requiredFlag = withResponse
        ? cb.CBCharacteristicProperties.CBCharacteristicPropertyWrite
        : cb
              .CBCharacteristicProperties
              .CBCharacteristicPropertyWriteWithoutResponse;
    if (target.properties & requiredFlag == 0) {
      throw PlatformException(
        code: 'Unsupported',
        message: 'The characteristic does not support $property.',
      );
    }
    final completer = Completer<void>();
    if (withResponse) {
      _writes
          .putIfAbsent(_key(deviceId, characteristic), () => [])
          .add(completer);
    }
    peripheral.writeValue(
      value.toNSData(),
      forCharacteristic: target,
      type: withResponse
          ? cb.CBCharacteristicWriteType.CBCharacteristicWriteWithResponse
          : cb.CBCharacteristicWriteType.CBCharacteristicWriteWithoutResponse,
    );
    if (!withResponse) completer.complete();
    return completer.future;
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async =>
      _connectedPeripheral(deviceId).maximumWriteValueLengthForType(
        cb.CBCharacteristicWriteType.CBCharacteristicWriteWithoutResponse,
      ) +
      3;

  @override
  Future<void> openL2cap(String deviceId, int psm) async {
    if (psm < 0 || psm > 0xffff) {
      throw PlatformException(
        code: 'InvalidArgument',
        message: 'Invalid PSM: $psm',
      );
    }
    _connectedPeripheral(deviceId).openL2CAPChannel(psm);
  }

  @override
  void closeL2cap(String deviceId) {
    _sockets.remove(deviceId)?.close();
  }

  @override
  void writeL2cap(String deviceId, Uint8List value) {
    final socket = _sockets[deviceId];
    if (socket == null) {
      throw PlatformException(code: 'Disconnected', message: deviceId);
    }
    socket.write(value);
  }

  cb.CBPeripheral _peripheral(String deviceId) {
    final known = _peripherals[deviceId];
    if (known != null) return known;
    final identifier = cb.NSUUID.alloc().initWithUUIDString(
      objc.NSString(deviceId),
    );
    if (identifier == null) {
      throw PlatformException(code: 'IllegalArgument', message: deviceId);
    }
    final results = _getManager().retrievePeripheralsWithIdentifiers(
      objc.NSArray.of([identifier]),
    );
    if (results.count == 0) {
      throw PlatformException(code: 'NotFound', message: deviceId);
    }
    final peripheral = cb.CBPeripheral.as(results.asDart().first);
    peripheral.delegate = _peripheralDelegate;
    _peripherals[deviceId] = peripheral;
    return peripheral;
  }

  cb.CBPeripheral _connectedPeripheral(String deviceId) {
    final peripheral = _peripheral(deviceId);
    if (peripheral.state != cb.CBPeripheralState.CBPeripheralStateConnected) {
      throw PlatformException(code: 'Disconnected', message: deviceId);
    }
    return peripheral;
  }

  cb.CBCharacteristic _characteristic(
    cb.CBPeripheral peripheral,
    String serviceId,
    String characteristicId,
  ) {
    final wantedService = _normalizedUuid(serviceId);
    final wantedCharacteristic = _normalizedUuid(characteristicId);
    for (final nativeService
        in peripheral.services?.asDart() ?? <objc.ObjCObject>[]) {
      final service = cb.CBService.as(nativeService);
      if (_uuid(service.UUID) != wantedService) {
        continue;
      }
      for (final nativeCharacteristic
          in service.characteristics?.asDart() ?? <objc.ObjCObject>[]) {
        final characteristic = cb.CBCharacteristic.as(nativeCharacteristic);
        if (_uuid(characteristic.UUID) == wantedCharacteristic) {
          return characteristic;
        }
      }
    }
    throw PlatformException(
      code: 'IllegalArgument',
      message: 'Unknown characteristic: $characteristicId',
    );
  }

  String _deviceId(cb.CBPeripheral peripheral) =>
      peripheral.identifier.UUIDString.toDartString();
  String _uuid(cb.CBUUID uuid) => uuid.UUIDString.toDartString().toLowerCase();
  String _normalizedUuid(String value) =>
      _uuid(cb.CBUUID.UUIDWithString(objc.NSString(value)));
  String _key(String deviceId, String characteristicId) =>
      '$deviceId/${_normalizedUuid(characteristicId)}';

  void _onStateChanged(cb.CBCentralManager manager) {
    _stateController.add(_mapState(manager.state));
  }

  models.PlatformBluetoothState _mapState(cb.CBManagerState nativeState) {
    return switch (nativeState) {
      cb.CBManagerState.CBManagerStatePoweredOn =>
        models.PlatformBluetoothState.poweredOn,
      cb.CBManagerState.CBManagerStatePoweredOff =>
        models.PlatformBluetoothState.poweredOff,
      cb.CBManagerState.CBManagerStateUnauthorized =>
        models.PlatformBluetoothState.unauthorized,
      cb.CBManagerState.CBManagerStateUnsupported =>
        models.PlatformBluetoothState.unavailable,
      _ => models.PlatformBluetoothState.unknown,
    };
  }

  void _onRestore(cb.CBCentralManager manager, objc.NSDictionary state) {
    final values = state.objectForKey(
      cb.CBCentralManagerRestoredStatePeripheralsKey,
    );
    final restored = values == null
        ? <cb.CBPeripheral>[]
        : [
            for (final item in objc.NSArray.as(values).asDart())
              cb.CBPeripheral.as(item),
          ];
    for (final peripheral in restored) {
      peripheral.delegate = _peripheralDelegate;
      _peripherals[_deviceId(peripheral)] = peripheral;
      _emitConnection(peripheral, null);
    }
    final scanServices = state.objectForKey(
      cb.CBCentralManagerRestoredStateScanServicesKey,
    );
    final event = models.PlatformDarwinRestorationEvent(
      restoredPeripheralCount: restored.length,
      disconnectedPeripheralCount: restored
          .where(
            (p) =>
                p.state == cb.CBPeripheralState.CBPeripheralStateDisconnected,
          )
          .length,
      connectingPeripheralCount: restored
          .where(
            (p) => p.state == cb.CBPeripheralState.CBPeripheralStateConnecting,
          )
          .length,
      connectedPeripheralCount: restored
          .where(
            (p) => p.state == cb.CBPeripheralState.CBPeripheralStateConnected,
          )
          .length,
      disconnectingPeripheralCount: restored
          .where(
            (p) =>
                p.state == cb.CBPeripheralState.CBPeripheralStateDisconnecting,
          )
          .length,
      unknownPeripheralCount: 0,
      scanningRestored:
          scanServices != null ||
          state.objectForKey(cb.CBCentralManagerRestoredStateScanOptionsKey) !=
              null,
      restoredScanServiceCount: scanServices == null
          ? 0
          : objc.NSArray.as(scanServices).count,
    );
    _restorationHistory.add(event);
    _restorationController.add(event);
  }

  void _onDiscovered(
    cb.CBCentralManager manager,
    cb.CBPeripheral peripheral,
    objc.NSDictionary advertisement,
    objc.NSNumber rssi,
  ) {
    final id = _deviceId(peripheral);
    _peripherals[id] = peripheral;
    if (_rssiFilter case final minimum? when rssi.intValue < minimum) {
      return;
    }
    final manufacturer = advertisement.objectForKey(
      cb.CBAdvertisementDataManufacturerDataKey,
    );
    final rawManufacturer = manufacturer == null
        ? Uint8List(0)
        : objc.NSData.as(manufacturer).toList();
    if (_manufacturerFilter case final wanted?
        when !_bytesEqual(wanted, rawManufacturer)) {
      return;
    }
    final serviceValues = advertisement.objectForKey(
      cb.CBAdvertisementDataServiceUUIDsKey,
    );
    final serviceDataValues = advertisement.objectForKey(
      cb.CBAdvertisementDataServiceDataKey,
    );
    final advertisedName = advertisement.objectForKey(
      cb.CBAdvertisementDataLocalNameKey,
    );
    final serviceData = <String, Uint8List>{};
    if (serviceDataValues != null) {
      for (final entry in objc.NSDictionary.as(
        serviceDataValues,
      ).asDart().entries) {
        serviceData[_uuid(cb.CBUUID.as(entry.key))] = objc.NSData.as(
          entry.value,
        ).toList();
      }
    }
    _scanController.add(
      models.PlatformScanResult(
        name: advertisedName != null && objc.NSString.isA(advertisedName)
            ? objc.NSString.as(advertisedName).toDartString()
            : peripheral.name?.toDartString() ?? '',
        deviceId: id,
        manufacturerDataHead: rawManufacturer,
        manufacturerData: rawManufacturer.length > 2
            ? Uint8List.sublistView(rawManufacturer, 2)
            : Uint8List(0),
        rssi: rssi.intValue,
        serviceUuids: serviceValues == null
            ? []
            : [
                for (final value in objc.NSArray.as(serviceValues).asDart())
                  _uuid(cb.CBUUID.as(value)),
              ],
        serviceData: serviceData,
      ),
    );
  }

  void _onConnected(cb.CBCentralManager manager, cb.CBPeripheral peripheral) {
    _peripherals[_deviceId(peripheral)] = peripheral;
    peripheral.delegate = _peripheralDelegate;
    _emitConnection(peripheral, null);
  }

  void _onConnectFailed(
    cb.CBCentralManager manager,
    cb.CBPeripheral peripheral,
    objc.NSError? error,
  ) => _emitConnection(peripheral, error);

  void _onDisconnected(
    cb.CBCentralManager manager,
    cb.CBPeripheral peripheral,
    objc.NSError? error,
  ) {
    final id = _deviceId(peripheral);
    _lastDisconnects[id] = DateTime.now();
    _pendingDisconnects.remove(id)?.complete();
    _sockets.remove(_deviceId(peripheral))?.close();
    _failOperations(_deviceId(peripheral), error);
    _emitConnection(peripheral, error);
  }

  void _emitConnection(cb.CBPeripheral peripheral, objc.NSError? error) {
    final state = switch (peripheral.state) {
      cb.CBPeripheralState.CBPeripheralStateConnected =>
        models.PlatformConnectionState.connected,
      cb.CBPeripheralState.CBPeripheralStateConnecting =>
        models.PlatformConnectionState.connecting,
      cb.CBPeripheralState.CBPeripheralStateDisconnecting =>
        models.PlatformConnectionState.disconnecting,
      _ => models.PlatformConnectionState.disconnected,
    };
    final event = models.PlatformConnectionStateChange(
      deviceId: _deviceId(peripheral),
      state: state,
      gattStatus: error == null
          ? models.PlatformGattStatus.success
          : models.PlatformGattStatus.failure,
      errorDomain: error?.domain.toDartString(),
      errorCode: error?.code,
      errorMessage: error?.localizedDescription.toDartString(),
    );
    _handleConnectionStateChange(_platform, event);
    _platformEventController.add(event);
  }

  void _onServices(cb.CBPeripheral peripheral, objc.NSError? error) {
    final id = _deviceId(peripheral);
    final services = peripheral.services?.asDart() ?? <objc.ObjCObject>[];
    if (error != null || services.isEmpty) {
      _platform.onServiceDiscoveryComplete(id);
      _platformEventController.add(_DarwinDiscoveryComplete(id));
      return;
    }
    _pendingServices[id] = {
      for (final value in services) _uuid(cb.CBService.as(value).UUID),
    };
    for (final value in services) {
      peripheral.discoverCharacteristics(
        null,
        forService: cb.CBService.as(value),
      );
    }
  }

  void _onCharacteristics(
    cb.CBPeripheral peripheral,
    cb.CBService service,
    objc.NSError? error,
  ) {
    final id = _deviceId(peripheral);
    final event = models.PlatformServiceDiscovered(
      deviceId: id,
      serviceUuid: _uuid(service.UUID),
      characteristics: [
        for (final value
            in service.characteristics?.asDart() ?? <objc.ObjCObject>[])
          () {
            final characteristic = cb.CBCharacteristic.as(value);
            final flags = characteristic.properties;
            return models.PlatformCharacteristic(
              uuid: _uuid(characteristic.UUID),
              canRead:
                  flags &
                      cb
                          .CBCharacteristicProperties
                          .CBCharacteristicPropertyRead !=
                  0,
              canWriteWithResponse:
                  flags &
                      cb
                          .CBCharacteristicProperties
                          .CBCharacteristicPropertyWrite !=
                  0,
              canWriteWithoutResponse:
                  flags &
                      cb
                          .CBCharacteristicProperties
                          .CBCharacteristicPropertyWriteWithoutResponse !=
                  0,
              canNotify:
                  flags &
                      cb
                          .CBCharacteristicProperties
                          .CBCharacteristicPropertyNotify !=
                  0,
              canIndicate:
                  flags &
                      cb
                          .CBCharacteristicProperties
                          .CBCharacteristicPropertyIndicate !=
                  0,
            );
          }(),
      ],
    );
    _handleServiceDiscovered(_platform, event);
    _platformEventController.add(event);
    final pending = _pendingServices[id];
    pending?.remove(_uuid(service.UUID));
    if (pending != null && pending.isEmpty) {
      _pendingServices.remove(id);
      _platform.onServiceDiscoveryComplete(id);
      _platformEventController.add(_DarwinDiscoveryComplete(id));
    }
  }

  void _onServicesModified(cb.CBPeripheral peripheral, objc.NSArray services) {
    final id = _deviceId(peripheral);
    _pendingServices.remove(id);
    final uuids = [
      for (final value in services.asDart()) _uuid(cb.CBService.as(value).UUID),
    ];
    _platform.handleGattServicesChanged(id, invalidatedServiceUuids: uuids);
    _platformEventController.add(_DarwinGattChanged(id, uuids));
  }

  void _onValue(
    cb.CBPeripheral peripheral,
    cb.CBCharacteristic characteristic,
    objc.NSError? error,
  ) {
    final id = _deviceId(peripheral);
    final pending = _pop(_reads, _key(id, _uuid(characteristic.UUID)));
    if (error != null) {
      pending?.completeError(_platformError(error, 'ReadFailed'));
      return;
    }
    final value = characteristic.value?.toList();
    if (value == null) {
      pending?.completeError(
        PlatformException(
          code: 'ReadFailed',
          message: 'CoreBluetooth returned no characteristic value.',
        ),
      );
      return;
    }
    pending?.complete(value);
    final event = models.PlatformCharacteristicValueChanged(
      deviceId: id,
      serviceUuid: characteristic.service == null
          ? ''
          : _uuid(characteristic.service!.UUID),
      characteristicId: _uuid(characteristic.UUID),
      value: value,
    );
    _handleCharacteristicValueChanged(_platform, event);
    _platformEventController.add(event);
  }

  void _onWrite(
    cb.CBPeripheral peripheral,
    cb.CBCharacteristic characteristic,
    objc.NSError? error,
  ) {
    final pending = _pop(
      _writes,
      _key(_deviceId(peripheral), _uuid(characteristic.UUID)),
    );
    if (error == null) {
      pending?.complete();
    } else {
      pending?.completeError(_platformError(error, 'WriteFailed'));
    }
  }

  void _onNotificationState(
    cb.CBPeripheral peripheral,
    cb.CBCharacteristic characteristic,
    objc.NSError? error,
  ) {
    final pending = _pop(
      _notifications,
      _key(_deviceId(peripheral), _uuid(characteristic.UUID)),
    );
    if (error == null) {
      pending?.complete();
    } else {
      pending?.completeError(_platformError(error, 'SetNotifiableFailed'));
    }
  }

  void _onL2capOpen(
    cb.CBPeripheral peripheral,
    cb.CBL2CAPChannel? channel,
    objc.NSError? error,
  ) {
    final id = _deviceId(peripheral);
    if (channel == null || error != null) {
      _l2capController.add(
        models.PlatformL2CapSocketEvent(
          deviceId: id,
          error:
              error?.localizedDescription.toDartString() ??
              'CoreBluetooth did not open the L2CAP channel.',
        ),
      );
      return;
    }
    _sockets.remove(id)?.close();
    _sockets[id] = _DarwinL2capSocket(
      channel,
      onEvent: (event) {
        _l2capController.add(
          models.PlatformL2CapSocketEvent(
            deviceId: id,
            data: event.data,
            error: event.error,
            opened: event.opened,
            closed: event.closed,
          ),
        );
        if (event.closed == true) {
          _sockets.remove(id);
        }
      },
    )..open();
  }

  T? _pop<T>(Map<String, List<T>> queue, String key) {
    final entries = queue[key];
    if (entries == null || entries.isEmpty) return null;
    final item = entries.removeAt(0);
    if (entries.isEmpty) queue.remove(key);
    return item;
  }

  void _failOperations(String deviceId, objc.NSError? error) {
    final failure = error == null
        ? PlatformException(code: 'Disconnected')
        : _platformError(error, 'Disconnected');
    for (final queue in [_reads, _writes, _notifications]) {
      for (final key
          in queue.keys.where((key) => key.startsWith('$deviceId/')).toList()) {
        for (final pending in queue.remove(key)!) {
          pending.completeError(failure);
        }
      }
    }
  }

  PlatformException _platformError(objc.NSError error, String code) =>
      PlatformException(
        code: code,
        message: error.localizedDescription.toDartString(),
        details: {'domain': error.domain.toDartString(), 'code': error.code},
      );

  bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

class _DarwinL2capSocket {
  _DarwinL2capSocket(this._channel, {required this.onEvent}) {
    _input = _channel.inputStream;
    _output = _channel.outputStream;
    _delegate = objc.NSStreamDelegate$Builder.implementAsListener(
      stream_handleEvent_: _onStreamEvent,
    );
  }

  final cb.CBL2CAPChannel _channel;
  final void Function(models.PlatformL2CapSocketEvent) onEvent;
  late final objc.NSInputStream _input;
  late final objc.NSOutputStream _output;
  late final objc.NSStreamDelegate _delegate;
  final List<int> _pending = [];
  bool _inputOpen = false;
  bool _outputOpen = false;
  bool _closed = false;

  void open() {
    final runLoop = objc.NSRunLoop.getMainRunLoop();
    final mode = cb.NSDefaultRunLoopMode;
    _input.delegate = _delegate;
    _output.delegate = _delegate;
    _input.scheduleInRunLoop(runLoop, forMode: mode);
    _output.scheduleInRunLoop(runLoop, forMode: mode);
    _input.open();
    _output.open();
  }

  void write(Uint8List bytes) {
    if (_closed) {
      throw PlatformException(
        code: 'Disconnected',
        message: 'L2CAP socket closed.',
      );
    }
    _pending.addAll(bytes);
    _flush();
  }

  void _onStreamEvent(objc.NSStream stream, int event) {
    if (_closed) return;
    final isInput = stream.ref.pointer == _input.ref.pointer;
    if (event & objc.NSStreamEvent.NSStreamEventOpenCompleted != 0) {
      if (isInput) {
        _inputOpen = true;
      } else {
        _outputOpen = true;
      }
      if (_inputOpen && _outputOpen) {
        onEvent(models.PlatformL2CapSocketEvent(deviceId: '', opened: true));
      }
    }
    if (event & objc.NSStreamEvent.NSStreamEventHasBytesAvailable != 0) {
      _read();
    }
    if (event & objc.NSStreamEvent.NSStreamEventHasSpaceAvailable != 0) {
      _flush();
    }
    if (event & objc.NSStreamEvent.NSStreamEventErrorOccurred != 0) {
      final error = stream.streamError;
      onEvent(
        models.PlatformL2CapSocketEvent(
          deviceId: '',
          error:
              error?.localizedDescription.toDartString() ??
              'L2CAP stream failed.',
        ),
      );
      close();
    }
    if (event & objc.NSStreamEvent.NSStreamEventEndEncountered != 0) {
      close();
    }
  }

  void _read() {
    final buffer = memory.calloc<ffi.Uint8>(8192);
    try {
      while (_input.hasBytesAvailable) {
        final count = _input.read(buffer, maxLength: 8192);
        if (count > 0) {
          onEvent(
            models.PlatformL2CapSocketEvent(
              deviceId: '',
              data: Uint8List.fromList(buffer.asTypedList(count)),
            ),
          );
        } else if (count < 0) {
          onEvent(
            models.PlatformL2CapSocketEvent(
              deviceId: '',
              error:
                  _input.streamError?.localizedDescription.toDartString() ??
                  'L2CAP read failed.',
            ),
          );
          close();
          return;
        } else {
          return;
        }
      }
    } finally {
      memory.calloc.free(buffer);
    }
  }

  void _flush() {
    if (_closed || !_output.hasSpaceAvailable || _pending.isEmpty) return;
    final buffer = memory.calloc<ffi.Uint8>(_pending.length);
    try {
      buffer.asTypedList(_pending.length).setAll(0, _pending);
      final count = _output.write(buffer, maxLength: _pending.length);
      if (count > 0) {
        _pending.removeRange(0, count);
      } else if (count < 0) {
        onEvent(
          models.PlatformL2CapSocketEvent(
            deviceId: '',
            error:
                _output.streamError?.localizedDescription.toDartString() ??
                'L2CAP write failed.',
          ),
        );
        close();
      }
    } finally {
      memory.calloc.free(buffer);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final runLoop = objc.NSRunLoop.getMainRunLoop();
    final mode = cb.NSDefaultRunLoopMode;
    _input.close();
    _output.close();
    _input.removeFromRunLoop(runLoop, forMode: mode);
    _output.removeFromRunLoop(runLoop, forMode: mode);
    _input.delegate = null;
    _output.delegate = null;
    _pending.clear();
    onEvent(models.PlatformL2CapSocketEvent(deviceId: '', closed: true));
  }
}
