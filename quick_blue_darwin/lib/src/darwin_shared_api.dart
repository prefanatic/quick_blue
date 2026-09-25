// Copyright (c) 2026, the quick_blue authors.
// Use of this source code is governed by the BSD-3-Clause license.

part of 'quick_blue_darwin.dart';

const _brokerName = 'quick_blue_darwin/core_bluetooth_owner';
const _ownerClient = 'owner';

DarwinApi _createDarwinApi(QuickBlueDarwin platform) {
  final inbox = ReceivePort();
  if (ui.IsolateNameServer.registerPortWithName(inbox.sendPort, _brokerName)) {
    return _DarwinOwnerApi(platform, inbox);
  }
  inbox.close();
  final owner = ui.IsolateNameServer.lookupPortByName(_brokerName);
  if (owner == null) {
    throw StateError('The Darwin Bluetooth owner is unavailable.');
  }
  return _DarwinProxyApi(platform, owner);
}

class _ScanRequest {
  const _ScanRequest(this.services, this.manufacturer, this.rssi, this.options);
  final List<String>? services;
  final Map<int, Uint8List>? manufacturer;
  final int? rssi;
  final models.PlatformDarwinScanOptions? options;

  bool accepts(models.PlatformScanResult result) {
    if (rssi case final minimum? when result.rssi < minimum) return false;
    if (services case final wanted? when wanted.isNotEmpty) {
      final advertised = result.serviceUuids.map(
        (value) => value.toLowerCase(),
      );
      if (!wanted.any((value) => advertised.contains(value.toLowerCase()))) {
        return false;
      }
    }
    if (manufacturer case final wanted? when wanted.isNotEmpty) {
      final entry = wanted.entries.first;
      final prefix = [
        entry.key & 0xff,
        (entry.key >> 8) & 0xff,
        ...entry.value,
      ];
      if (result.manufacturerDataHead.length < prefix.length) return false;
      for (var i = 0; i < prefix.length; i++) {
        if (result.manufacturerDataHead[i] != prefix[i]) return false;
      }
    }
    return true;
  }
}

class _DarwinOwnerApi extends _DarwinFfiApi {
  _DarwinOwnerApi(super.platform, this._inbox) {
    _inbox.listen(_onMessage);
    _stateController.stream.listen(
      (event) => _broadcast(['state', event.index]),
    );
    _scanController.stream.listen(_onScan);
    _l2capController.stream.listen((event) => _broadcast(_encodeL2cap(event)));
    _restorationController.stream.listen((event) {
      _restoredScanning = event.scanningRestored;
      _broadcast(_encodeRestoration(event));
    });
    _platformEventController.stream.listen((event) {
      final encoded = _encodePlatformEvent(event);
      if (encoded != null) _broadcast(encoded);
      if (event is models.PlatformConnectionStateChange &&
          event.state == models.PlatformConnectionState.disconnected) {
        _connections.remove(event.deviceId);
        _notificationClaims.removeWhere(
          (key, _) => key.startsWith('${event.deviceId}/'),
        );
      }
    });
  }

  final ReceivePort _inbox;
  final Map<String, SendPort> _clients = {};
  final Map<String, Set<String>> _connections = {};
  final Map<String, Set<String>> _notificationClaims = {};
  final Map<String, _ScanRequest> _scans = {};
  final _ownerScans = StreamController<models.PlatformScanResult>.broadcast();
  bool _restoredScanning = false;

  @override
  Stream<models.PlatformScanResult> get scanResults => _ownerScans.stream;

  void _broadcast(List<Object?> event) {
    for (final port in _clients.values) {
      port.send(event);
    }
  }

  void _sendTo(String client, List<Object?> event) {
    if (client == _ownerClient) {
      _applyLocalEvent(event);
    } else {
      _clients[client]?.send(event);
    }
  }

  void _applyLocalEvent(List<Object?> event) {
    if (event[0] == 'connection') {
      _handleConnectionStateChange(_platform, _decodeConnection(event));
    }
  }

