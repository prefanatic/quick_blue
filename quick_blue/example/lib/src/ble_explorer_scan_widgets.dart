part of 'ble_explorer_page.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        SliverFloatingHeader(
          key: const ValueKey('ble_scan_header'),
          animationStyle: AnimationStyle.noAnimation,
          child: Material(
            color: colorScheme.surface,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
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
                      onScanAllowDuplicatesChanged:
                          onScanAllowDuplicatesChanged,
                      onScanModeChanged: onScanModeChanged,
                      onAndroidScanModeChanged: onAndroidScanModeChanged,
                      onAndroidCallbackTypeChanged:
                          onAndroidCallbackTypeChanged,
                      onAndroidMatchModeChanged: onAndroidMatchModeChanged,
                      onAndroidNumOfMatchesChanged:
                          onAndroidNumOfMatchesChanged,
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
          ),
        ),
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
          SliverPrototypeExtentList.builder(
            key: const ValueKey('ble_devices_list'),
            prototypeItem: _DeviceResultTile.prototype(),
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final result = devices[index];
              return _DeviceResultTile(
                key: ValueKey(result.deviceId),
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
