import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart'
    show QuickBluePlatform;

import 'ble_value_codec.dart';

const scanDuration = Duration(seconds: 10);
const defaultConnectTimeout = Duration(seconds: 15);
const deviceSwitchDisconnectTimeout = Duration(seconds: 3);

class BleEvent {
  const BleEvent({
    required this.timestamp,
    required this.message,
    required this.severity,
  });

  final DateTime timestamp;
  final String message;
  final BleEventSeverity severity;
}

enum BleEventSeverity { info, warning, error }

class BleExplorerController extends ChangeNotifier {
  BleExplorerController({this.connectTimeout = defaultConnectTimeout}) {
    final completer = Completer<void>();
    _initialBluetoothCheck = completer;
    initialBluetoothCheck = completer.future;
    _startBluetoothStateUpdates();
  }

  final Duration connectTimeout;
  final devices = <String, BlueScanResult>{};
  final services = <BluetoothService>[];
  final latestValues = <String, Uint8List>{};
  final events = <BleEvent>[];

  late final Future<void> initialBluetoothCheck;
  final serviceFilterController = TextEditingController();
  final androidReportDelayMillisController = TextEditingController();
  final darwinSolicitedServiceUuidsController = TextEditingController();
  final linuxRssiController = TextEditingController();
  final linuxPathlossController = TextEditingController();
  final linuxPatternController = TextEditingController();
  final windowsInRangeThresholdController = TextEditingController();
  final windowsOutOfRangeThresholdController = TextEditingController();
  final windowsOutOfRangeTimeoutMillisController = TextEditingController();
  final windowsSamplingIntervalMillisController = TextEditingController();

  final _writeControllers = <String, TextEditingController>{};
  final _writeWithoutResponseKeys = <String>{};
  final _notificationSubscriptions = <String, StreamSubscription<Uint8List>>{};

  Completer<void>? _initialBluetoothCheck;
  StreamSubscription<BlueBluetoothState>? _bluetoothStateSubscription;
  StreamSubscription<BlueScanResult>? _scanSubscription;
  StreamSubscription<BluetoothConnectionStateChange>? _connectionSubscription;
  Timer? _scanTimer;
  Future<void> _connectionRelease = Future<void>.value();
  var _connectionAttempt = 0;

  BlueBluetoothState bluetoothState = BlueBluetoothState.unknown;
  bool bluetoothAvailable = false;
  bool availabilityChecked = false;
  bool scanning = false;
  bool connecting = false;
  bool discovering = false;
  Duration scanRemaining = Duration.zero;
  String? selectedDeviceId;
  BlueConnectionState connectionState = BlueConnectionState.disconnected;
  String? status;
  bool? scanAllowDuplicates;
  ScanMode? scanMode;
  AndroidScanMode? androidScanMode;
  AndroidScanCallbackType androidCallbackType =
      AndroidScanCallbackType.allMatches;
  AndroidScanMatchMode androidMatchMode = AndroidScanMatchMode.sticky;
  AndroidScanNumOfMatches? androidNumOfMatches;
  bool? androidLegacy;
  AndroidScanPhy? androidPhy;
  bool? darwinAllowDuplicates;
  LinuxScanTransport linuxTransport = LinuxScanTransport.le;
  bool? linuxDuplicateData;
  bool? linuxDiscoverable;
  WindowsScanMode? windowsScanMode;

  bool _disposed = false;
  bool _scanOptionParseFailed = false;

  Set<String> get notificationKeys => _notificationSubscriptions.keys.toSet();

  List<BlueScanResult> get discoveredDevices {
    return devices.values.toList();
  }

  bool get connected => connectionState == BlueConnectionState.connected;

  Future<void> toggleScan() {
    return scanning ? stopScan() : startScan();
  }