  void _onScan(models.PlatformScanResult result) {
    if (_scans.isEmpty && _restoredScanning) {
      _ownerScans.add(result);
    }
    for (final entry in _scans.entries) {
      if (!entry.value.accepts(result)) continue;
      if (entry.key == _ownerClient) {
        _ownerScans.add(result);
      } else {
        _clients[entry.key]?.send(_encodeScan(result));
      }
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! List<Object?> || raw.isEmpty) return;
    switch (raw[0]) {
      case 'join':
        final client = raw[1] as String;
        _clients[client] = raw[2] as SendPort;
        for (final event in _restorationHistory) {
          _clients[client]?.send(_encodeRestoration(event));
        }
      case 'exit':
        _releaseClient(raw[1] as String).catchError(
          (Object error, StackTrace stack) =>
              Zone.current.handleUncaughtError(error, stack),
        );
      case 'call':
        _handleCall(raw).catchError(
          (Object error, StackTrace stack) =>
              Zone.current.handleUncaughtError(error, stack),
        );
      case 'oneway':
        _handleOneWay(raw).catchError(
          (Object error, StackTrace stack) =>
              Zone.current.handleUncaughtError(error, stack),
        );
    }
  }

  Future<void> _handleCall(List<Object?> raw) async {
    final client = raw[1] as String;
    final operation = raw[2] as String;
    final args = raw[3] as List<Object?>;
    final reply = raw[4] as SendPort;
    try {
      final value = await _dispatch(client, operation, args);
      reply.send(['ok', value]);
    } on PlatformException catch (error) {
      reply.send(['error', error.code, error.message, error.details]);
    } catch (error) {
      reply.send(['error', 'OperationFailed', error.toString(), null]);
    }
  }

  Future<void> _handleOneWay(List<Object?> raw) async {
    final client = raw[1] as String;
    final operation = raw[2] as String;
    final args = raw[3] as List<Object?>;
    try {
      await _dispatch(client, operation, args);
    } catch (error) {
      if (operation == 'writeL2cap') {
        _clients[client]?.send([
          'l2cap',
          args[0],
          null,
          error.toString(),
          false,
          false,
        ]);
      }
    }
  }

  Future<Object?> _dispatch(
    String client,
    String method,
    List<Object?> args,
  ) async {
    switch (method) {
      case 'configure':
        await configure(
          models.PlatformDarwinConfiguration(maintainState: args[0] as bool),
        );
      case 'isAppleAccessorySetupSupported':
        return isAppleAccessorySetupSupported();
      case 'showAppleAccessoryPicker':
        final item = await showAppleAccessoryPicker([
          for (final raw in args[0] as List<Object?>)
            _decodePickerItem(raw as List<Object?>),
        ]);
        return item == null ? null : [item.deviceId, item.displayName];
      case 'getAppleAccessories':
        return [
          for (final item in await getAppleAccessories())
            [item.deviceId, item.displayName],
        ];
      case 'removeAppleAccessory':
        await removeAppleAccessory(args[0] as String);
      case 'getConnectedPeripherals':
        return [
          for (final item in await getConnectedPeripherals(
            (args[0] as List<Object?>).cast<String>(),
          ))
            [item.id, item.name],
        ];
      case 'isBluetoothAvailable':
        return isBluetoothAvailable();
      case 'stateSnapshot':
        return _mapState(_getManager().state).index;
      case 'startScan':
        await _startScanFor(
          client,
          (args[0] as List?)?.cast<String>(),
          (args[1] as Map?)?.cast<int, Uint8List>(),
          args[2] as int?,
          args[3] == null
              ? null
              : models.PlatformDarwinScanOptions(
                  allowDuplicates: (args[3] as List<Object?>)[0] as bool,
                  solicitedServiceUuids:
                      ((args[3] as List<Object?>)[1] as List<Object?>)
                          .cast<String>(),
                ),
        );
      case 'stopScan':
        await _stopScanFor(client);
      case 'connect':
        await _connectFor(client, args[0] as String);
      case 'disconnect':
        await _disconnectFor(client, args[0] as String);
      case 'discoverServices':
        await discoverServices(args[0] as String);
      case 'setNotifiable':
        await _setNotifiableFor(
          client,
          args[0] as String,
          args[1] as String,
          args[2] as String,
          models.PlatformBleInputProperty.values[args[3] as int],
        );
      case 'readValue':
        return readValue(
          args[0] as String,
          args[1] as String,
          args[2] as String,
        );
      case 'writeValue':
        await writeValue(
          args[0] as String,
          args[1] as String,
          args[2] as String,
          args[3] as Uint8List,
          models.PlatformBleOutputProperty.values[args[4] as int],
        );
      case 'requestMtu':
        return requestMtu(args[0] as String, args[1] as int);
      case 'openL2cap':
        await openL2cap(args[0] as String, args[1] as int);
      case 'closeL2cap':
        closeL2cap(args[0] as String);
      case 'writeL2cap':
        writeL2cap(args[0] as String, args[1] as Uint8List);
      default:
        throw PlatformException(code: 'Unimplemented', message: method);
    }
    return null;
  }

