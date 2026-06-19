import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quick_blue/quick_blue.dart';

import 'ble_explorer_controller.dart';
import 'ble_value_codec.dart';

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

class BleExplorerPage extends StatefulWidget {
  const BleExplorerPage({super.key});

  @override
  State<BleExplorerPage> createState() => _BleExplorerPageState();
}

class _BleExplorerPageState extends State<BleExplorerPage> {
  late final BleExplorerController _controller;

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
                    child: _buildDetailSurface(showEventLog: true),
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

  Widget _buildDetailSurface({required bool showEventLog}) {
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

    return Column(
      children: [
        Expanded(child: detailPane),
        const Divider(height: 1),
        _EventLogPanel(
          events: _controller.events,
          onClear: _controller.clearEvents,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('quick_blue example')),
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
                      const Divider(height: 1),
                      _EventLogPanel(
                        events: _controller.events,
                        onClear: _controller.clearEvents,
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 360,
                            child: _buildScanSurface(openDetailOnSelect: false),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: _buildDetailSurface(showEventLog: false),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    _EventLogPanel(
                      events: _controller.events,
                      onClear: _controller.clearEvents,
                    ),
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

class _ScanPane extends StatelessWidget {
  const _ScanPane({
    required this.availabilityChecked,
    required this.bluetoothState,
    required this.bluetoothAvailable,
    required this.scanning,
    required this.scanRemaining,
    required this.devices,
    required this.selectedDeviceId,
    required this.serviceFilterController,
    required this.androidReportDelayMillisController,
    required this.darwinSolicitedServiceUuidsController,
    required this.linuxRssiController,
    required this.linuxPathlossController,
    required this.linuxPatternController,
    required this.windowsInRangeThresholdController,
    required this.windowsOutOfRangeThresholdController,
    required this.windowsOutOfRangeTimeoutMillisController,
    required this.windowsSamplingIntervalMillisController,
    required this.scanAllowDuplicates,
    required this.scanMode,
    required this.androidScanMode,
    required this.androidCallbackType,
    required this.androidMatchMode,
    required this.androidNumOfMatches,
    required this.androidLegacy,
    required this.androidPhy,
    required this.darwinAllowDuplicates,
    required this.linuxTransport,
    required this.linuxDuplicateData,
    required this.linuxDiscoverable,
    required this.windowsScanMode,
    required this.onToggleScan,
    required this.onSelectDevice,
    required this.onScanAllowDuplicatesChanged,
    required this.onScanModeChanged,
    required this.onAndroidScanModeChanged,
    required this.onAndroidCallbackTypeChanged,
    required this.onAndroidMatchModeChanged,
    required this.onAndroidNumOfMatchesChanged,
    required this.onAndroidLegacyChanged,
    required this.onAndroidPhyChanged,
    required this.onDarwinAllowDuplicatesChanged,
    required this.onLinuxTransportChanged,
    required this.onLinuxDuplicateDataChanged,
    required this.onLinuxDiscoverableChanged,
    required this.onWindowsScanModeChanged,
  });

  final bool availabilityChecked;
  final BlueBluetoothState bluetoothState;
  final bool bluetoothAvailable;
  final bool scanning;
  final Duration scanRemaining;
  final List<BlueScanResult> devices;
  final String? selectedDeviceId;
  final TextEditingController serviceFilterController;
  final TextEditingController androidReportDelayMillisController;
  final TextEditingController darwinSolicitedServiceUuidsController;
  final TextEditingController linuxRssiController;
  final TextEditingController linuxPathlossController;
  final TextEditingController linuxPatternController;
  final TextEditingController windowsInRangeThresholdController;
  final TextEditingController windowsOutOfRangeThresholdController;
  final TextEditingController windowsOutOfRangeTimeoutMillisController;
  final TextEditingController windowsSamplingIntervalMillisController;
  final bool? scanAllowDuplicates;
  final ScanMode? scanMode;
  final AndroidScanMode? androidScanMode;
  final AndroidScanCallbackType androidCallbackType;
  final AndroidScanMatchMode androidMatchMode;
  final AndroidScanNumOfMatches? androidNumOfMatches;
  final bool? androidLegacy;
  final AndroidScanPhy? androidPhy;
  final bool? darwinAllowDuplicates;
  final LinuxScanTransport linuxTransport;
  final bool? linuxDuplicateData;
  final bool? linuxDiscoverable;
  final WindowsScanMode? windowsScanMode;
  final ToggleScanCallback onToggleScan;
  final SelectDeviceCallback onSelectDevice;
  final NullableBoolChangedCallback onScanAllowDuplicatesChanged;
  final ValueChanged<ScanMode?> onScanModeChanged;
  final ValueChanged<AndroidScanMode?> onAndroidScanModeChanged;
  final ValueChanged<AndroidScanCallbackType> onAndroidCallbackTypeChanged;
  final ValueChanged<AndroidScanMatchMode> onAndroidMatchModeChanged;
  final ValueChanged<AndroidScanNumOfMatches?> onAndroidNumOfMatchesChanged;
  final NullableBoolChangedCallback onAndroidLegacyChanged;
  final ValueChanged<AndroidScanPhy?> onAndroidPhyChanged;
  final NullableBoolChangedCallback onDarwinAllowDuplicatesChanged;
  final ValueChanged<LinuxScanTransport> onLinuxTransportChanged;
  final NullableBoolChangedCallback onLinuxDuplicateDataChanged;
  final NullableBoolChangedCallback onLinuxDiscoverableChanged;
  final ValueChanged<WindowsScanMode?> onWindowsScanModeChanged;

  @override
  Widget build(BuildContext context) {
    final scanEnabled = availabilityChecked && bluetoothAvailable;
    final textTheme = Theme.of(context).textTheme;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Devices',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          _StatusBadge(
                            _statusText,
                            tone: bluetoothAvailable
                                ? _StatusTone.neutral
                                : _StatusTone.warning,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      key: const ValueKey('ble_scan_button'),
                      onPressed: scanEnabled ? onToggleScan : null,
                      icon: Icon(
                        scanning ? Icons.stop : Icons.bluetooth_searching,
                      ),
                      label: Text(scanning ? 'Stop' : 'Scan 10s'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: serviceFilterController,
                  enabled: !scanning,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.filter_list),
                    labelText: 'Filter services',
                    hintText:
                        '180d, 180f, f000aa00-0451-4000-b000-000000000000',
                  ),
                ),
                const SizedBox(height: 8),
                _ScanOptionsPanel(
                  enabled: !scanning,
                  androidReportDelayMillisController:
                      androidReportDelayMillisController,
                  darwinSolicitedServiceUuidsController:
                      darwinSolicitedServiceUuidsController,
                  linuxRssiController: linuxRssiController,
                  linuxPathlossController: linuxPathlossController,
                  linuxPatternController: linuxPatternController,
                  windowsInRangeThresholdController:
                      windowsInRangeThresholdController,
                  windowsOutOfRangeThresholdController:
                      windowsOutOfRangeThresholdController,
                  windowsOutOfRangeTimeoutMillisController:
                      windowsOutOfRangeTimeoutMillisController,
                  windowsSamplingIntervalMillisController:
                      windowsSamplingIntervalMillisController,
                  scanAllowDuplicates: scanAllowDuplicates,
                  scanMode: scanMode,
                  androidScanMode: androidScanMode,
                  androidCallbackType: androidCallbackType,
                  androidMatchMode: androidMatchMode,
                  androidNumOfMatches: androidNumOfMatches,
                  androidLegacy: androidLegacy,
                  androidPhy: androidPhy,
                  darwinAllowDuplicates: darwinAllowDuplicates,
                  linuxTransport: linuxTransport,
                  linuxDuplicateData: linuxDuplicateData,
                  linuxDiscoverable: linuxDiscoverable,
                  windowsScanMode: windowsScanMode,
                  onScanAllowDuplicatesChanged: onScanAllowDuplicatesChanged,
                  onScanModeChanged: onScanModeChanged,
                  onAndroidScanModeChanged: onAndroidScanModeChanged,
                  onAndroidCallbackTypeChanged: onAndroidCallbackTypeChanged,
                  onAndroidMatchModeChanged: onAndroidMatchModeChanged,
                  onAndroidNumOfMatchesChanged: onAndroidNumOfMatchesChanged,
                  onAndroidLegacyChanged: onAndroidLegacyChanged,
                  onAndroidPhyChanged: onAndroidPhyChanged,
                  onDarwinAllowDuplicatesChanged:
                      onDarwinAllowDuplicatesChanged,
                  onLinuxTransportChanged: onLinuxTransportChanged,
                  onLinuxDuplicateDataChanged: onLinuxDuplicateDataChanged,
                  onLinuxDiscoverableChanged: onLinuxDiscoverableChanged,
                  onWindowsScanModeChanged: onWindowsScanModeChanged,
                ),
                if (scanning) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: _scanProgress),
                ],
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: Divider(height: 1)),
        if (devices.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              icon: Icons.bluetooth_disabled,
              title: scanning ? 'Listening for advertisements' : 'No devices',
              message: scanning
                  ? 'Devices will appear here as they advertise.'
                  : 'Start a scan to find nearby BLE peripherals.',
            ),
          )
        else
          SliverList.separated(
            key: const ValueKey('ble_devices_list'),
            itemCount: devices.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final result = devices[index];
              return _DeviceResultTile(
                result: result,
                selected: result.deviceId == selectedDeviceId,
                onTap: () => onSelectDevice(result.deviceId),
              );
            },
          ),
      ],
    );
  }

  double get _scanProgress {
    if (!scanning) {
      return 0;
    }
    final remaining =
        scanRemaining.inMilliseconds / scanDuration.inMilliseconds;
    return 1 - remaining.clamp(0, 1);
  }

  String get _statusText {
    if (!availabilityChecked) {
      return 'Checking Bluetooth...';
    }
    if (bluetoothAvailable) {
      return scanning ? '${devices.length} found' : 'Ready';
    }
    return switch (bluetoothState) {
      BlueBluetoothState.poweredOff => 'Bluetooth is off.',
      BlueBluetoothState.unauthorized => 'Bluetooth permission is missing.',
      BlueBluetoothState.unavailable => 'Bluetooth is unavailable.',
      BlueBluetoothState.unknown => 'Bluetooth state is unknown.',
      BlueBluetoothState.poweredOn => 'Ready',
    };
  }
}