  Future<void> startScan() async {
    if (scanning) {
      return;
    }

    await _cancelScanSubscription();
    _scanTimer?.cancel();
    final scanFilter = _scanFilter();
    final scanOptions = _scanOptions();
    if (scanOptions == null) {
      return;
    }

    _mutate(() {
      devices.clear();
      scanning = true;
      scanRemaining = scanDuration;
      status = 'Scanning...';
      _log(
        scanFilter.serviceUuids.isEmpty
            ? 'Scan started.'
            : 'Scan started for ${scanFilter.serviceUuids.join(', ')}.',
        BleEventSeverity.info,
      );
      if (scanOptions != ScanOptions.defaults) {
        _log('Scan options: $scanOptions.', BleEventSeverity.info);
      }
    });
    _startScanCountdown();

    _scanSubscription =
        QuickBlue.scanResults(
          scanFilter: scanFilter,
          scanOptions: scanOptions,
        ).listen(
          (result) => _mutate(() {
            final firstSeen = !devices.containsKey(result.deviceId);
            devices[result.deviceId] = _mergeScanResult(
              previous: devices[result.deviceId],
              latest: result,
            );
            if (firstSeen) {
              _log('Found ${_deviceLabel(result)}.', BleEventSeverity.info);
            }
          }),
          onError: (Object error) {
            _scanTimer?.cancel();
            _setError('Scan failed', error);
            _mutate(() {
              scanning = false;
              scanRemaining = Duration.zero;
            });
          },
          onDone: () => _mutate(() {
            _scanTimer?.cancel();
            scanning = false;
            scanRemaining = Duration.zero;
          }),
        );
  }

  Future<void> stopScan({String statusMessage = 'Scan stopped.'}) async {
    if (!scanning && _scanSubscription == null) {
      return;
    }

    _scanTimer?.cancel();
    await _cancelScanSubscription();
    _mutate(() {
      scanning = false;
      scanRemaining = Duration.zero;
      status = statusMessage;
      _log(statusMessage, BleEventSeverity.info);
    });
  }

  Future<void> selectDevice(String deviceId) async {
    if (selectedDeviceId == deviceId) {
      return;
    }

    final previousDeviceId = selectedDeviceId;
    final shouldReleasePrevious =
        previousDeviceId != null &&
        (connecting || connectionState != BlueConnectionState.disconnected);
    _connectionAttempt++;
    if (shouldReleasePrevious) {
      _connectionRelease = _connectionRelease.then(
        (_) => _releaseDeviceConnection(previousDeviceId),
      );
    }
    await _cancelConnectionSubscription();
    await _cancelNotifications();
    _disposeWriteControllers();
    _writeWithoutResponseKeys.clear();

    final device = QuickBlue.device(deviceId);
    _connectionSubscription = device.connectionStateStream.listen(
      (event) {
        _mutate(() {
          connectionState = event.state;
          status = 'Connection ${event.state.value} (${event.status.name}).';
          _log(status!, BleEventSeverity.info);
          if (event.state == BlueConnectionState.disconnected) {
            _clearGattState(disposeControllers: true);
          }
        });
      },
      onError: (Object error) {
        _setError('Connection state failed', error);
      },
    );

    _mutate(() {
      selectedDeviceId = deviceId;
      connecting = false;
      discovering = false;
      connectionState = BlueConnectionState.disconnected;
      _clearGattState(disposeControllers: false);
      status = 'Selected ${deviceTitle(deviceId)}.';
      _log(status!, BleEventSeverity.info);
    });
  }

  Future<void> connectSelected() async {
    final deviceId = selectedDeviceId;
    if (deviceId == null || connecting || connected) {
      return;
    }
    final attempt = ++_connectionAttempt;

    _mutate(() {
      connecting = true;
      status = 'Connecting...';
      _log('Connecting to ${deviceTitle(deviceId)}.', BleEventSeverity.info);
    });

    try {
      await stopScan();
      await _connectionRelease;
      if (!_isCurrentConnectionAttempt(deviceId, attempt)) {
        return;
      }
      final stateChanged = _nextConnectOutcome(deviceId);
      await QuickBluePlatform.instance
          .connect(deviceId)
          .timeout(connectTimeout);
      final event = await stateChanged.timeout(connectTimeout);
      if (event.status == BleStatus.failure) {
        throw StateError('Failed to connect to Bluetooth device $deviceId.');
      }
      if (_isCurrentConnectionAttempt(deviceId, attempt)) {
        _mutate(() {
          connecting = false;
        });
        await _discoverServices(deviceId);
      }
    } on TimeoutException {
      if (_isCurrentConnectionAttempt(deviceId, attempt)) {
        _mutate(() {
          status = 'Connect timed out.';
          _log(
            'Connect timed out for ${deviceTitle(deviceId)}.',
            BleEventSeverity.warning,
          );
        });
      }
    } catch (error) {
      if (_isCurrentConnectionAttempt(deviceId, attempt)) {
        _setError('Connect failed', error);
      }
    } finally {
      if (_isCurrentConnectionAttempt(deviceId, attempt)) {
        _mutate(() {
          connecting = false;
        });
      }
    }
  }