  Future<void> _connectFor(String client, String deviceId) async {
    final claims = _connections.putIfAbsent(deviceId, () => {});
    if (!claims.add(client)) {
      await super.connect(deviceId);
      return;
    }
    try {
      await super.connect(deviceId);
    } catch (_) {
      claims.remove(client);
      if (claims.isEmpty) _connections.remove(deviceId);
      rethrow;
    }
  }

  Future<void> _disconnectFor(String client, String deviceId) async {
    final claims = _connections[deviceId];
    if (claims == null || !claims.remove(client)) {
      throw PlatformException(code: 'IllegalArgument', message: deviceId);
    }
    await _releaseNotifications(client, deviceId: deviceId);
    if (claims.isEmpty) {
      _connections.remove(deviceId);
      await super.disconnect(deviceId);
    } else {
      _sendTo(client, [
        'connection',
        deviceId,
        models.PlatformConnectionState.disconnected.index,
        models.PlatformGattStatus.success.index,
        null,
        null,
        null,
      ]);
    }
  }

  Future<void> _setNotifiableFor(
    String client,
    String deviceId,
    String service,
    String characteristic,
    models.PlatformBleInputProperty property,
  ) async {
    final key = '$deviceId/$service/$characteristic';
    final clients = _notificationClaims.putIfAbsent(key, () => {});
    if (property == models.PlatformBleInputProperty.disabled) {
      if (!clients.remove(client)) return;
      if (clients.isEmpty) {
        _notificationClaims.remove(key);
        await super.setNotifiable(deviceId, service, characteristic, property);
      }
      return;
    }
    if (!clients.add(client)) return;
    if (clients.length == 1) {
      try {
        await super.setNotifiable(deviceId, service, characteristic, property);
      } catch (_) {
        clients.remove(client);
        if (clients.isEmpty) _notificationClaims.remove(key);
        rethrow;
      }
    }
  }

  Future<void> _releaseNotifications(String client, {String? deviceId}) async {
    for (final key in _notificationClaims.keys.toList()) {
      if (deviceId != null && !key.startsWith('$deviceId/')) continue;
      final clients = _notificationClaims[key]!;
      if (!clients.remove(client)) continue;
      if (clients.isNotEmpty) continue;
      _notificationClaims.remove(key);
      final parts = key.split('/');
      try {
        await super.setNotifiable(
          parts[0],
          parts[1],
          parts[2],
          models.PlatformBleInputProperty.disabled,
        );
      } on PlatformException catch (error) {
        if (error.code != 'Disconnected' && error.code != 'NotFound') {
          rethrow;
        }
      }
    }
  }

  Future<void> _releaseClient(String client) async {
    _clients.remove(client);
    await _releaseNotifications(client);
    await _stopScanFor(client);
    for (final deviceId in _connections.keys.toList()) {
      if (_connections[deviceId]?.contains(client) == true) {
        try {
          await _disconnectFor(client, deviceId);
        } on PlatformException catch (error) {
          if (error.code != 'Disconnected' && error.code != 'IllegalArgument') {
            rethrow;
          }
        }
      }
    }
  }

  Future<void> _startScanFor(
    String client,
    List<String>? services,
    Map<int, Uint8List>? manufacturer,
    int? rssi,
    models.PlatformDarwinScanOptions? options,
  ) async {
    _restoredScanning = false;
    _scans[client] = _ScanRequest(services, manufacturer, rssi, options);
    await _applyScans();
  }

  Future<void> _stopScanFor(String client) async {
    if (client == _ownerClient && _restoredScanning) {
      _restoredScanning = false;
      if (_scans.isEmpty) await super.stopScan();
    }
    if (_scans.remove(client) != null) await _applyScans();
  }

  Future<void> _applyScans() async {
    if (_scans.isEmpty) {
      await super.stopScan();
    } else if (_scans.length == 1) {
      final request = _scans.values.single;
      await super.startScan(
        serviceUuids: request.services,
        manufacturerData: request.manufacturer,
        rssi: request.rssi,
        options: request.options,
      );
    } else {
      await super.startScan(
        options: models.PlatformDarwinScanOptions(
          allowDuplicates: true,
          solicitedServiceUuids: const [],
        ),
      );
    }
  }

