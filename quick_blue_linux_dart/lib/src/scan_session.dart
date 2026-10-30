import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'scan_filter.dart';
import 'uuid_rules.dart';

/// Owns one client's discovery filters, scan results and property watches.
/// The platform shell retains initialization, adapter selection and device cache.
class LinuxScanSession {
  LinuxScanSession({
    required BlueZClient client,
    required void Function(BlueZDevice) onTrackDevice,
    required Logger logger,
    bool Function(BlueZDevice)? acceptsDevice,
  }) : _client = client,
       _acceptsDevice = acceptsDevice,
       _onTrackDevice = onTrackDevice,
       _logger = logger {
    _scanResultController = StreamController<BlueScanResult>.broadcast(
      onListen: _emitKnownScanResults,
    );
  }

  final BlueZClient _client;
  final bool Function(BlueZDevice)? _acceptsDevice;
  final void Function(BlueZDevice) _onTrackDevice;
  final Logger _logger;
  final _scanDevicePropertySubscriptions =
      <String, StreamSubscription<List<String>>>{};
  static const _scanResultProperties = <String>{
    'Alias',
    'ManufacturerData',
    'Name',
    'RSSI',
    'ServiceData',
    'UUIDs',
  };
  Set<String> _activeScanServiceUuids = const <String>{};
  Map<String, Uint8List>? _activeScanServiceData;
  Map<int, Uint8List>? _activeScanManufacturerData;
  int? _activeScanRssi;
  LinuxScanOptions _activeScanOptions = const LinuxScanOptions();
  var _isScanning = false;

  late final StreamController<BlueScanResult> _scanResultController;

  Stream<BlueScanResult> get results => _scanResultController.stream;

  Future<void> close() async {
    await _clearScanDevicePropertySubscriptions();
    _scanResultController.close().then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _logger.warning('Unable to close scan results', error, stack);
      },
    );
  }

  Future<void> start(
    BlueZAdapter adapter,
    ScanFilter scanFilter,
    ScanOptions scanOptions,
  ) async {
    _activeScanServiceUuids = scanFilter.serviceUuids
        .map(canonicalizeUuid)
        .toSet();
    _activeScanServiceData = scanFilter.serviceData;
    _activeScanManufacturerData = scanFilter.manufacturerData;
    _activeScanRssi = scanFilter.rssi ?? scanOptions.linux.rssi;
    _activeScanOptions = scanOptions.linux;
    await _setDiscoveryFilter(adapter, scanFilter, scanOptions);
    await adapter.startDiscovery();
    _isScanning = true;
  }

  Future<void> stop(BlueZAdapter? adapter) async {
    _isScanning = false;

    if (adapter == null) {
      await _clearScanDevicePropertySubscriptions();
      _activeScanServiceUuids = const <String>{};
      _activeScanServiceData = null;
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
      _activeScanServiceData = null;
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

  void deviceAdded(BlueZDevice device) {
    _trackDevice(device);
    _emitScanResult(device);
  }

  Future<void> removeDevice(String deviceId) async {
    await _scanDevicePropertySubscriptions.remove(deviceId)?.cancel();
  }

  Future<void> _clearScanDevicePropertySubscriptions() async {
    final subscriptions = _scanDevicePropertySubscriptions.values.toList();
    _scanDevicePropertySubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  void _trackDevice(BlueZDevice device) {
    if (!(_acceptsDevice?.call(device) ?? true)) return;
    _onTrackDevice(device);
    if (_isScanning) {
      _watchScanDeviceProperties(device);
    }
  }

  void _emitScanResult(BlueZDevice device) {
    if (!(_acceptsDevice?.call(device) ?? true)) return;
    if (!_isScanning) {
      return;
    }
    if (!_matchesScanFilter(device)) {
      return;
    }

    final manufacturerData = device.advertisedManufacturerData;
    final result = BlueScanResult(
      deviceId: device.address,
      name: device.alias.isEmpty ? device.name : device.alias,
      manufacturerDataHead: manufacturerData.head,
      manufacturerData: manufacturerData.payload,
      rssi: device.rssi,
      serviceUuids: device.uuids
          .map((uuid) => formatUuid(uuid))
          .toList(growable: false),
      serviceData: device.serviceData.map(
        (uuid, value) => MapEntry(formatUuid(uuid), Uint8List.fromList(value)),
      ),
    );
    if (!matchesServiceDataFilter(_activeScanServiceData, result.serviceData)) {
      return;
    }
    _scanResultController.add(result);
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

  Future<void> _setDiscoveryFilter(
    BlueZAdapter adapter,
    ScanFilter scanFilter,
    ScanOptions scanOptions,
  ) {
    final serviceUuids = scanFilter.serviceUuids
        .map(canonicalizeUuid)
        .map(canonicalToDashed)
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
          .map(bluezUuidToCanonical)
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
