import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quick_blue/quick_blue.dart';

import 'ble_explorer_controller.dart';
import 'ble_value_codec.dart';

part 'ble_explorer_scan_widgets.dart';
part 'ble_explorer_device_widgets.dart';
part 'ble_explorer_shared_widgets.dart';

typedef ToggleScanCallback = Future<void> Function();
typedef SelectDeviceCallback = void Function(String deviceId);
typedef DeviceActionCallback = Future<void> Function();
typedef CharacteristicActionCallback =
    Future<void> Function(BluetoothService service, String characteristicId);
typedef WriteControllerFactory =
    TextEditingController Function(String characteristicKey);
typedef WriteModeLookup = bool Function(String characteristicKey);
typedef WriteModeChangedCallback =
    void Function(String characteristicKey, bool withoutResponse);
typedef NullableBoolChangedCallback = void Function(bool? value);

const _defaultEventLogHeight = 148.0;
const _minEventLogHeight = 88.0;
const _maxEventLogHeightFraction = 0.6;
const _eventLogHeaderHeight = 36.0;
const _defaultScanPaneWidth = 360.0;
const _minScanPaneWidth = 280.0;
const _maxScanPaneWidth = 560.0;
const _minDetailPaneWidth = 360.0;
const _resizeHandleExtent = 12.0;

class BleExplorerPage extends StatefulWidget {
  const BleExplorerPage({super.key});

  @override
  State<BleExplorerPage> createState() => _BleExplorerPageState();
}

class _BleExplorerPageState extends State<BleExplorerPage> {
  late final BleExplorerController _controller;
  var _eventLogExpanded = false;
  var _eventLogHeight = _defaultEventLogHeight;
  var _scanPaneWidth = _defaultScanPaneWidth;

  @override
  void initState() {
    super.initState();
    _controller = BleExplorerController();
    _controller.addListener(_showControllerMessage);
  }

  @override
  void dispose() {
    _controller.removeListener(_showControllerMessage);
    _controller.dispose();
    super.dispose();
  }