  @override
  Future<void> connect(String deviceId) => _connectFor(_ownerClient, deviceId);
  @override
  Future<void> disconnect(String deviceId) =>
      _disconnectFor(_ownerClient, deviceId);
  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    models.PlatformBleInputProperty property,
  ) => _setNotifiableFor(
    _ownerClient,
    deviceId,
    service,
    characteristic,
    property,
  );
  @override
  Future<void> startScan({
    List<String>? serviceUuids,
    Map<int, Uint8List>? manufacturerData,
    int? rssi,
    models.PlatformDarwinScanOptions? options,
  }) => _startScanFor(
    _ownerClient,
    serviceUuids,
    manufacturerData,
    rssi,
    options,
  );
  @override
  Future<void> stopScan() => _stopScanFor(_ownerClient);
}

class _DarwinProxyApi implements DarwinApi {
  _DarwinProxyApi(this._platform, this._owner) {
    _id =
        '${Isolate.current.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    _owner.send(['join', _id, _inbox.sendPort]);
    Isolate.current.addOnExitListener(_owner, response: ['exit', _id]);
    _inbox.listen(_onEvent);
  }

  final QuickBlueDarwin _platform;
  final SendPort _owner;
  final ReceivePort _inbox = ReceivePort();
  late final String _id;
  final _states = StreamController<models.PlatformBluetoothState>.broadcast();
  final _scans = StreamController<models.PlatformScanResult>.broadcast();
  final _sockets =
      StreamController<models.PlatformL2CapSocketEvent>.broadcast();
  final _restorations =
      StreamController<models.PlatformDarwinRestorationEvent>.broadcast();
  final _restorationHistory = <models.PlatformDarwinRestorationEvent>[];

  Future<Object?> _call(String operation, List<Object?> args) async {
    final reply = ReceivePort();
    try {
      _owner.send(['call', _id, operation, args, reply.sendPort]);
      final result = (await reply.first) as List<Object?>;
      if (result[0] == 'error') {
        throw PlatformException(
          code: result[1] as String,
          message: result[2] as String?,
          details: result[3],
        );
      }
      return result[1];
    } finally {
      reply.close();
    }
  }

  void _onEvent(dynamic raw) {
    if (raw is! List<Object?> || raw.isEmpty) return;
    switch (raw[0]) {
      case 'state':
        _states.add(models.PlatformBluetoothState.values[raw[1] as int]);
      case 'scan':
        _scans.add(_decodeScan(raw));
      case 'l2cap':
        _sockets.add(_decodeL2cap(raw));
      case 'restoration':
        final event = _decodeRestoration(raw);
        _restorationHistory.add(event);
        _restorations.add(event);
      case 'connection':
        _handleConnectionStateChange(_platform, _decodeConnection(raw));
      case 'service':
        _handleServiceDiscovered(_platform, _decodeService(raw));
      case 'complete':
        _platform.onServiceDiscoveryComplete(raw[1] as String);
      case 'gatt':
        _platform.handleGattServicesChanged(
          raw[1] as String,
          invalidatedServiceUuids: (raw[2] as List<Object?>).cast<String>(),
        );
      case 'value':
        _handleCharacteristicValueChanged(
          _platform,
          models.PlatformCharacteristicValueChanged(
            deviceId: raw[1] as String,
            serviceUuid: raw[2] as String,
            characteristicId: raw[3] as String,
            value: raw[4] as Uint8List,
          ),
        );
    }
  }

  @override
  Stream<models.PlatformBluetoothState> get bluetoothStateEvents async* {
    yield models.PlatformBluetoothState.values[(await _call(
          'stateSnapshot',
          const [],
        ))
        as int];
    yield* _states.stream;
  }

  @override
  Stream<models.PlatformScanResult> get scanResults => _scans.stream;
  @override
  Stream<models.PlatformL2CapSocketEvent> get l2CapEvents => _sockets.stream;
  @override
  Stream<models.PlatformDarwinRestorationEvent> get restorationEvents =>
      _eventsWithHistory(_restorationHistory, _restorations.stream);

  @override
  void bootstrapIfEnabled() {}
  @override
  Future<void> configure(
    models.PlatformDarwinConfiguration configuration,
  ) async {
    await _call('configure', [configuration.maintainState]);
  }