class _ScanOptionsPanel extends StatelessWidget {
  const _ScanOptionsPanel({
    required this.enabled,
    required this.androidReportDelayMillisController,
    required this.darwinSolicitedServiceUuidsController,
    required this.linuxRssiController,
    required this.linuxPathlossController,
    required this.linuxPatternController,
    required this.windowsInRangeThresholdController,
    required this.windowsOutOfRangeThresholdController,
    required this.windowsOutOfRangeTimeoutMillisController,
    required this.windowsSamplingIntervalMillisController,
    required this.scanAllowDuplicates,
    required this.scanMode,
    required this.androidScanMode,
    required this.androidCallbackType,
    required this.androidMatchMode,
    required this.androidNumOfMatches,
    required this.androidLegacy,
    required this.androidPhy,
    required this.darwinAllowDuplicates,
    required this.linuxTransport,
    required this.linuxDuplicateData,
    required this.linuxDiscoverable,
    required this.windowsScanMode,
    required this.onScanAllowDuplicatesChanged,
    required this.onScanModeChanged,
    required this.onAndroidScanModeChanged,
    required this.onAndroidCallbackTypeChanged,
    required this.onAndroidMatchModeChanged,
    required this.onAndroidNumOfMatchesChanged,
    required this.onAndroidLegacyChanged,
    required this.onAndroidPhyChanged,
    required this.onDarwinAllowDuplicatesChanged,
    required this.onLinuxTransportChanged,
    required this.onLinuxDuplicateDataChanged,
    required this.onLinuxDiscoverableChanged,
    required this.onWindowsScanModeChanged,
  });