  Future<void> disconnectSelected() async {
    final deviceId = selectedDeviceId;
    if (deviceId == null || !connected) {
      return;
    }

    try {
      await QuickBlue.device(deviceId).disconnect();
      _mutate(() {
        _clearGattState(disposeControllers: true);
        status = 'Disconnected.';
        _log(status!, BleEventSeverity.info);
      });
    } catch (error) {
      _setError('Disconnect failed', error);
    }
  }

  Future<void> discoverServices() async {
    final deviceId = selectedDeviceId;
    if (deviceId == null || !connected || discovering) {
      return;
    }

    await _discoverServices(deviceId);
  }

  Future<void> _discoverServices(String deviceId) async {
    if (discovering) {
      return;
    }

    await _cancelNotifications();
    _disposeWriteControllers();
    _writeWithoutResponseKeys.clear();
    _mutate(() {
      discovering = true;
      services.clear();
      latestValues.clear();
      status = 'Discovering services...';
      _log(status!, BleEventSeverity.info);
    });

    try {
      final discoveredServices = await QuickBlue.device(
        deviceId,
      ).discoverServices();
      if (selectedDeviceId != deviceId) {
        return;
      }
      _mutate(() {
        services.addAll(discoveredServices);
        status = 'Found ${discoveredServices.length} service(s).';
        _log(status!, BleEventSeverity.info);
      });
    } catch (error) {
      if (selectedDeviceId == deviceId) {
        _setError('Discover services failed', error);
      }
    } finally {
      if (selectedDeviceId == deviceId) {
        _mutate(() {
          discovering = false;
        });
      }
    }
  }

  bool _isCurrentConnectionAttempt(String deviceId, int attempt) {
    return selectedDeviceId == deviceId && _connectionAttempt == attempt;
  }

  Future<void> _releaseDeviceConnection(String deviceId) async {
    try {
      await QuickBluePlatform.instance
          .disconnect(deviceId)
          .timeout(deviceSwitchDisconnectTimeout);
      _mutate(() {
        _log(
          'Released previous connection for ${deviceTitle(deviceId)}.',
          BleEventSeverity.info,
        );
      });
    } on TimeoutException {
      _mutate(() {
        _log(
          'Timed out releasing previous connection for ${deviceTitle(deviceId)}.',
          BleEventSeverity.warning,
        );
      });
    } catch (error) {
      _mutate(() {
        _log(
          'Release previous connection failed for ${deviceTitle(deviceId)}: '
          '$error',
          BleEventSeverity.warning,
        );
      });
    }
  }

  Future<BluetoothConnectionStateChange> _nextConnectOutcome(String deviceId) {
    return QuickBlue.device(deviceId).connectionStateStream.firstWhere(
      (event) =>
          event.status == BleStatus.failure ||
          event.state == BlueConnectionState.connected,
    );
  }

  Future<void> readCharacteristic(
    BluetoothService service,
    String characteristicId,
  ) async {
    try {
      final characteristic = QuickBlue.device(
        service.deviceId,
      ).characteristic(service.uuid, characteristicId);
      final value = await characteristic.read();
      _mutate(() {
        latestValues[characteristicKey(service.uuid, characteristicId)] = value;
        status = 'Read ${value.length} byte(s).';
        _log(
          'Read ${value.length} byte(s) from $characteristicId.',
          BleEventSeverity.info,
        );
      });
    } catch (error) {
      _setError('Read failed', error);
    }
  }

