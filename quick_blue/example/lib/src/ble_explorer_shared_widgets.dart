part of 'ble_explorer_page.dart';

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    super.key,
    required this.axis,
    required this.onDragUpdate,
  });

  final Axis axis;
  final ValueChanged<double> onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resizingWidth = axis == Axis.horizontal;
    return MouseRegion(
      cursor: resizingWidth
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: resizingWidth
            ? (details) => onDragUpdate(details.delta.dx)
            : null,
        onVerticalDragUpdate: resizingWidth
            ? null
            : (details) => onDragUpdate(details.delta.dy),
        child: SizedBox(
          width: resizingWidth ? _resizeHandleExtent : double.infinity,
          height: resizingWidth ? double.infinity : _resizeHandleExtent,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
              child: SizedBox(
                width: resizingWidth ? 2 : 48,
                height: resizingWidth ? 48 : 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EventLogPanel extends StatelessWidget {
  const _EventLogPanel({
    required this.events,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onClear,
  });

  final List<BleEvent> events;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _eventLogHeaderHeight,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('ble_events_header'),
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                    ),
                    const SizedBox(width: 4),
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
          ),
        ),
        if (expanded) ...[
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
      ],
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