  final bool enabled;
  final TextEditingController androidReportDelayMillisController;
  final TextEditingController darwinSolicitedServiceUuidsController;
  final TextEditingController linuxRssiController;
  final TextEditingController linuxPathlossController;
  final TextEditingController linuxPatternController;
  final TextEditingController windowsInRangeThresholdController;
  final TextEditingController windowsOutOfRangeThresholdController;
  final TextEditingController windowsOutOfRangeTimeoutMillisController;
  final TextEditingController windowsSamplingIntervalMillisController;
  final bool? scanAllowDuplicates;
  final ScanMode? scanMode;
  final AndroidScanMode? androidScanMode;
  final AndroidScanCallbackType androidCallbackType;
  final AndroidScanMatchMode androidMatchMode;
  final AndroidScanNumOfMatches? androidNumOfMatches;
  final bool? androidLegacy;
  final AndroidScanPhy? androidPhy;
  final bool? darwinAllowDuplicates;
  final LinuxScanTransport linuxTransport;
  final bool? linuxDuplicateData;
  final bool? linuxDiscoverable;
  final WindowsScanMode? windowsScanMode;
  final NullableBoolChangedCallback onScanAllowDuplicatesChanged;
  final ValueChanged<ScanMode?> onScanModeChanged;
  final ValueChanged<AndroidScanMode?> onAndroidScanModeChanged;
  final ValueChanged<AndroidScanCallbackType> onAndroidCallbackTypeChanged;
  final ValueChanged<AndroidScanMatchMode> onAndroidMatchModeChanged;
  final ValueChanged<AndroidScanNumOfMatches?> onAndroidNumOfMatchesChanged;
  final NullableBoolChangedCallback onAndroidLegacyChanged;
  final ValueChanged<AndroidScanPhy?> onAndroidPhyChanged;
  final NullableBoolChangedCallback onDarwinAllowDuplicatesChanged;
  final ValueChanged<LinuxScanTransport> onLinuxTransportChanged;
  final NullableBoolChangedCallback onLinuxDuplicateDataChanged;
  final NullableBoolChangedCallback onLinuxDiscoverableChanged;
  final ValueChanged<WindowsScanMode?> onWindowsScanModeChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('ble_scan_options_panel'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            'Scan options',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!_showsDarwinOptions(context) &&
                      !_showsLinuxOptions(context))
                    _BoolOptionDropdown(
                      label: 'Allow duplicates',
                      enabled: enabled,
                      value: scanAllowDuplicates,
                      defaultLabel: 'Default (Enabled)',
                      onChanged: onScanAllowDuplicatesChanged,
                    ),
                  if (_showsAndroidOptions(context)) ...[
                    _EnumOptionDropdown<AndroidScanMode>(
                      label: 'Android mode',
                      enabled: enabled,
                      value: androidScanMode,
                      values: AndroidScanMode.values,
                      defaultLabel: 'Default (Low latency)',
                      onChanged: onAndroidScanModeChanged,
                    ),
                    _EnumOptionDropdown<AndroidScanCallbackType>(
                      label: 'Callback type',
                      enabled: enabled,
                      value: androidCallbackType,
                      values: AndroidScanCallbackType.values,
                      includeDefault: false,
                      onChanged: (value) {
                        if (value != null) {
                          onAndroidCallbackTypeChanged(value);
                        }
                      },
                    ),
                    _EnumOptionDropdown<AndroidScanMatchMode>(
                      label: 'Match mode',
                      enabled: enabled,
                      value: androidMatchMode,
                      values: AndroidScanMatchMode.values,
                      includeDefault: false,
                      onChanged: (value) {
                        if (value != null) {
                          onAndroidMatchModeChanged(value);
                        }
                      },
                    ),
                    _EnumOptionDropdown<AndroidScanNumOfMatches>(
                      label: 'Num matches',
                      enabled: enabled,
                      value: androidNumOfMatches,
                      values: AndroidScanNumOfMatches.values,
                      defaultLabel: 'Default (System)',
                      onChanged: onAndroidNumOfMatchesChanged,
                    ),
                    _NumberOptionField(
                      controller: androidReportDelayMillisController,
                      enabled: enabled,
                      label: 'Report delay ms',
                      defaultValueLabel: 'Default (0 ms)',
                    ),
                    _BoolOptionDropdown(
                      label: 'Legacy',
                      enabled: enabled,
                      value: androidLegacy,
                      defaultLabel: 'Default (System)',
                      onChanged: onAndroidLegacyChanged,
                    ),
                    _EnumOptionDropdown<AndroidScanPhy>(
                      label: 'PHY',
                      enabled: enabled,
                      value: androidPhy,
                      values: AndroidScanPhy.values,
                      defaultLabel: 'Default (System)',
                      onChanged: onAndroidPhyChanged,
                    ),
                  ],
                  if (_showsDarwinOptions(context)) ...[
                    _BoolOptionDropdown(
                      label: 'Allow duplicates',
                      enabled: enabled,
                      value: darwinAllowDuplicates,
                      defaultLabel: 'Default (Enabled)',
                      onChanged: onDarwinAllowDuplicatesChanged,
                    ),
                    _TextOptionField(
                      controller: darwinSolicitedServiceUuidsController,
                      enabled: enabled,
                      label: 'Solicited services',
                      hintText: '180d, 180f',
                      defaultValueLabel: 'Default (None)',
                    ),
                  ],
                  if (_showsLinuxOptions(context)) ...[
                    _NumberOptionField(
                      controller: linuxRssiController,
                      enabled: enabled,
                      label: 'RSSI',
                      defaultValueLabel: 'Default (No filter)',
                    ),
                    _NumberOptionField(
                      controller: linuxPathlossController,
                      enabled: enabled,
                      label: 'Pathloss',
                      defaultValueLabel: 'Default (No filter)',
                    ),
                    _EnumOptionDropdown<LinuxScanTransport>(
                      label: 'Transport',
                      enabled: enabled,
                      value: linuxTransport,
                      values: LinuxScanTransport.values,
                      includeDefault: false,
                      onChanged: (value) {
                        if (value != null) {
                          onLinuxTransportChanged(value);
                        }
                      },
                    ),
                    _BoolOptionDropdown(
                      label: 'Allow duplicates',
                      enabled: enabled,
                      value: linuxDuplicateData,
                      defaultLabel: 'Default (Disabled)',
                      onChanged: onLinuxDuplicateDataChanged,
                    ),
                    _BoolOptionDropdown(
                      label: 'Discoverable',
                      enabled: enabled,
                      value: linuxDiscoverable,
                      defaultLabel: 'Default (System)',
                      onChanged: onLinuxDiscoverableChanged,
                    ),
                    _TextOptionField(
                      controller: linuxPatternController,
                      enabled: enabled,
                      label: 'Pattern',
                      defaultValueLabel: 'Default (None)',
                    ),
                  ],
                  if (_showsWindowsOptions(context)) ...[
                    _EnumOptionDropdown<WindowsScanMode>(
                      label: 'Scan mode',
                      enabled: enabled,
                      value: windowsScanMode,
                      values: WindowsScanMode.values,
                      defaultLabel: 'Default (System)',
                      onChanged: onWindowsScanModeChanged,
                    ),
                    _NumberOptionField(
                      controller: windowsInRangeThresholdController,
                      enabled: enabled,
                      label: 'In range dBm',
                      defaultValueLabel: 'Default (No filter)',
                    ),
                    _NumberOptionField(
                      controller: windowsOutOfRangeThresholdController,
                      enabled: enabled,
                      label: 'Out range dBm',
                      defaultValueLabel: 'Default (No filter)',
                    ),
                    _NumberOptionField(
                      controller: windowsOutOfRangeTimeoutMillisController,
                      enabled: enabled,
                      label: 'Out timeout ms',
                      defaultValueLabel: 'Default (System)',
                    ),
                    _NumberOptionField(
                      controller: windowsSamplingIntervalMillisController,
                      enabled: enabled,
                      label: 'Sample interval ms',
                      defaultValueLabel: 'Default (System)',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnumOptionDropdown<T extends Enum> extends StatelessWidget {
  const _EnumOptionDropdown({
    required this.label,
    required this.enabled,
    required this.value,
    required this.values,
    required this.onChanged,
    this.includeDefault = true,
    this.defaultLabel = 'Default',
  });

  final String label;
  final bool enabled;
  final T? value;
  final List<T> values;
  final ValueChanged<T?> onChanged;
  final bool includeDefault;
  final String defaultLabel;

  @override
  Widget build(BuildContext context) {
    final choices = <_OptionChoice<T?>>[
      if (includeDefault) _OptionChoice<T?>(null, defaultLabel),
      for (final option in values)
        _OptionChoice<T?>(option, _enumLabel(option)),
    ];
    return _ChoiceOptionTile<T?>(
      label: label,
      enabled: enabled,
      value: value,
      defaultValue: includeDefault ? null : values.first,
      choices: choices,
      onSelected: onChanged,
    );
  }
}

class _BoolOptionDropdown extends StatelessWidget {
  const _BoolOptionDropdown({
    required this.label,
    required this.enabled,
    required this.value,
    required this.onChanged,
    this.defaultLabel = 'Default',
  });

  final String label;
  final bool enabled;
  final bool? value;
  final NullableBoolChangedCallback onChanged;
  final String defaultLabel;

  @override
  Widget build(BuildContext context) {
    return _ChoiceOptionTile<bool?>(
      label: label,
      enabled: enabled,
      value: value,
      defaultValue: null,
      choices: [
        _OptionChoice<bool?>(null, defaultLabel),
        _OptionChoice<bool?>(true, 'Enabled'),
        _OptionChoice<bool?>(false, 'Disabled'),
      ],
      onSelected: onChanged,
    );
  }
}

class _ChoiceOptionTile<T> extends StatelessWidget {
  const _ChoiceOptionTile({
    required this.label,
    required this.enabled,
    required this.value,
    required this.defaultValue,
    required this.choices,
    required this.onSelected,
  });

  final String label;
  final bool enabled;
  final T value;
  final T defaultValue;
  final List<_OptionChoice<T>> choices;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedValue = value ?? defaultValue;
    final selected = choices.firstWhere(
      (choice) => choice.value == selectedValue,
      orElse: () => choices.first,
    );
    return PopupMenuButton<T>(
      enabled: enabled,
      initialValue: selected.value,
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          for (final choice in choices)
            PopupMenuItem<T>(value: choice.value, child: Text(choice.label)),
        ];
      },
      child: _OptionTileShell(
        enabled: enabled,
        label: label,
        value: selected.label,
        trailing: Icons.expand_more,
      ),
    );
  }
}