  Future<void> writeCharacteristic(
    BluetoothService service,
    String characteristicId,
  ) async {
    final key = characteristicKey(service.uuid, characteristicId);
    final text = _writeControllers[key]?.text ?? '';
    if (text.trim().isEmpty) {
      _mutate(() {
        message = 'Enter bytes as hex or text before writing.';
      });
      return;
    }

    try {
      final value = parseBleValue(text);
      final characteristic = QuickBlue.device(
        service.deviceId,
      ).characteristic(service.uuid, characteristicId);
      final characteristicInfo = service.characteristicDetails.firstWhere(
        (candidate) => candidate.uuid == characteristicId,
        orElse: () => BluetoothCharacteristicInfo(uuid: characteristicId),
      );
      final outputProperty =
          writeWithoutResponseFor(key) ||
              (!characteristicInfo.canWriteWithResponse &&
                  characteristicInfo.canWriteWithoutResponse)
          ? BleOutputProperty.withoutResponse
          : BleOutputProperty.withResponse;
      await characteristic.write(value, outputProperty);
      _mutate(() {
        status = 'Wrote ${value.length} byte(s).';
        _log(
          'Wrote ${value.length} byte(s) to $characteristicId.',
          BleEventSeverity.info,
        );
      });
    } catch (error) {
      _setError('Write failed', error);
    }
  }

  Future<void> toggleNotify(
    BluetoothService service,
    String characteristicId,
  ) async {
    final key = characteristicKey(service.uuid, characteristicId);
    final subscription = _notificationSubscriptions.remove(key);
    if (subscription != null) {
      await subscription.cancel();
      _mutate(() {
        status = 'Notifications stopped.';
        _log(
          'Stopped notifications for $characteristicId.',
          BleEventSeverity.info,
        );
      });
      return;
    }

    try {
      final characteristic = QuickBlue.device(
        service.deviceId,
      ).characteristic(service.uuid, characteristicId);
      final newSubscription = characteristic.notifications().listen(
        (value) {
          _mutate(() {
            latestValues[key] = value;
            status = 'Notification: ${value.length} byte(s).';
          });
        },
        onError: (Object error) {
          _notificationSubscriptions.remove(key);
          _setError('Notification failed', error);
        },
      );
      _mutate(() {
        _notificationSubscriptions[key] = newSubscription;
        status = 'Notifications started.';
        _log(
          'Started notifications for $characteristicId.',
          BleEventSeverity.info,
        );
      });
    } catch (error) {
      _setError('Notify failed', error);
    }
  }

  TextEditingController writeControllerFor(String key) {
    return _writeControllers.putIfAbsent(key, TextEditingController.new);
  }

  bool writeWithoutResponseFor(String key) {
    return _writeWithoutResponseKeys.contains(key);
  }

  void setWriteWithoutResponse(String key, bool enabled) {
    _mutate(() {
      if (enabled) {
        _writeWithoutResponseKeys.add(key);
      } else {
        _writeWithoutResponseKeys.remove(key);
      }
    });
  }

  void setScanAllowDuplicates(bool? value) {
    _mutate(() {
      scanAllowDuplicates = value;
    });
  }

  void setScanMode(ScanMode? value) {
    _mutate(() {
      scanMode = value;
    });
  }

  void setAndroidScanMode(AndroidScanMode? value) {
    _mutate(() {
      androidScanMode = value;
    });
  }

  void setAndroidCallbackType(AndroidScanCallbackType value) {
    _mutate(() {
      androidCallbackType = value;
    });
  }

  void setAndroidMatchMode(AndroidScanMatchMode value) {
    _mutate(() {
      androidMatchMode = value;
    });
  }

  void setAndroidNumOfMatches(AndroidScanNumOfMatches? value) {
    _mutate(() {
      androidNumOfMatches = value;
    });
  }

  void setAndroidLegacy(bool? value) {
    _mutate(() {
      androidLegacy = value;
    });
  }

  void setAndroidPhy(AndroidScanPhy? value) {
    _mutate(() {
      androidPhy = value;
    });
  }

  void setDarwinAllowDuplicates(bool? value) {
    _mutate(() {
      darwinAllowDuplicates = value;
    });
  }

