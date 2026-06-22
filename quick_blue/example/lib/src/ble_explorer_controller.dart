import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart'
    show QuickBluePlatform;

import 'ble_gatt_session.dart';
import 'ble_scan_configuration.dart';
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
  final events = <BleEvent>[];

  late final Future<void> initialBluetoothCheck;

  final _gattSession = BleGattSession();
  final _scanConfiguration = BleScanConfiguration();

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

  bool _disposed = false;

  List<BluetoothService> get services => _gattSession.services;

  Map<String, Uint8List> get latestValues => _gattSession.latestValues;

  Set<String> get notificationKeys => _gattSession.notificationKeys;

  TextEditingController get serviceFilterController {
    return _scanConfiguration.serviceFilterController;
  }

  TextEditingController get androidReportDelayMillisController {
    return _scanConfiguration.androidReportDelayMillisController;
  }

  TextEditingController get darwinSolicitedServiceUuidsController {
    return _scanConfiguration.darwinSolicitedServiceUuidsController;
  }

  TextEditingController get linuxRssiController {
    return _scanConfiguration.linuxRssiController;
  }

  TextEditingController get linuxPathlossController {
    return _scanConfiguration.linuxPathlossController;
  }

  TextEditingController get linuxPatternController {
    return _scanConfiguration.linuxPatternController;
  }

  TextEditingController get windowsInRangeThresholdController {
    return _scanConfiguration.windowsInRangeThresholdController;
  }

  TextEditingController get windowsOutOfRangeThresholdController {
    return _scanConfiguration.windowsOutOfRangeThresholdController;
  }

  TextEditingController get windowsOutOfRangeTimeoutMillisController {
    return _scanConfiguration.windowsOutOfRangeTimeoutMillisController;
  }

  TextEditingController get windowsSamplingIntervalMillisController {
    return _scanConfiguration.windowsSamplingIntervalMillisController;
  }

  bool? get scanAllowDuplicates => _scanConfiguration.scanAllowDuplicates;

  ScanMode? get scanMode => _scanConfiguration.scanMode;

  AndroidScanMode? get androidScanMode => _scanConfiguration.androidScanMode;

  AndroidScanCallbackType get androidCallbackType {
    return _scanConfiguration.androidCallbackType;
  }

  AndroidScanMatchMode get androidMatchMode {
    return _scanConfiguration.androidMatchMode;
  }

  AndroidScanNumOfMatches? get androidNumOfMatches {
    return _scanConfiguration.androidNumOfMatches;
  }

  bool? get androidLegacy => _scanConfiguration.androidLegacy;

  AndroidScanPhy? get androidPhy => _scanConfiguration.androidPhy;

  bool? get darwinAllowDuplicates => _scanConfiguration.darwinAllowDuplicates;

  LinuxScanTransport get linuxTransport => _scanConfiguration.linuxTransport;

  bool? get linuxDuplicateData => _scanConfiguration.linuxDuplicateData;

  bool? get linuxDiscoverable => _scanConfiguration.linuxDiscoverable;

  WindowsScanMode? get windowsScanMode => _scanConfiguration.windowsScanMode;

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
    final scanFilter = _scanConfiguration.scanFilter();
    late final ScanOptions scanOptions;
    try {
      scanOptions = _scanConfiguration.scanOptions();
    } on BleScanOptionParseException catch (error) {
      _setScanOptionError(error.message);
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
    await _gattSession.cancelNotifications();
    _gattSession.clear(disposeControllers: true);

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

    await _gattSession.cancelNotifications();
    _gattSession.clear(disposeControllers: true);
    _mutate(() {
      discovering = true;
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
        _gattSession.replaceServices(discoveredServices);
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
        _gattSession.setLatestValue(
          characteristicKey(service.uuid, characteristicId),
          value,
        );
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
    final text = _gattSession.writeTextFor(key);
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
    final subscription = _gattSession.takeNotification(key);
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
            _gattSession.setLatestValue(key, value);
            status = 'Notification: ${value.length} byte(s).';
          });
        },
        onError: (Object error) {
          _gattSession.removeNotification(key);
          _setError('Notification failed', error);
        },
      );
      _mutate(() {
        _gattSession.setNotification(key, newSubscription);
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
    return _gattSession.writeControllerFor(key);
  }

  bool writeWithoutResponseFor(String key) {
    return _gattSession.writeWithoutResponseFor(key);
  }

  void setWriteWithoutResponse(String key, bool enabled) {
    _mutate(() {
      _gattSession.setWriteWithoutResponse(key, enabled);
    });
  }

  void setScanAllowDuplicates(bool? value) {
    _mutate(() {
      _scanConfiguration.scanAllowDuplicates = value;
    });
  }

  void setScanMode(ScanMode? value) {
    _mutate(() {
      _scanConfiguration.scanMode = value;
    });
  }

  void setAndroidScanMode(AndroidScanMode? value) {
    _mutate(() {
      _scanConfiguration.androidScanMode = value;
    });
  }

  void setAndroidCallbackType(AndroidScanCallbackType value) {
    _mutate(() {
      _scanConfiguration.androidCallbackType = value;
    });
  }

  void setAndroidMatchMode(AndroidScanMatchMode value) {
    _mutate(() {
      _scanConfiguration.androidMatchMode = value;
    });
  }

  void setAndroidNumOfMatches(AndroidScanNumOfMatches? value) {
    _mutate(() {
      _scanConfiguration.androidNumOfMatches = value;
    });
  }

  void setAndroidLegacy(bool? value) {
    _mutate(() {
      _scanConfiguration.androidLegacy = value;
    });
  }

  void setAndroidPhy(AndroidScanPhy? value) {
    _mutate(() {
      _scanConfiguration.androidPhy = value;
    });
  }

  void setDarwinAllowDuplicates(bool? value) {
    _mutate(() {
      _scanConfiguration.darwinAllowDuplicates = value;
    });
  }

  void setLinuxTransport(LinuxScanTransport value) {
    _mutate(() {
      _scanConfiguration.linuxTransport = value;
    });
  }

  void setLinuxDuplicateData(bool? value) {
    _mutate(() {
      _scanConfiguration.linuxDuplicateData = value;
    });
  }

  void setLinuxDiscoverable(bool? value) {
    _mutate(() {
      _scanConfiguration.linuxDiscoverable = value;
    });
  }

  void setWindowsScanMode(WindowsScanMode? value) {
    _mutate(() {
      _scanConfiguration.windowsScanMode = value;
    });
  }

  String deviceTitle(String deviceId) {
    final name = devices[deviceId]?.name.trim();
    return name == null || name.isEmpty ? deviceId : name;
  }

  String? message;

  void clearMessage() {
    if (message == null) {
      return;
    }
    _mutate(() {
      message = null;
    });
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

  void _setScanOptionError(String text) {
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
    _gattSession.clear(disposeControllers: disposeControllers);
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
      _gattSession.cancelNotifications(),
    );
    _gattSession.disposeWriteControllers();
    _scanConfiguration.dispose();
    super.dispose();
  }
}
