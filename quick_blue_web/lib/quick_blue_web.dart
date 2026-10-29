// The binding package substitutes non-JS stubs during native analysis. On web
// these extension types are JS EventTargets; this library is web-only.
// ignore_for_file: invalid_runtime_check_with_js_interop_types

/// Web Bluetooth backend. Chooser access is separate from raw scanning.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_web_bluetooth/js_web_bluetooth.dart' as browser;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:web/web.dart' as web;

String _uuid(String value) {
  var hex = value.toLowerCase();
  if (RegExp(r'^[0-9a-f]{4}$').hasMatch(hex)) hex = '0000$hex';
  if (RegExp(r'^[0-9a-f]{8}$').hasMatch(hex)) {
    return '$hex-0000-1000-8000-00805f9b34fb';
  }
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  ).hasMatch(hex)) {
    throw ArgumentError.value(
      value,
      'uuid',
      'Expected a 16, 32 or 128-bit UUID',
    );
  }
  return hex;
}

Uint8List _bytes(ByteData value) => Uint8List.fromList(
  value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
);

class _Session {
  _Session(this.device);
  final browser.WebBluetoothDevice device;
  final waiters = <void Function()>{};
  final characteristics =
      <String, browser.WebBluetoothRemoteGATTCharacteristic>{};
  final listeners = <String, web.EventListener>{};
  web.EventListener? disconnected;
  bool connected = false;
  final notificationClosers = <Future<void> Function()>[];
}

/// Federated browser implementation. Every promise wait has a finite deadline.
class QuickBlueWeb extends QuickBluePlatform {
  QuickBlueWeb({this.operationTimeout = const Duration(seconds: 20)}) {
    if (operationTimeout <= Duration.zero) {
      throw ArgumentError.value(operationTimeout);
    }
  }

  final Duration operationTimeout;
  final _devices = <String, browser.WebBluetoothDevice>{};
  final _sessions = <String, _Session>{};
  final _pending = <String, int>{};
  final _retiring = <String, Future<void>>{};
  Object? _chooser;

  static void registerWith(Registrar registrar) {
    QuickBluePlatform.instance = QuickBlueWeb();
  }

  QuickBlueException _error(
    String operation,
    String message, [
    QuickBlueErrorCode code = QuickBlueErrorCode.unsupported,
  ]) => QuickBlueException(code: code, operation: operation, message: message);

  Never _unsupported(String operation) => throw _error(
    operation,
    '$operation is not exposed by Web Bluetooth. Use requestDevice for chooser access; native scanning, bonding, MTU and L2CAP are unavailable.',
  );

  void _checkBrowser() {
    if (!web.window.isSecureContext) {
      throw _error(
        'requestDevice',
        'Use HTTPS or localhost: Web Bluetooth requires a secure context.',
        QuickBlueErrorCode.unavailable,
      );
    }
    if (!browser.Bluetooth.isBluetoothAPISupported()) {
      throw _error(
        'requestDevice',
        'Web Bluetooth is unavailable. Use a supported Chromium browser and check browser/Permissions-Policy settings.',
      );
    }
  }

  Future<T> _bounded<T>(
    String operation,
    Future<T> future, {
    _Session? session,
  }) async {
    final ended = Completer<T>();
    void cancel() => ended.completeError(
      _error(
        operation,
        'Device session ended; reconnect and rediscover.',
        QuickBlueErrorCode.cancelled,
      ),
    );
    session?.waiters.add(cancel);
    if (session != null) {
      final id = session.device.id;
      _pending[id] = (_pending[id] ?? 0) + 1;
      future = future.whenComplete(() {
        final remaining = (_pending[id] ?? 1) - 1;
        if (remaining == 0) {
          _pending.remove(id);
        } else {
          _pending[id] = remaining;
        }
      });
    }
    try {
      final result =
          await (session == null
                  ? future
                  : Future.any<T>([future, ended.future]))
              .timeout(operationTimeout);
      if (session != null &&
          !identical(_sessions[session.device.id], session)) {
        throw _error(
          operation,
          'Stale device session.',
          QuickBlueErrorCode.cancelled,
        );
      }
      return result;
    } on TimeoutException {
      if (session != null) _end(session);
      throw _error(
        operation,
        'Browser operation timed out; its physical work may still complete.',
        QuickBlueErrorCode.operationFailed,
      );
    } on QuickBlueException {
      rethrow;
    } catch (error) {
      throw QuickBlueException(
        operation: operation,
        message:
            'Browser rejected $operation: $error. Check permission, user gesture, service authorization and peripheral state.',
        code: QuickBlueErrorCode.operationFailed,
        details:
            operation == 'requestDevice' && error is browser.DeviceNotFoundError
            ? const {'chooserNotFound': true}
            : null,
      );
    } finally {
      session?.waiters.remove(cancel);
    }
  }

