part of 'ble_explorer_page.dart';

class _DeviceResultTile extends StatelessWidget {
  const _DeviceResultTile({
    super.key,
    required this.result,
    required this.selected,
    required this.onTap,
  });

  factory _DeviceResultTile.prototype() {
    return _DeviceResultTile(
      result: BlueScanResult(
        name: 'Prototype device',
        deviceId: '00:00:00:00:00:00',
        rssi: -100,
        manufacturerData: Uint8List(8),
        serviceUuids: const [
          '0000180d-0000-1000-8000-00805f9b34fb',
          '0000180f-0000-1000-8000-00805f9b34fb',
        ],
      ),
      selected: false,
      onTap: () {},
    );
  }

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
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
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
                      Text(
                        result.deviceId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
