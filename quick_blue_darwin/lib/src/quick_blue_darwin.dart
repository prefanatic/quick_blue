import 'dart:async';
import 'dart:typed_data';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'messages.g.dart' as messages;

class QuickBlueDarwin extends QuickBluePlatform {
  QuickBlueDarwin();

  final messages.QuickBlueApi _api = messages.QuickBlueApi();
  messages.QuickBlueFlutterApi? _flutterApi;
  late final Stream<BlueBluetoothState> _bluetoothStateStream = messages
      .bluetoothState()
      .map((state) => state.toBlueBluetoothState())
      .distinct();

  final Stream<messages.PlatformL2CapSocketEvent> _l2CapEventStream = messages
      .l2CapSocketEvents();

  static void registerWith() {
    QuickBluePlatform.instance = QuickBlueDarwin();
  }

  void _ensureInitialized() {
    if (_flutterApi != null) return;
    _flutterApi = _FlutterApi(
      onConnectionChangedCallback: (deviceId, state, status) {
        onConnectionChanged?.call(deviceId, state, status);
      },
      onServiceDiscoveredCallback: (deviceId, serviceId, characteristicIds) {
        onServiceDiscovered?.call(deviceId, serviceId, characteristicIds);
      },
      onServiceDiscoveryCompleteCallback: (deviceId) {
        onServiceDiscoveryComplete(deviceId);
      },
      onValueChangedCallback: (deviceId, characteristicId, value) {
        onValueChanged?.call(deviceId, characteristicId, value);
      },
    );
    messages.QuickBlueFlutterApi.setUp(_flutterApi);
  }

  // Companion device association is an Android CompanionDeviceManager feature
  // with no CoreBluetooth equivalent on iOS/macOS.
  static const _companionUnsupported =
      'Companion device association is not supported on iOS/macOS '
      '(no CoreBluetooth equivalent for Android CompanionDeviceManager).';

  @override
  Future<CompanionDevice?> companionAssociate({
    String? deviceId,
    ScanFilter? scanFilter,
  }) async {
    throw UnsupportedError(_companionUnsupported);
  }

  @override
  Future<void> companionDisassociate(int associationId) {
    throw UnsupportedError(_companionUnsupported);
  }

  @override
  Future<List<CompanionDevice>?> getCompanionAssociations() async {
    throw UnsupportedError(_companionUnsupported);
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
  Stream<BlueBluetoothState> get bluetoothStateStream {
    _ensureInitialized();

    return _bluetoothStateStream;
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) async {
    _ensureInitialized();

    await _api.openL2cap(deviceId, psm);

    // Wait for the open status.
    await _l2CapEventStream
        .where((event) => event.deviceId == deviceId)
        .firstWhere((event) => event.opened == true)
        .timeout(const Duration(seconds: 5));
    print('L2CAP socket opened for device: $deviceId');

    return BleL2capSocket(
      sink: _L2capSink(api: _api, deviceId: deviceId),
      stream: _l2CapEventStream
          .where((event) => event.deviceId == deviceId)
          .map((e) {
            if (e.data != null) {
              return BleL2CapSocketEventData(
                deviceId: e.deviceId,
                data: e.data!,
              );
            } else if (e.error != null) {
              return BleL2CapSocketEventError(
                deviceId: e.deviceId,
                error: e.error,
              );
            } else if (e.opened == true) {
              return BleL2CapSocketEventOpened(deviceId: e.deviceId);
            } else if (e.closed == true) {
              return BleL2CapSocketEventClosed(deviceId: e.deviceId);
            }

            throw Exception('Unknown L2CAP event: $e');
          }),
    );
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) {
    _ensureInitialized();

    return _api.readValue(deviceId, service, characteristic);
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    _ensureInitialized();

    return _api.requestMtu(deviceId, expectedMtu);
  }

  @override
  Stream<BlueScanResult> get scanResultStream => messages.scanResults().map(
    (item) => BlueScanResult(
      deviceId: item.deviceId,
      name: item.name,
      rssi: item.rssi,
      serviceUuids: item.serviceUuids,
      manufacturerDataHead: item.manufacturerDataHead,
      manufacturerData: item.manufacturerData,
      serviceData: item.serviceData,
    ),
  );

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    _ensureInitialized();

    return _api.setNotifiable(
      deviceId,
      service,
      characteristic,
      bleInputProperty.toPlatformBleInputProperty(),
    );
  }

