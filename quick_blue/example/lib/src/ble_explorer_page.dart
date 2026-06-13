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
      onToggleScan: _controller.toggleScan,
      onSelectDevice: (deviceId) =>
          _selectDevice(deviceId, openDetail: openDetailOnSelect),
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
    required this.onToggleScan,
    required this.onSelectDevice,
  });

  final bool availabilityChecked;
  final BlueBluetoothState bluetoothState;
  final bool bluetoothAvailable;
  final bool scanning;
  final Duration scanRemaining;
  final List<BlueScanResult> devices;
  final String? selectedDeviceId;
  final TextEditingController serviceFilterController;
  final ToggleScanCallback onToggleScan;
  final SelectDeviceCallback onSelectDevice;

  @override
  Widget build(BuildContext context) {
    final scanEnabled = availabilityChecked && bluetoothAvailable;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
                  hintText: '180d, 180f, f000aa00-0451-4000-b000-000000000000',
                ),
              ),
              if (scanning) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: _scanProgress),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: devices.isEmpty
              ? _EmptyState(
                  icon: Icons.bluetooth_disabled,
                  title: scanning
                      ? 'Listening for advertisements'
                      : 'No devices',
                  message: scanning
                      ? 'Devices will appear here as they advertise.'
                      : 'Start a scan to find nearby BLE peripherals.',
                )
              : ListView.separated(
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
                    onPressed: connecting || _connected ? null : onConnect,
                    icon: connecting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: const Text('Connect'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _connected ? onDisconnect : null,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
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
                      ? 'Run service discovery to inspect characteristics.'
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
    final characteristicCount = service.characteristics.length;
    return Material(
      color: Colors.transparent,
      shape: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          initiallyExpanded: service.characteristics.length <= 4,
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
            for (final characteristicId in service.characteristics)
              _CharacteristicRow(
                service: service,
                characteristicId: characteristicId,
                value:
                    latestValues[characteristicKey(
                      service.uuid,
                      characteristicId,
                    )],
                notifying: notificationKeys.contains(
                  characteristicKey(service.uuid, characteristicId),
                ),
                writeWithoutResponse: writeWithoutResponseFor(
                  characteristicKey(service.uuid, characteristicId),
                ),
                onRead: onRead,
                onWrite: onWrite,
                onToggleNotify: onToggleNotify,
                onWriteModeChanged: (enabled) => onWriteModeChanged(
                  characteristicKey(service.uuid, characteristicId),
                  enabled,
                ),
                writeController: writeControllerFor(
                  characteristicKey(service.uuid, characteristicId),
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
    required this.characteristicId,
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
  final String characteristicId;
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
    final utf8Preview = value == null ? null : formatUtf8Preview(value!);
    final valuePreview = _ValuePreview(
      hex: value == null ? '<none>' : formatBleValue(value!),
      utf8Preview: utf8Preview,
    );
    final writeDisclosure = _WriteDisclosure(
      controller: writeController,
      writeWithoutResponse: writeWithoutResponse,
      onWriteModeChanged: onWriteModeChanged,
      onWrite: () => onWrite(service, characteristicId),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
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
                  onPressed: () => onRead(service, characteristicId),
                  icon: const Icon(Icons.download),
                  label: const Text('Read'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onToggleNotify(service, characteristicId),
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
                const SizedBox(height: 6),
                writeDisclosure,
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
    required this.onWriteModeChanged,
    required this.onWrite,
  });

  final TextEditingController controller;
  final bool writeWithoutResponse;
  final ValueChanged<bool> onWriteModeChanged;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE5E7EB)),
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
              onWriteModeChanged: onWriteModeChanged,
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
  final ValueChanged<bool> onWriteModeChanged;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 320;
        final noResponse = _CheckboxRow(
          value: writeWithoutResponse,
          onChanged: onWriteModeChanged,
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
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Last read',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SelectableText(
              utf8Preview == null
                  ? 'hex  $hex'
                  : 'hex  $hex\nutf8 "$utf8Preview"',
              style: style,
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
    final colors = switch (tone) {
      _StatusTone.neutral => (
        background: const Color(0xFFF3F4F6),
        foreground: const Color(0xFF374151),
      ),
      _StatusTone.success => (
        background: const Color(0xFFECFDF5),
        foreground: const Color(0xFF047857),
      ),
      _StatusTone.warning => (
        background: const Color(0xFFFFF7ED),
        foreground: const Color(0xFFC2410C),
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