class _OptionChoice<T> {
  const _OptionChoice(this.value, this.label);

  final T value;
  final String label;
}

class _NumberOptionField extends StatelessWidget {
  const _NumberOptionField({
    required this.controller,
    required this.enabled,
    required this.label,
    this.defaultValueLabel = 'Default',
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String defaultValueLabel;

  @override
  Widget build(BuildContext context) {
    return _TextOptionField(
      controller: controller,
      enabled: enabled,
      label: label,
      defaultValueLabel: defaultValueLabel,
      keyboardType: const TextInputType.numberWithOptions(signed: true),
    );
  }
}

class _TextOptionField extends StatelessWidget {
  const _TextOptionField({
    required this.controller,
    required this.enabled,
    required this.label,
    this.defaultValueLabel = 'Default',
    this.hintText,
    this.keyboardType,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String defaultValueLabel;
  final String? hintText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final text = controller.text.trim();
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled
              ? () => _showTextOptionDialog(
                  context: context,
                  controller: controller,
                  label: label,
                  hintText: hintText,
                  keyboardType: keyboardType,
                )
              : null,
          child: _OptionTileShell(
            enabled: enabled,
            label: label,
            value: text.isEmpty ? defaultValueLabel : text,
            trailing: Icons.edit,
          ),
        );
      },
    );
  }
}