  @override
  Future<void> startScan({ScanFilter scanFilter = ScanFilter.empty}) {
    _ensureInitialized();

    final serviceUuids = scanFilter.serviceUuids.isEmpty
        ? null
        : scanFilter.serviceUuids;
    final manufacturerData = scanFilter.manufacturerData?.isEmpty == true
        ? null
        : scanFilter.manufacturerData;

    return _api.startScan(
      serviceUuids: serviceUuids,
      manufacturerData: manufacturerData,
    );
  }

  @override
  Future<void> stopScan() {
    _ensureInitialized();

    return _api.stopScan();
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

    return _api.writeValue(
      deviceId,
      service,
      characteristic,
      value,
      bleOutputProperty.toPlatformBleOutputProperty(),
    );
  }
}

class _L2capSink implements EventSink<Uint8List> {
  _L2capSink({required this.api, required this.deviceId});

  final messages.QuickBlueApi api;
  final String deviceId;

  @override
  void add(Uint8List event) {
    api.writeL2cap(deviceId, event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future close() async {}
}

class _FlutterApi extends messages.QuickBlueFlutterApi {
  _FlutterApi({
    required this.onConnectionChangedCallback,
    required this.onServiceDiscoveredCallback,
    required this.onServiceDiscoveryCompleteCallback,
    required this.onValueChangedCallback,
  });

  final OnConnectionChanged onConnectionChangedCallback;
  final OnServiceDiscovered onServiceDiscoveredCallback;
  final OnServiceDiscoveryComplete onServiceDiscoveryCompleteCallback;
  final OnValueChanged onValueChangedCallback;

  @override
  void onCharacteristicValueChanged(
    messages.PlatformCharacteristicValueChanged valueChanged,
  ) {
    onValueChangedCallback.call(
      valueChanged.deviceId,
      valueChanged.characteristicId,
      valueChanged.value,
    );
  }

  @override
  void onConnectionStateChange(
    messages.PlatformConnectionStateChange stateChange,
  ) {
    final state = switch (stateChange.state) {
      messages.PlatformConnectionState.disconnected =>
        BlueConnectionState.disconnected,
      messages.PlatformConnectionState.connected =>
        BlueConnectionState.connected,
      _ => null,
    };
    if (state == null) return;

    onConnectionChangedCallback.call(
      stateChange.deviceId,
      state,
      stateChange.gattStatus.toBleStatus(),
    );
  }

  @override
  void onServiceDiscovered(
    messages.PlatformServiceDiscovered serviceDiscovered,
  ) {
    onServiceDiscoveredCallback.call(
      serviceDiscovered.deviceId,
      serviceDiscovered.serviceUuid,
      serviceDiscovered.characteristics,
    );
  }

  @override
  void onServiceDiscoveryComplete(String deviceId) {
    onServiceDiscoveryCompleteCallback.call(deviceId);
  }
}

extension _BleInputPropertyExtension on BleInputProperty {
  messages.PlatformBleInputProperty toPlatformBleInputProperty() {
    if (this == BleInputProperty.disabled) {
      return messages.PlatformBleInputProperty.disabled;
    } else if (this == BleInputProperty.notification) {
      return messages.PlatformBleInputProperty.notification;
    } else if (this == BleInputProperty.indication) {
      return messages.PlatformBleInputProperty.indication;
    } else {
      throw ArgumentError('Unknown BleInputProperty: $this');
    }
  }
}

extension _BleOutputPropertyExtension on BleOutputProperty {
  messages.PlatformBleOutputProperty toPlatformBleOutputProperty() {
    if (this == BleOutputProperty.withResponse) {
      return messages.PlatformBleOutputProperty.withResponse;
    } else if (this == BleOutputProperty.withoutResponse) {
      return messages.PlatformBleOutputProperty.withoutResponse;
    } else {
      throw ArgumentError('Unknown BleOutputProperty: $this');
    }
  }
}

extension _BleStatusExtension on messages.PlatformGattStatus {
  BleStatus toBleStatus() {
    switch (this) {
      case messages.PlatformGattStatus.success:
        return BleStatus.success;
      case messages.PlatformGattStatus.failure:
        return BleStatus.failure;
    }
  }
}

extension _BluetoothStateExtension on messages.PlatformBluetoothState {
  BlueBluetoothState toBlueBluetoothState() {
    switch (this) {
      case messages.PlatformBluetoothState.unknown:
        return BlueBluetoothState.unknown;
      case messages.PlatformBluetoothState.unavailable:
        return BlueBluetoothState.unavailable;
      case messages.PlatformBluetoothState.unauthorized:
        return BlueBluetoothState.unauthorized;
      case messages.PlatformBluetoothState.poweredOff:
        return BlueBluetoothState.poweredOff;
      case messages.PlatformBluetoothState.poweredOn:
        return BlueBluetoothState.poweredOn;
    }
  }
}