  void _showControllerMessage() {
    final message = _controller.message;
    if (message == null || !mounted) {
      return;
    }

    _controller.clearMessage();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _selectDevice(String deviceId, {required bool openDetail}) {
    final selection =
        (openDetail && _controller.scanning
                ? _controller.stopScan(
                    statusMessage: 'Scan stopped after selection.',
                  )
                : Future<void>.value())
            .then((_) => _controller.selectDevice(deviceId));

    selection
        .then((_) {
          if (!openDetail || !mounted) {
            return;
          }
          _openDeviceDetailRoute();
        })
        .catchError((Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'quick_blue_example',
              context: ErrorDescription('while selecting BLE device'),
            ),
          );
        });
  }

  void _openDeviceDetailRoute() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (context) => AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final selectedDeviceId = _controller.selectedDeviceId;
                return Scaffold(
                  appBar: AppBar(
                    title: Text(
                      selectedDeviceId == null
                          ? 'Device'
                          : _controller.deviceTitle(selectedDeviceId),
                    ),
                  ),
                  body: SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return _buildDetailSurface(
                          showEventLog: true,
                          maxHeight: constraints.maxHeight,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        )
        .catchError((Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'quick_blue_example',
              context: ErrorDescription('while opening BLE device details'),
            ),
          );
        });
  }

  void _resizeEventLog(double deltaDy, double maxHeight) {
    setState(() {
      _eventLogExpanded = true;
      _eventLogHeight = (_eventLogHeight - deltaDy)
          .clamp(_minEventLogHeight, _maxEventLogHeight(maxHeight))
          .toDouble();
    });
  }

  void _resizeScanPane(double deltaDx, double maxWidth) {
    setState(() {
      _scanPaneWidth = (_scanPaneWidth + deltaDx)
          .clamp(_minScanPaneWidth, _maxScanPaneWidthFor(maxWidth))
          .toDouble();
    });
  }

  void _toggleEventLogExpanded() {
    setState(() {
      _eventLogExpanded = !_eventLogExpanded;
    });
  }

  double _maxEventLogHeight(double maxHeight) {
    return (maxHeight * _maxEventLogHeightFraction)
        .clamp(_minEventLogHeight, double.infinity)
        .toDouble();
  }

  double _maxScanPaneWidthFor(double maxWidth) {
    final availableWidth = maxWidth - _resizeHandleExtent - _minDetailPaneWidth;
    return availableWidth
        .clamp(_minScanPaneWidth, _maxScanPaneWidth)
        .toDouble();
  }

  Widget _buildResizableEventLog({required double maxHeight}) {
    final eventLogHeight = _eventLogHeight
        .clamp(_minEventLogHeight, _maxEventLogHeight(maxHeight))
        .toDouble();
    return Column(
      children: [
        if (_eventLogExpanded)
          _ResizeHandle(
            key: const ValueKey('ble_events_resize_handle'),
            axis: Axis.vertical,
            onDragUpdate: (delta) => _resizeEventLog(delta, maxHeight),
          ),
        SizedBox(
          key: const ValueKey('ble_events_panel'),
          height: _eventLogExpanded ? eventLogHeight : _eventLogHeaderHeight,
          child: _EventLogPanel(
            events: _controller.events,
            expanded: _eventLogExpanded,
            onToggleExpanded: _toggleEventLogExpanded,
            onClear: _controller.clearEvents,
          ),
        ),
      ],
    );
  }

  Widget _buildScanSurface({required bool openDetailOnSelect}) {
    return _ScanPane(
      availabilityChecked: _controller.availabilityChecked,
      bluetoothState: _controller.bluetoothState,
      bluetoothAvailable: _controller.bluetoothAvailable,
      scanning: _controller.scanning,
      scanRemaining: _controller.scanRemaining,
      devices: _controller.discoveredDevices,
      selectedDeviceId: _controller.selectedDeviceId,
      serviceFilterController: _controller.serviceFilterController,
      androidReportDelayMillisController:
          _controller.androidReportDelayMillisController,
      darwinSolicitedServiceUuidsController:
          _controller.darwinSolicitedServiceUuidsController,
      linuxRssiController: _controller.linuxRssiController,
      linuxPathlossController: _controller.linuxPathlossController,
      linuxPatternController: _controller.linuxPatternController,
      windowsInRangeThresholdController:
          _controller.windowsInRangeThresholdController,
      windowsOutOfRangeThresholdController:
          _controller.windowsOutOfRangeThresholdController,
      windowsOutOfRangeTimeoutMillisController:
          _controller.windowsOutOfRangeTimeoutMillisController,
      windowsSamplingIntervalMillisController:
          _controller.windowsSamplingIntervalMillisController,
      scanAllowDuplicates: _controller.scanAllowDuplicates,
      scanMode: _controller.scanMode,
      androidScanMode: _controller.androidScanMode,
      androidCallbackType: _controller.androidCallbackType,
      androidMatchMode: _controller.androidMatchMode,
      androidNumOfMatches: _controller.androidNumOfMatches,
      androidLegacy: _controller.androidLegacy,
      androidPhy: _controller.androidPhy,
      darwinAllowDuplicates: _controller.darwinAllowDuplicates,
      linuxTransport: _controller.linuxTransport,
      linuxDuplicateData: _controller.linuxDuplicateData,
      linuxDiscoverable: _controller.linuxDiscoverable,
      windowsScanMode: _controller.windowsScanMode,
      onToggleScan: _controller.toggleScan,
      onSelectDevice: (deviceId) =>
          _selectDevice(deviceId, openDetail: openDetailOnSelect),
      onScanAllowDuplicatesChanged: _controller.setScanAllowDuplicates,
      onScanModeChanged: _controller.setScanMode,
      onAndroidScanModeChanged: _controller.setAndroidScanMode,
      onAndroidCallbackTypeChanged: _controller.setAndroidCallbackType,
      onAndroidMatchModeChanged: _controller.setAndroidMatchMode,
      onAndroidNumOfMatchesChanged: _controller.setAndroidNumOfMatches,
      onAndroidLegacyChanged: _controller.setAndroidLegacy,
      onAndroidPhyChanged: _controller.setAndroidPhy,
      onDarwinAllowDuplicatesChanged: _controller.setDarwinAllowDuplicates,
      onLinuxTransportChanged: _controller.setLinuxTransport,
      onLinuxDuplicateDataChanged: _controller.setLinuxDuplicateData,
      onLinuxDiscoverableChanged: _controller.setLinuxDiscoverable,
      onWindowsScanModeChanged: _controller.setWindowsScanMode,
    );
  }

  Widget _buildDetailSurface({required bool showEventLog, double? maxHeight}) {
    final selectedDeviceId = _controller.selectedDeviceId;
    final detailPane = _DevicePane(
      deviceId: selectedDeviceId,
      title: selectedDeviceId == null
          ? null
          : _controller.deviceTitle(selectedDeviceId),
      connectionState: _controller.connectionState,
      connecting: _controller.connecting,
      discovering: _controller.discovering,
      services: _controller.services,
      latestValues: _controller.latestValues,
      notificationKeys: _controller.notificationKeys,
      status: _controller.status,
      onConnect: _controller.connectSelected,
      onDisconnect: _controller.disconnectSelected,
      onDiscoverServices: _controller.discoverServices,
      onRead: _controller.readCharacteristic,
      onWrite: _controller.writeCharacteristic,
      onToggleNotify: _controller.toggleNotify,
      writeControllerFor: _controller.writeControllerFor,
      writeWithoutResponseFor: _controller.writeWithoutResponseFor,
      onWriteModeChanged: _controller.setWriteWithoutResponse,
    );

    if (!showEventLog) {
      return detailPane;
    }

    assert(maxHeight != null);
    return Column(
      children: [
        Expanded(child: detailPane),
        _buildResizableEventLog(maxHeight: maxHeight!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                if (!wide) {
                  return Column(
                    children: [
                      Expanded(
                        child: _buildScanSurface(openDetailOnSelect: true),
                      ),
                      _buildResizableEventLog(maxHeight: constraints.maxHeight),
                    ],
                  );
                }

                final scanPaneWidth = _scanPaneWidth
                    .clamp(
                      _minScanPaneWidth,
                      _maxScanPaneWidthFor(constraints.maxWidth),
                    )
                    .toDouble();
                return Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(
                            key: const ValueKey('ble_scan_pane'),
                            width: scanPaneWidth,
                            child: _buildScanSurface(openDetailOnSelect: false),
                          ),
                          _ResizeHandle(
                            key: const ValueKey('ble_scan_resize_handle'),
                            axis: Axis.horizontal,
                            onDragUpdate: (delta) =>
                                _resizeScanPane(delta, constraints.maxWidth),
                          ),
                          Expanded(
                            child: _buildDetailSurface(showEventLog: false),
                          ),
                        ],
                      ),
                    ),
                    _buildResizableEventLog(maxHeight: constraints.maxHeight),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