  void setLinuxTransport(LinuxScanTransport value) {
    _mutate(() {
      linuxTransport = value;
    });
  }

  void setLinuxDuplicateData(bool? value) {
    _mutate(() {
      linuxDuplicateData = value;
    });
  }

  void setLinuxDiscoverable(bool? value) {
    _mutate(() {
      linuxDiscoverable = value;
    });
  }

  void setWindowsScanMode(WindowsScanMode? value) {
    _mutate(() {
      windowsScanMode = value;
    });
  }

  String deviceTitle(String deviceId) {
    final name = devices[deviceId]?.name.trim();
    return name == null || name.isEmpty ? deviceId : name;
  }

  String? message;

  void clearMessage() {
    message = null;
  }

  void clearEvents() {
    _mutate(events.clear);
  }

  Future<void> _cancelScanSubscription() async {
    final subscription = _scanSubscription;
    _scanSubscription = null;
    await subscription?.cancel();
  }

  Future<void> _cancelBluetoothStateSubscription() async {
    final subscription = _bluetoothStateSubscription;
    _bluetoothStateSubscription = null;
    await subscription?.cancel();
  }

  Future<void> _cancelConnectionSubscription() async {
    final subscription = _connectionSubscription;
    _connectionSubscription = null;
    await subscription?.cancel();
  }

  Future<void> _cancelNotifications() async {
    final subscriptions = _notificationSubscriptions.values.toList();
    _notificationSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  ScanFilter _scanFilter() {
    final serviceUuids = _splitUuidText(serviceFilterController.text);
    return serviceUuids.isEmpty
        ? ScanFilter.empty
        : ScanFilter(serviceUuids: serviceUuids);
  }

  ScanOptions? _scanOptions() {
    _scanOptionParseFailed = false;
    final androidReportDelayMillis = _optionalInt(
      androidReportDelayMillisController.text,
      'Android report delay',
    );
    final linuxRssi = _optionalInt(linuxRssiController.text, 'Linux RSSI');
    final linuxPathloss = _optionalInt(
      linuxPathlossController.text,
      'Linux pathloss',
    );
    final windowsInRangeThreshold = _optionalInt(
      windowsInRangeThresholdController.text,
      'Windows in-range threshold',
    );
    final windowsOutOfRangeThreshold = _optionalInt(
      windowsOutOfRangeThresholdController.text,
      'Windows out-of-range threshold',
    );
    final windowsOutOfRangeTimeoutMillis = _optionalInt(
      windowsOutOfRangeTimeoutMillisController.text,
      'Windows out-of-range timeout',
    );
    final windowsSamplingIntervalMillis = _optionalInt(
      windowsSamplingIntervalMillisController.text,
      'Windows sampling interval',
    );
    if (_scanOptionParseFailed) {
      return null;
    }

    return ScanOptions(
      allowDuplicates: scanAllowDuplicates,
      scanMode: scanMode,
      android: AndroidScanOptions(
        scanMode: androidScanMode,
        callbackType: androidCallbackType,
        matchMode: androidMatchMode,
        numOfMatches: androidNumOfMatches,
        reportDelay: Duration(milliseconds: androidReportDelayMillis ?? 0),
        legacy: androidLegacy,
        phy: androidPhy,
      ),
      darwin: DarwinScanOptions(
        allowDuplicates: darwinAllowDuplicates,
        solicitedServiceUuids: _splitUuidText(
          darwinSolicitedServiceUuidsController.text,
        ),
      ),
      linux: LinuxScanOptions(
        rssi: linuxRssi,
        pathloss: linuxPathloss,
        transport: linuxTransport,
        duplicateData: linuxDuplicateData,
        discoverable: linuxDiscoverable,
        pattern: _optionalText(linuxPatternController.text),
      ),
      windows: WindowsScanOptions(
        scanningMode: windowsScanMode,
        signalStrengthFilter: _windowsSignalStrengthFilter(
          inRangeThresholdInDBm: windowsInRangeThreshold,
          outOfRangeThresholdInDBm: windowsOutOfRangeThreshold,
          outOfRangeTimeoutMillis: windowsOutOfRangeTimeoutMillis,
          samplingIntervalMillis: windowsSamplingIntervalMillis,
        ),
      ),
    );
  }

  int? _optionalInt(String text, String label) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final value = int.tryParse(trimmed);
    if (value == null) {
      _setScanOptionError('$label must be an integer.');
    }
    return value;
  }