class _OptionTileShell extends StatelessWidget {
  const _OptionTileShell({
    required this.enabled,
    required this.label,
    required this.value,
    required this.trailing,
  });

  final bool enabled;
  final String label;
  final String value;
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.38);
    final valueColor = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurface.withValues(alpha: 0.38);
    return SizedBox(
      width: 160,
      height: 68,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: valueColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(trailing, size: 18, color: valueColor),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showTextOptionDialog({
  required BuildContext context,
  required TextEditingController controller,
  required String label,
  required String? hintText,
  required TextInputType? keyboardType,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return _TextOptionDialog(
        controller: controller,
        label: label,
        hintText: hintText,
        keyboardType: keyboardType,
      );
    },
  );
}

class _TextOptionDialog extends StatefulWidget {
  const _TextOptionDialog({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final TextInputType? keyboardType;

  @override
  State<_TextOptionDialog> createState() => _TextOptionDialogState();
}

class _TextOptionDialogState extends State<_TextOptionDialog> {
  late final TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.controller.text);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _apply() {
    widget.controller.text = _editController.text.trim();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.label),
      content: TextField(
        controller: _editController,
        keyboardType: widget.keyboardType,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _apply(),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.controller.clear();
            Navigator.of(context).pop();
          },
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _apply, child: const Text('Apply')),
      ],
    );
  }
}