  @override
  Future<bool> isAppleAccessorySetupSupported() async =>
      (await _call('isAppleAccessorySetupSupported', const [])) as bool;
  @override
  Future<models.PlatformAppleAccessory?> showAppleAccessoryPicker(
    List<models.PlatformAppleAccessoryPickerItem> items,
  ) async {
    final result = await _call('showAppleAccessoryPicker', [
      [for (final item in items) _encodePickerItem(item)],
    ]);
    if (result == null) return null;
    final data = result as List<Object?>;
    return models.PlatformAppleAccessory(
      deviceId: data[0] as String,
      displayName: data[1] as String,
    );
  }

  @override
  Future<List<models.PlatformAppleAccessory>> getAppleAccessories() async => [
    for (final item
        in (await _call('getAppleAccessories', const [])) as List<Object?>)
      models.PlatformAppleAccessory(
        deviceId: (item as List<Object?>)[0] as String,
        displayName: item[1] as String,
      ),
  ];
  @override
  Future<void> removeAppleAccessory(String deviceId) async {
    await _call('removeAppleAccessory', [deviceId]);
  }

  @override
  Future<List<models.Peripheral>> getConnectedPeripherals(
    List<String> serviceUuids,
  ) async => [
    for (final item
        in (await _call('getConnectedPeripherals', [serviceUuids]))
            as List<Object?>)
      models.Peripheral(
        id: (item as List<Object?>)[0] as String,
        name: item[1] as String,
      ),
  ];
  @override
  Future<bool> isBluetoothAvailable() async =>
      (await _call('isBluetoothAvailable', const [])) as bool;
  @override
  Future<void> startScan({
    List<String>? serviceUuids,
    Map<int, Uint8List>? manufacturerData,
    int? rssi,
    models.PlatformDarwinScanOptions? options,
  }) async {
    await _call('startScan', [
      serviceUuids,
      manufacturerData,
      rssi,
      options == null
          ? null
          : [options.allowDuplicates, options.solicitedServiceUuids],
    ]);
  }

  @override
  Future<void> stopScan() async {
    await _call('stopScan', const []);
  }

  @override
  Future<void> connect(String deviceId) async {
    await _call('connect', [deviceId]);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _call('disconnect', [deviceId]);
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    await _call('discoverServices', [deviceId]);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    models.PlatformBleInputProperty property,
  ) async {
    await _call('setNotifiable', [
      deviceId,
      service,
      characteristic,
      property.index,
    ]);
  }

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async =>
      (await _call('readValue', [deviceId, service, characteristic]))
          as Uint8List;
  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    models.PlatformBleOutputProperty property,
  ) async {
    await _call('writeValue', [
      deviceId,
      service,
      characteristic,
      value,
      property.index,
    ]);
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async =>
      (await _call('requestMtu', [deviceId, expectedMtu])) as int;
  @override
  Future<void> openL2cap(String deviceId, int psm) async {
    await _call('openL2cap', [deviceId, psm]);
  }

  @override
  void closeL2cap(String deviceId) {
    _owner.send([
      'oneway',
      _id,
      'closeL2cap',
      [deviceId],
    ]);
  }

  @override
  void writeL2cap(String deviceId, Uint8List value) {
    _owner.send([
      'oneway',
      _id,
      'writeL2cap',
      [deviceId, value],
    ]);
  }
}

List<Object?> _encodeScan(models.PlatformScanResult result) => [
  'scan',
  result.name,
  result.deviceId,
  result.manufacturerDataHead,
  result.manufacturerData,
  result.rssi,
  result.serviceUuids,
  result.serviceData,
];
models.PlatformScanResult _decodeScan(List<Object?> raw) =>
    models.PlatformScanResult(
      name: raw[1] as String,
      deviceId: raw[2] as String,
      manufacturerDataHead: raw[3] as Uint8List,
      manufacturerData: raw[4] as Uint8List,
      rssi: raw[5] as int,
      serviceUuids: (raw[6] as List<Object?>).cast<String>(),
      serviceData: (raw[7] as Map).cast<String, Uint8List>(),
    );
List<Object?> _encodeL2cap(models.PlatformL2CapSocketEvent event) => [
  'l2cap',
  event.deviceId,
  event.data,
  event.error,
  event.opened,
  event.closed,
];
models.PlatformL2CapSocketEvent _decodeL2cap(List<Object?> raw) =>
    models.PlatformL2CapSocketEvent(
      deviceId: raw[1] as String,
      data: raw[2] as Uint8List?,
      error: raw[3] as String?,
      opened: raw[4] as bool?,
      closed: raw[5] as bool?,
    );