  String? _optionalText(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> _splitUuidText(String text) {
    return text
        .split(RegExp(r'[\s,]+'))
        .map((uuid) => uuid.trim())
        .where((uuid) => uuid.isNotEmpty)
        .toList();
  }

  WindowsSignalStrengthFilter? _windowsSignalStrengthFilter({
    required int? inRangeThresholdInDBm,
    required int? outOfRangeThresholdInDBm,
    required int? outOfRangeTimeoutMillis,
    required int? samplingIntervalMillis,
  }) {
    if (inRangeThresholdInDBm == null &&
        outOfRangeThresholdInDBm == null &&
        outOfRangeTimeoutMillis == null &&
        samplingIntervalMillis == null) {
      return null;
    }
    return WindowsSignalStrengthFilter(
      inRangeThresholdInDBm: inRangeThresholdInDBm,
      outOfRangeThresholdInDBm: outOfRangeThresholdInDBm,
      outOfRangeTimeout: outOfRangeTimeoutMillis == null
          ? null
          : Duration(milliseconds: outOfRangeTimeoutMillis),
      samplingInterval: samplingIntervalMillis == null
          ? null
          : Duration(milliseconds: samplingIntervalMillis),
    );
  }

  void _setScanOptionError(String text) {
    _scanOptionParseFailed = true;
    _mutate(() {
      message = 'Invalid scan option: $text';
      status = 'Invalid scan option.';
      _log(message!, BleEventSeverity.error);
    });
  }

  BlueScanResult _mergeScanResult({
    required BlueScanResult? previous,
    required BlueScanResult latest,
  }) {
    if (previous == null) {
      return latest;
    }

    final name = latest.name.trim().isEmpty ? previous.name : latest.name;
    final serviceUuids = latest.serviceUuids.isEmpty
        ? previous.serviceUuids
        : latest.serviceUuids;
    final serviceData = latest.serviceData.isEmpty
        ? previous.serviceData
        : latest.serviceData;

    return BlueScanResult(
      name: name,
      deviceId: latest.deviceId,
      manufacturerDataHead: latest.manufacturerDataHead,
      manufacturerData: latest.manufacturerData,
      rssi: latest.rssi,
      advertisedDateTime: latest.advertisedDateTime,
      serviceUuids: serviceUuids,
      serviceData: serviceData,
    );
  }

  void _startBluetoothStateUpdates() {
    try {
      _bluetoothStateSubscription = QuickBlue.bluetoothStateStream.listen(
        _handleBluetoothState,
        onError: (Object error) {
          _setError('Bluetooth state failed', error);
          _mutate(() {
            bluetoothState = BlueBluetoothState.unknown;
            bluetoothAvailable = false;
            availabilityChecked = true;
            status = 'Bluetooth state unavailable.';
          });
          _completeInitialBluetoothCheck();
        },
        onDone: _completeInitialBluetoothCheck,
      );
    } catch (error) {
      _setError('Bluetooth state failed', error);
      _mutate(() {
        bluetoothState = BlueBluetoothState.unknown;
        bluetoothAvailable = false;
        availabilityChecked = true;
        status = 'Bluetooth state unavailable.';
      });
      _completeInitialBluetoothCheck();
    }
  }

  void _handleBluetoothState(BlueBluetoothState state) {
    final shouldLog = !availabilityChecked || bluetoothState != state;
    final shouldStopScan = scanning && state != BlueBluetoothState.poweredOn;
    final stateStatus = _bluetoothStateStatus(state);

    _mutate(() {
      bluetoothState = state;
      bluetoothAvailable = state == BlueBluetoothState.poweredOn;
      availabilityChecked = true;
      status = stateStatus;
      if (shouldLog) {
        _log(
          stateStatus,
          bluetoothAvailable ? BleEventSeverity.info : BleEventSeverity.warning,
        );
      }
    });
    _completeInitialBluetoothCheck();

    if (shouldStopScan) {
      stopScan(
        statusMessage: 'Scan stopped because ${_bluetoothStateReason(state)}.',
      ).catchError((Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'quick_blue_example',
            context: ErrorDescription(
              'while stopping scan after Bluetooth state changed',
            ),
          ),
        );
      });
    }
  }

  String _bluetoothStateStatus(BlueBluetoothState state) {
    return switch (state) {
      BlueBluetoothState.poweredOn => 'Bluetooth is ready.',
      BlueBluetoothState.poweredOff => 'Bluetooth is off.',
      BlueBluetoothState.unauthorized => 'Bluetooth permission is missing.',
      BlueBluetoothState.unavailable =>
        'Bluetooth is unavailable on this device.',
      BlueBluetoothState.unknown => 'Bluetooth state is unknown.',
    };
  }

  String _bluetoothStateReason(BlueBluetoothState state) {
    return switch (state) {
      BlueBluetoothState.poweredOn => 'Bluetooth is ready',
      BlueBluetoothState.poweredOff => 'Bluetooth is off',
      BlueBluetoothState.unauthorized => 'Bluetooth permission is missing',
      BlueBluetoothState.unavailable => 'Bluetooth is unavailable',
      BlueBluetoothState.unknown => 'Bluetooth state is unknown',
    };
  }

  void _completeInitialBluetoothCheck() {
    final completer = _initialBluetoothCheck;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete();
  }

  void _startScanCountdown() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final nextRemaining = scanRemaining - const Duration(seconds: 1);
      if (nextRemaining <= Duration.zero) {
        timer.cancel();
        stopScan(statusMessage: 'Scan completed.').catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'quick_blue_example',
              context: ErrorDescription('while stopping timed BLE scan'),
            ),
          );
        });
        return;
      }

      _mutate(() {
        scanRemaining = nextRemaining;
      });
    });
  }

  void _clearGattState({required bool disposeControllers}) {
    services.clear();
    latestValues.clear();
    _writeWithoutResponseKeys.clear();
    if (disposeControllers) {
      _disposeWriteControllers();
    }
  }

  void _disposeWriteControllers() {
    for (final controller in _writeControllers.values) {
      controller.dispose();
    }
    _writeControllers.clear();
  }

  void _setError(String label, Object error) {
    _mutate(() {
      message = '$label: $error';
      status = '$label.';
      _log(message!, BleEventSeverity.error);
    });
  }

  String _deviceLabel(BlueScanResult result) {
    final name = result.name.trim();
    return name.isEmpty ? result.deviceId : name;
  }

  void _log(String text, BleEventSeverity severity) {
    events.insert(
      0,
      BleEvent(timestamp: DateTime.now(), message: text, severity: severity),
    );
    if (events.length > 50) {
      events.removeRange(50, events.length);
    }
  }

  void _mutate(VoidCallback change) {
    if (_disposed) {
      return;
    }
    change();
    notifyListeners();
  }

  void _reportCancelError(String context, Future<void> future) {
    future.catchError((Object error, StackTrace stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'quick_blue_example',
          context: ErrorDescription(context),
        ),
      );
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    _reportCancelError(
      'while canceling BLE state subscription',
      _cancelBluetoothStateSubscription(),
    );
    _reportCancelError(
      'while canceling BLE scan subscription',
      _cancelScanSubscription(),
    );
    _reportCancelError(
      'while canceling BLE connection subscription',
      _cancelConnectionSubscription(),
    );
    _reportCancelError(
      'while canceling BLE notification subscriptions',
      _cancelNotifications(),
    );
    _disposeWriteControllers();
    serviceFilterController.dispose();
    androidReportDelayMillisController.dispose();
    darwinSolicitedServiceUuidsController.dispose();
    linuxRssiController.dispose();
    linuxPathlossController.dispose();
    linuxPatternController.dispose();
    windowsInRangeThresholdController.dispose();
    windowsOutOfRangeThresholdController.dispose();
    windowsOutOfRangeTimeoutMillisController.dispose();
    windowsSamplingIntervalMillisController.dispose();
    super.dispose();
  }
}