class _DeviceResultTile extends StatelessWidget {
  const _DeviceResultTile({
    required this.result,
    required this.selected,
    required this.onTap,
  });

  final BlueScanResult result;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = result.name.trim();
    final manufacturerData = result.manufacturerData;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        key: ValueKey('ble_device_row_name_${result.name}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name.isEmpty ? 'Unnamed device' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${result.rssi} dBm',
                          style: textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      result.deviceId,
                      style: textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _deviceMetadata(result, manufacturerData.length),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckboxRow extends StatelessWidget {
  const _CheckboxRow({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: (nextValue) => onChanged(nextValue ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicePane extends StatelessWidget {
  const _DevicePane({
    required this.deviceId,
    required this.title,
    required this.connectionState,
    required this.connecting,
    required this.discovering,
    required this.services,
    required this.latestValues,
    required this.notificationKeys,
    required this.status,
    required this.onConnect,
    required this.onDisconnect,
    required this.onDiscoverServices,
    required this.onRead,
    required this.onWrite,
    required this.onToggleNotify,
    required this.writeControllerFor,
    required this.writeWithoutResponseFor,
    required this.onWriteModeChanged,
  });

  final String? deviceId;
  final String? title;
  final BlueConnectionState connectionState;
  final bool connecting;
  final bool discovering;
  final List<BluetoothService> services;
  final Map<String, Uint8List> latestValues;
  final Set<String> notificationKeys;
  final String? status;
  final DeviceActionCallback onConnect;
  final DeviceActionCallback onDisconnect;
  final DeviceActionCallback onDiscoverServices;
  final CharacteristicActionCallback onRead;
  final CharacteristicActionCallback onWrite;
  final CharacteristicActionCallback onToggleNotify;
  final WriteControllerFactory writeControllerFor;
  final WriteModeLookup writeWithoutResponseFor;
  final WriteModeChangedCallback onWriteModeChanged;

  bool get _connected => connectionState == BlueConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    if (deviceId == null) {
      return const _EmptyState(
        icon: Icons.ads_click,
        title: 'Select a device',
        message: 'Scan nearby BLE devices, then select one to connect.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final summary = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ?? deviceId!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusBadge(
                        connectionState.value,
                        tone: _connected
                            ? _StatusTone.success
                            : _StatusTone.neutral,
                      ),
                      Text(
                        '${services.length} service(s)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (status != null)
                        Text(
                          status!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: compact ? WrapAlignment.start : WrapAlignment.end,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('ble_connect_button'),
                    onPressed: connecting
                        ? null
                        : _connected
                        ? onDisconnect
                        : onConnect,
                    icon: connecting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_connected ? Icons.link_off : Icons.link),
                    label: Text(
                      connecting
                          ? 'Connecting'
                          : _connected
                          ? 'Disconnect'
                          : 'Connect',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _connected && !discovering
                        ? onDiscoverServices
                        : null,
                    icon: discovering
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.account_tree),
                    label: const Text('Discover'),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [summary, const SizedBox(height: 10), actions],
                );
              }

              return Row(
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 16),
                  actions,
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: services.isEmpty
              ? _EmptyState(
                  icon: Icons.account_tree_outlined,
                  title: _connected ? 'No services yet' : 'Not connected',
                  message: _connected
                      ? 'Use Discover to refresh services.'
                      : 'Connect before discovering services.',
                )
              : ListView.builder(
                  itemCount: services.length,
                  itemBuilder: (context, index) {
                    final service = services[index];
                    return _ServiceTile(
                      service: service,
                      latestValues: latestValues,
                      notificationKeys: notificationKeys,
                      onRead: onRead,
                      onWrite: onWrite,
                      onToggleNotify: onToggleNotify,
                      writeControllerFor: writeControllerFor,
                      writeWithoutResponseFor: writeWithoutResponseFor,
                      onWriteModeChanged: onWriteModeChanged,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.latestValues,
    required this.notificationKeys,
    required this.onRead,
    required this.onWrite,
    required this.onToggleNotify,
    required this.writeControllerFor,
    required this.writeWithoutResponseFor,
    required this.onWriteModeChanged,
  });

  final BluetoothService service;
  final Map<String, Uint8List> latestValues;
  final Set<String> notificationKeys;
  final CharacteristicActionCallback onRead;
  final CharacteristicActionCallback onWrite;
  final CharacteristicActionCallback onToggleNotify;
  final WriteControllerFactory writeControllerFor;
  final WriteModeLookup writeWithoutResponseFor;
  final WriteModeChangedCallback onWriteModeChanged;

  @override
  Widget build(BuildContext context) {
    final characteristicCount = service.characteristicDetails.length;
    final dividerColor = Theme.of(context).dividerTheme.color;
    return Material(
      color: Colors.transparent,
      shape: Border(bottom: BorderSide(color: dividerColor ?? Colors.grey)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          initiallyExpanded: false,
          title: SelectableText(
            service.uuid,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '$characteristicCount characteristic${characteristicCount == 1 ? '' : 's'}',
          ),
          children: [
            for (final characteristic in service.characteristicDetails)
              _CharacteristicRow(
                service: service,
                characteristic: characteristic,
                value:
                    latestValues[characteristicKey(
                      service.uuid,
                      characteristic.uuid,
                    )],
                notifying: notificationKeys.contains(
                  characteristicKey(service.uuid, characteristic.uuid),
                ),
                writeWithoutResponse: writeWithoutResponseFor(
                  characteristicKey(service.uuid, characteristic.uuid),
                ),
                onRead: onRead,
                onWrite: onWrite,
                onToggleNotify: onToggleNotify,
                onWriteModeChanged: (enabled) => onWriteModeChanged(
                  characteristicKey(service.uuid, characteristic.uuid),
                  enabled,
                ),
                writeController: writeControllerFor(
                  characteristicKey(service.uuid, characteristic.uuid),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CharacteristicRow extends StatelessWidget {
  const _CharacteristicRow({
    required this.service,
    required this.characteristic,
    required this.value,
    required this.notifying,
    required this.writeWithoutResponse,
    required this.onRead,
    required this.onWrite,
    required this.onToggleNotify,
    required this.onWriteModeChanged,
    required this.writeController,
  });

  final BluetoothService service;
  final BluetoothCharacteristicInfo characteristic;
  final Uint8List? value;
  final bool notifying;
  final bool writeWithoutResponse;
  final CharacteristicActionCallback onRead;
  final CharacteristicActionCallback onWrite;
  final CharacteristicActionCallback onToggleNotify;
  final ValueChanged<bool> onWriteModeChanged;
  final TextEditingController writeController;

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerTheme.color;
    final utf8Preview = value == null ? null : formatUtf8Preview(value!);
    final characteristicId = characteristic.uuid;
    final valuePreview = _ValuePreview(
      hex: value == null ? '<none>' : formatBleValue(value!),
      utf8Preview: utf8Preview,
    );
    final effectiveWriteWithoutResponse =
        writeWithoutResponse ||
        (!characteristic.canWriteWithResponse &&
            characteristic.canWriteWithoutResponse);
    final writeDisclosure = characteristic.canWrite
        ? _WriteDisclosure(
            controller: writeController,
            writeWithoutResponse: effectiveWriteWithoutResponse,
            canWriteWithResponse: characteristic.canWriteWithResponse,
            canWriteWithoutResponse: characteristic.canWriteWithoutResponse,
            onWriteModeChanged: onWriteModeChanged,
            onWrite: () => onWrite(service, characteristicId),
          )
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: dividerColor ?? Colors.grey)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactHeader = constraints.maxWidth < 520;
            final idText = SelectableText(
              characteristicId,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            );
            final inspectActions = Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: characteristic.canRead
                      ? () => onRead(service, characteristicId)
                      : null,
                  icon: const Icon(Icons.download),
                  label: const Text('Read'),
                ),
                OutlinedButton.icon(
                  onPressed: characteristic.canSubscribe
                      ? () => onToggleNotify(service, characteristicId)
                      : null,
                  icon: Icon(
                    notifying
                        ? Icons.notifications_active
                        : Icons.notifications,
                  ),
                  label: Text(notifying ? 'Stop notify' : 'Notify'),
                ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compactHeader)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      idText,
                      const SizedBox(height: 8),
                      inspectActions,
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: idText),
                      const SizedBox(width: 12),
                      inspectActions,
                    ],
                  ),
                const SizedBox(height: 10),
                valuePreview,
                if (writeDisclosure != null) ...[
                  const SizedBox(height: 6),
                  writeDisclosure,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WriteDisclosure extends StatelessWidget {
  const _WriteDisclosure({
    required this.controller,
    required this.writeWithoutResponse,
    required this.canWriteWithResponse,
    required this.canWriteWithoutResponse,
    required this.onWriteModeChanged,
    required this.onWrite,
  });

  final TextEditingController controller;
  final bool writeWithoutResponse;
  final bool canWriteWithResponse;
  final bool canWriteWithoutResponse;
  final ValueChanged<bool> onWriteModeChanged;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          leading: const Icon(Icons.upload, size: 18),
          title: Text(
            'Write value',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Value',
                hintText: '01 02 03 or text',
              ),
            ),
            const SizedBox(height: 8),
            _WriteOptions(
              writeWithoutResponse: writeWithoutResponse,
              onWriteModeChanged:
                  canWriteWithResponse && canWriteWithoutResponse
                  ? onWriteModeChanged
                  : null,
              onWrite: onWrite,
            ),
          ],
        ),
      ),
    );
  }
}

class _WriteOptions extends StatelessWidget {
  const _WriteOptions({
    required this.writeWithoutResponse,
    required this.onWriteModeChanged,
    required this.onWrite,
  });

  final bool writeWithoutResponse;
  final ValueChanged<bool>? onWriteModeChanged;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 320;
        final noResponse = _CheckboxRow(
          value: writeWithoutResponse,
          onChanged: onWriteModeChanged ?? (_) {},
          label: 'No response',
        );
        final sendButton = FilledButton.tonalIcon(
          onPressed: onWrite,
          icon: const Icon(Icons.upload),
          label: const Text('Send'),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [noResponse, const SizedBox(height: 6), sendButton],
          );
        }

        return Row(
          children: [
            Expanded(child: noResponse),
            sendButton,
          ],
        );
      },
    );
  }
}

class _ValuePreview extends StatelessWidget {
  const _ValuePreview({required this.hex, required this.utf8Preview});