List<Object?> _encodeRestoration(models.PlatformDarwinRestorationEvent event) =>
    [
      'restoration',
      event.restoredPeripheralCount,
      event.disconnectedPeripheralCount,
      event.connectingPeripheralCount,
      event.connectedPeripheralCount,
      event.disconnectingPeripheralCount,
      event.unknownPeripheralCount,
      event.scanningRestored,
      event.restoredScanServiceCount,
    ];
models.PlatformDarwinRestorationEvent _decodeRestoration(List<Object?> raw) =>
    models.PlatformDarwinRestorationEvent(
      restoredPeripheralCount: raw[1] as int,
      disconnectedPeripheralCount: raw[2] as int,
      connectingPeripheralCount: raw[3] as int,
      connectedPeripheralCount: raw[4] as int,
      disconnectingPeripheralCount: raw[5] as int,
      unknownPeripheralCount: raw[6] as int,
      scanningRestored: raw[7] as bool,
      restoredScanServiceCount: raw[8] as int,
    );
List<Object?>? _encodePlatformEvent(Object event) {
  if (event is models.PlatformConnectionStateChange) {
    return [
      'connection',
      event.deviceId,
      event.state.index,
      event.gattStatus.index,
      event.errorDomain,
      event.errorCode,
      event.errorMessage,
    ];
  }
  if (event is models.PlatformServiceDiscovered) {
    return [
      'service',
      event.deviceId,
      event.serviceUuid,
      [
        for (final item in event.characteristics)
          [
            item.uuid,
            item.canRead,
            item.canWriteWithResponse,
            item.canWriteWithoutResponse,
            item.canNotify,
            item.canIndicate,
          ],
      ],
    ];
  }
  if (event is _DarwinDiscoveryComplete) return ['complete', event.deviceId];
  if (event is _DarwinGattChanged) {
    return ['gatt', event.deviceId, event.serviceUuids];
  }
  if (event is models.PlatformCharacteristicValueChanged) {
    return [
      'value',
      event.deviceId,
      event.serviceUuid,
      event.characteristicId,
      event.value,
    ];
  }
  return null;
}

models.PlatformConnectionStateChange _decodeConnection(List<Object?> raw) =>
    models.PlatformConnectionStateChange(
      deviceId: raw[1] as String,
      state: models.PlatformConnectionState.values[raw[2] as int],
      gattStatus: models.PlatformGattStatus.values[raw[3] as int],
      errorDomain: raw[4] as String?,
      errorCode: raw[5] as int?,
      errorMessage: raw[6] as String?,
    );
models.PlatformServiceDiscovered _decodeService(List<Object?> raw) =>
    models.PlatformServiceDiscovered(
      deviceId: raw[1] as String,
      serviceUuid: raw[2] as String,
      characteristics: [
        for (final value in raw[3] as List<Object?>)
          models.PlatformCharacteristic(
            uuid: (value as List<Object?>)[0] as String,
            canRead: value[1] as bool,
            canWriteWithResponse: value[2] as bool,
            canWriteWithoutResponse: value[3] as bool,
            canNotify: value[4] as bool,
            canIndicate: value[5] as bool,
          ),
      ],
    );
List<Object?> _encodePickerItem(models.PlatformAppleAccessoryPickerItem item) =>
    [
      item.displayName,
      item.productImage,
      item.discovery.serviceUuid,
      item.discovery.nameSubstring,
      item.discovery.serviceData,
      item.discovery.serviceDataMask,
      item.discovery.immediate,
      item.migrationDeviceId,
    ];
models.PlatformAppleAccessoryPickerItem _decodePickerItem(List<Object?> raw) =>
    models.PlatformAppleAccessoryPickerItem(
      displayName: raw[0] as String,
      productImage: raw[1] as Uint8List,
      discovery: models.PlatformAppleAccessoryDiscovery(
        serviceUuid: raw[2] as String,
        nameSubstring: raw[3] as String?,
        serviceData: raw[4] as Uint8List?,
        serviceDataMask: raw[5] as Uint8List?,
        immediate: raw[6] as bool,
      ),
      migrationDeviceId: raw[7] as String?,
    );