  @override
  Future<BluetoothDevice> requestDevice({
    List<String> serviceUuids = const [],
    List<String> optionalServices = const [],
    String? namePrefix,
  }) {
    // Deliberately no async preflight: requestDevice runs in this call stack.
    try {
      _checkBrowser();
      if (_chooser != null) {
        throw _error(
          'requestDevice',
          'A chooser is already pending.',
          QuickBlueErrorCode.deviceBusy,
        );
      }
      if (namePrefix != null && namePrefix.isEmpty) {
        throw ArgumentError.value(namePrefix);
      }
      final services = serviceUuids.map(_uuid).toList();
      final options = browser.RequestOptions.create(
        filters: services.isEmpty && namePrefix == null
            ? null
            : [
                browser.BluetoothScanFilter.create(
                  services: services.isEmpty ? null : services,
                  namePrefix: namePrefix,
                ),
              ],
        acceptAllDevices: services.isEmpty && namePrefix == null,
        optionalServices: optionalServices.map(_uuid).toList(),
      );
      final token = Object();
      _chooser = token;
      final pending = browser.Bluetooth.requestDevice(options).whenComplete(() {
        if (identical(_chooser, token)) _chooser = null;
      });
      return _select(pending);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  Future<BluetoothDevice> _select(
    Future<browser.WebBluetoothDevice> pending,
  ) async {
    final selected = await _bounded('requestDevice', pending);
    _devices[selected.id] = selected;
    return device(selected.id);
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    if (!web.window.isSecureContext ||
        !browser.Bluetooth.isBluetoothAPISupported()) {
      return false;
    }
    return _bounded(
      'isBluetoothAvailable',
      browser.Bluetooth.getAvailability(),
    );
  }

  @override
  Stream<BlueBluetoothState> get bluetoothStateEvents async* {
    // getAvailability is not a power/permission guarantee.
    yield await isBluetoothAvailable()
        ? BlueBluetoothState.unknown
        : BlueBluetoothState.unavailable;
  }

  @override
  Future<void> configure({bool maintainState = false}) async {
    if (maintainState) _unsupported('configure(maintainState)');
  }

  @override
  Future<QuickBlueCapabilities> capabilities() async =>
      const QuickBlueCapabilities(
        bonding: BluetoothBondingCapability.unsupported,
        mtu: BluetoothMtuCapability.unsupported,
        gattServiceChanges: BluetoothGattServiceChangeCapability.unsupported,
        connectedDeviceLookup:
            BluetoothConnectedDeviceLookupCapability.unsupported,
        supportsL2capSockets: false,
        supportsCompanionAssociation: false,
        supportsAppleAccessorySetup: false,
      );

  void _end(_Session session) {
    final id = session.device.id;
    if (!identical(_sessions[id], session)) return;
    _sessions.remove(id);
    for (final cancel in List.of(session.waiters)) {
      cancel();
    }
    session.waiters.clear();
    if (session.notificationClosers.isNotEmpty) {
      final closing = Future.wait(
        List.of(session.notificationClosers).map((close) => close()),
      );
      final settled = closing.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          // Release errors are delivered to the owning stream by its closer.
        },
      );
      _retiring[id] = settled;
      settled.then<void>((_) {
        if (identical(_retiring[id], settled)) _retiring.remove(id);
      });
    }
    for (final entry in session.listeners.entries) {
      (session.characteristics[entry.key]! as web.EventTarget)
          .removeEventListener('characteristicvaluechanged', entry.value);
    }
    session.listeners.clear();
    if (session.disconnected != null) {
      (session.device as web.EventTarget).removeEventListener(
        'gattserverdisconnected',
        session.disconnected!,
      );
    }
    session.device.gatt?.disconnect();
    handleConnectionStateChanged(
      id,
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
  }

  _Session _session(String id) {
    final session = _sessions[id];
    if (session == null || !session.connected) {
      throw _error(
        'gatt',
        'Connect and discover before GATT operations.',
        QuickBlueErrorCode.invalidState,
      );
    }
    return session;
  }

  @override
  Future<void> connect(String deviceId) async {
    final selected = _devices[deviceId];
    if (selected == null) {
      throw _error(
        'connect',
        'Select this device with requestDevice first.',
        QuickBlueErrorCode.notFound,
      );
    }
    if (_sessions.containsKey(deviceId) ||
        _pending.containsKey(deviceId) ||
        _retiring.containsKey(deviceId)) {
      throw _error(
        'connect',
        'Device session or uncancellable browser work is still active. Wait for settlement or reload the page.',
        QuickBlueErrorCode.invalidState,
      );
    }
    final session = _Session(selected);
    _sessions[deviceId] = session;
    void disconnected(web.Event event) {
      _end(session);
    }

    session.disconnected = disconnected.toJS;
    (selected as web.EventTarget).addEventListener(
      'gattserverdisconnected',
      session.disconnected!,
    );
    try {
      final server = selected.gatt;
      if (server == null) {
        throw _error(
          'connect',
          'Selected device has no GATT server.',
          QuickBlueErrorCode.unavailable,
        );
      }
      final pending = server.connect().then((result) {
        if (!identical(_sessions[deviceId], session)) {
          // A late connect must not be adopted by a newer session.
          result.disconnect();
          throw _error(
            'connect',
            'Late connection discarded.',
            QuickBlueErrorCode.cancelled,
          );
        }
        return result;
      });
      await _bounded('connect', pending, session: session);
      session.connected = true;
      handleConnectionStateChanged(
        deviceId,
        BlueConnectionState.connected,
        BleStatus.success,
      );
    } catch (_) {
      _end(session);
      rethrow;
    }
  }

  @override
  Future<void> disconnect(String deviceId) =>
      runDisconnectRequest(deviceId, () async {
        final session = _sessions[deviceId];
        if (session != null) {
          _end(session);
        } else {
          handleConnectionStateChanged(
            deviceId,
            BlueConnectionState.disconnected,
            BleStatus.success,
          );
        }
      });

  String _key(String service, String characteristic) =>
      '${_uuid(service)}/${_uuid(characteristic)}';
  browser.WebBluetoothRemoteGATTCharacteristic _characteristic(
    _Session session,
    String service,
    String characteristic,
  ) {
    final found = session.characteristics[_key(service, characteristic)];
    if (found == null) {
      throw _error(
        'gatt',
        'Characteristic absent or not authorized; rediscover using declared services.',
        QuickBlueErrorCode.notFound,
      );
    }
    return found;
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    final session = _session(deviceId);
    final found = await _bounded('discoverServices', () async {
      final services = await session.device.gatt!.getPrimaryServices();
      final result =
          <String, List<browser.WebBluetoothRemoteGATTCharacteristic>>{};
      for (final service in services) {
        final chars = await service.getCharacteristics();
        if (result.containsKey(service.uuid)) {
          throw _error(
            'discoverServices',
            'Duplicate service UUID cannot be addressed unambiguously.',
            QuickBlueErrorCode.ambiguous,
          );
        }
        final ids = chars.map((c) => c.uuid).toSet();
        if (ids.length != chars.length) {
          throw _error(
            'discoverServices',
            'Duplicate characteristic UUID cannot be addressed unambiguously.',
            QuickBlueErrorCode.ambiguous,
          );
        }
        result[service.uuid] = chars;
      }
      return result;
    }(), session: session);
    // Publish only a complete, current discovery. Preserve active event targets.
    if (session.listeners.isNotEmpty) {
      throw _error(
        'discoverServices',
        'Cancel notifications before rediscovery.',
        QuickBlueErrorCode.invalidState,
      );
    }
    session.characteristics.clear();
    for (final entry in found.entries) {
      for (final c in entry.value) {
        session.characteristics[_key(entry.key, c.uuid)] = c;
      }
      handleServiceDiscovered(
        deviceId,
        entry.key,
        entry.value
            .map(
              (c) => BluetoothCharacteristicInfo(
                uuid: c.uuid,
                canRead: c.properties.read,
                canWriteWithResponse: c.properties.write,
                canWriteWithoutResponse: c.properties.writeWithoutResponse,
                canNotify: c.properties.notify,
                canIndicate: c.properties.indicate,
              ),
            )
            .toList(),
      );
    }
    onServiceDiscoveryComplete(deviceId);
  }

  @override
  Future<Uint8List> readCharacteristicValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    final session = _session(deviceId);
    final value = await _bounded(
      'read',
      _characteristic(session, service, characteristic).readValue(),
      session: session,
    );
    return _bytes(value);
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    final value = await readCharacteristicValue(
      deviceId,
      service,
      characteristic,
    );
    handleCharacteristicValueChanged(
      deviceId,
      _uuid(service),
      _uuid(characteristic),
      value,
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
    final session = _session(deviceId);
    final c = _characteristic(session, service, characteristic);
    // Bindings pass ArrayBuffer: copy a view so unrelated backing bytes cannot leak.
    final copy = Uint8List.fromList(value);
    await _bounded(
      'write',
      bleOutputProperty == BleOutputProperty.withResponse
          ? c.writeValueWithResponse(copy)
          : c.writeValueWithoutResponse(copy),
      session: session,
    );
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    if (bleInputProperty == BleInputProperty.disabled &&
        !_sessions.containsKey(deviceId)) {
      return;
    }
    final session = _session(deviceId);
    final key = _key(service, characteristic);
    final c = _characteristic(session, service, characteristic);
    if (bleInputProperty == BleInputProperty.disabled) {
      final callback = session.listeners.remove(key);
      if (callback != null) {
        (c as web.EventTarget).removeEventListener(
          'characteristicvaluechanged',
          callback,
        );
      }
      await _bounded(
        'stopNotifications',
        c.stopNotifications(),
        session: session,
      );
      return;
    }
    if (session.listeners.containsKey(key)) return;
    if ((bleInputProperty == BleInputProperty.notification &&
            !c.properties.notify) ||
        (bleInputProperty == BleInputProperty.indication &&
            !c.properties.indicate)) {
      throw _error(
        'startNotifications',
        'Requested subscription mode is not supported by this characteristic.',
      );
    }
    void changed(web.Event event) {
      if (identical(_sessions[deviceId], session) &&
          session.listeners.containsKey(key)) {
        final value = c.value;
        if (value != null) {
          handleCharacteristicValueChanged(
            deviceId,
            _uuid(service),
            _uuid(characteristic),
            _bytes(value),
          );
        }
      }
    }

    final callback = changed.toJS;
    session.listeners[key] = callback;
    (c as web.EventTarget).addEventListener(
      'characteristicvaluechanged',
      callback,
    );
    try {
      await _bounded(
        'startNotifications',
        c.startNotifications(),
        session: session,
      );
    } catch (_) {
      (c as web.EventTarget).removeEventListener(
        'characteristicvaluechanged',
        callback,
      );
      if (identical(session.listeners[key], callback)) {
        session.listeners.remove(key);
      }
      // Rejection can leave browser subscription state uncertain; discard session.
      _end(session);
      rethrow;
    }
  }

  @override
  Stream<Uint8List> characteristicNotifications(
    String deviceId,
    String service,
    String characteristic, {
    BleInputProperty bleInputProperty = BleInputProperty.notification,
  }) {
    final controller = StreamController<Uint8List>();
    Future<void>? release;
    controller.onListen = () {
      try {
        final session = _session(deviceId);
        final subscription = super
            .characteristicNotifications(
              deviceId,
              service,
              characteristic,
              bleInputProperty: bleInputProperty,
            )
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: () {
                controller.close().then<void>(
                  (_) {},
                  onError: controller.addError,
                );
              },
            );
        late Future<void> Function() close;
        Future<void> cancel() {
          session.notificationClosers.remove(close);
          return release ??= subscription.cancel();
        }

        close = () async {
          controller.addError(
            _error(
              'notifications',
              'Device session ended. Subscribe again after reconnect and discovery.',
              QuickBlueErrorCode.cancelled,
            ),
          );
          try {
            await cancel();
          } catch (error, stack) {
            controller.addError(error, stack);
          }
          // Do not let an application-paused listener block native retirement.
          controller.close().then<void>((_) {}, onError: controller.addError);
        };
        session.notificationClosers.add(close);
        controller.onCancel = cancel;
      } catch (error, stack) {
        controller.addError(error, stack);
        controller.close().then<void>((_) {}, onError: controller.addError);
      }
    };
    return controller.stream;
  }

  @override
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) async => _unsupported('startScan');
  @override
  Future<void> stopScan() async => _unsupported('stopScan');
  @override
  Stream<BlueScanResult> get scanResultStream => Stream.error(
    _error('scan', 'Raw advertisements are unavailable; use requestDevice.'),
  );
  @override
  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const [],
  }) async => _unsupported('connectedDevices');
  @override
  Future<BluetoothBondState> bondState(String deviceId) async =>
      _unsupported('bondState');
  @override
  Future<void> pair(String deviceId) async => _unsupported('pair');
  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async =>
      _unsupported('requestMtu');
  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) async =>
      _unsupported('openL2cap');
  @override
  Future<bool> isCompanionAssociationSupported() async => false;
  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async => _unsupported('companionAssociate');
  @override
  Future<void> companionDisassociate(int associationId) async =>
      _unsupported('companionDisassociate');
  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async =>
      _unsupported('getCompanionAssociations');
}