  final String hex;
  final String? utf8Preview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: colorScheme.onSurfaceVariant,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.download_done,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                utf8Preview == null
                    ? 'hex  $hex'
                    : 'hex  $hex\nutf8 "$utf8Preview"',
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventLogPanel extends StatelessWidget {
  const _EventLogPanel({required this.events, required this.onClear});

  final List<BleEvent> events;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Events (${events.length})',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  if (events.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear events',
                      onPressed: onClear,
                      icon: const Icon(Icons.clear_all),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: events.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No events',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _eventIcon(event.severity),
                              color: _eventColor(context, event.severity),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                event.message,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatTime(event.timestamp),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.label, {required this.tone});

  final String label;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = switch (tone) {
      _StatusTone.neutral => (
        background: colorScheme.surfaceContainerHighest,
        foreground: colorScheme.onSurfaceVariant,
      ),
      _StatusTone.success => (
        background: colorScheme.primaryContainer,
        foreground: colorScheme.onPrimaryContainer,
      ),
      _StatusTone.warning => (
        background: colorScheme.tertiaryContainer,
        foreground: colorScheme.onTertiaryContainer,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

enum _StatusTone { neutral, success, warning }

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatAge(DateTime advertisedDateTime) {
  final age = DateTime.now().difference(advertisedDateTime);
  if (age.inSeconds < 5) {
    return 'now';
  }
  if (age.inSeconds < 60) {
    return '${age.inSeconds}s ago';
  }
  return '${age.inMinutes}m ago';
}

String _deviceMetadata(BlueScanResult result, int manufacturerDataLength) {
  final serviceUuids = result.serviceUuids;
  final segments = <String>[
    'seen ${_formatAge(result.advertisedDateTime)}',
    if (manufacturerDataLength > 0) 'mfg $manufacturerDataLength B',
    if (serviceUuids.isNotEmpty) 'svc ${serviceUuids.take(3).join(', ')}',
    if (serviceUuids.length > 3) '+${serviceUuids.length - 3}',
  ];
  return segments.join('  /  ');
}

String _enumLabel(Enum value) {
  final words = value.name.replaceAllMapped(
    RegExp(r'([A-Z])'),
    (match) => ' ${match.group(1)!.toLowerCase()}',
  );
  return words[0].toUpperCase() + words.substring(1);
}

bool _showsAndroidOptions(BuildContext context) {
  return Theme.of(context).platform == TargetPlatform.android;
}

bool _showsDarwinOptions(BuildContext context) {
  return switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => true,
    _ => false,
  };
}

bool _showsLinuxOptions(BuildContext context) {
  return Theme.of(context).platform == TargetPlatform.linux;
}

bool _showsWindowsOptions(BuildContext context) {
  return Theme.of(context).platform == TargetPlatform.windows;
}

String _formatTime(DateTime timestamp) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${twoDigits(timestamp.hour)}:'
      '${twoDigits(timestamp.minute)}:'
      '${twoDigits(timestamp.second)}';
}

IconData _eventIcon(BleEventSeverity severity) {
  return switch (severity) {
    BleEventSeverity.info => Icons.info_outline,
    BleEventSeverity.warning => Icons.warning_amber,
    BleEventSeverity.error => Icons.error_outline,
  };
}

Color _eventColor(BuildContext context, BleEventSeverity severity) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (severity) {
    BleEventSeverity.info => colorScheme.primary,
    BleEventSeverity.warning => colorScheme.tertiary,
    BleEventSeverity.error => colorScheme.error,
  };
}
