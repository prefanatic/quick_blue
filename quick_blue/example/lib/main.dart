import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quick_blue/quick_blue.dart';

typedef ToggleScanCallback = Future<void> Function();
typedef SelectDeviceCallback = Future<void> Function(String deviceId);
typedef DeviceActionCallback = Future<void> Function();
typedef CharacteristicActionCallback =
    Future<void> Function(BluetoothService service, String characteristicId);
typedef WriteControllerFactory =
    TextEditingController Function(String characteristicKey);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quick Blue',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BleExplorerPage(),
    );
  }
}

class BleExplorerPage extends StatefulWidget {
  const BleExplorerPage({super.key});

  @override
  State<BleExplorerPage> createState() => _BleExplorerPageState();
}

class _BleExplorerPageState extends State<BleExplorerPage> {
  final _devices = <String, BlueScanResult>{};
  final _services = <BluetoothService>[];
  final _latestValues = <String, Uint8List>{};
  final _writeControllers = <String, TextEditingController>{};
  final _notificationSubscriptions = <String, StreamSubscription<Uint8List>>{};

  StreamSubscription<BlueScanResult>? _scanSubscription;
  StreamSubscription<BluetoothConnectionStateChange>? _connectionSubscription;

  bool _bluetoothAvailable = false;
  bool _availabilityChecked = false;
  bool _scanning = false;
  bool _connecting = false;
  bool _discovering = false;
  String? _selectedDeviceId;
  BlueConnectionState _connectionState = BlueConnectionState.disconnected;
  String? _status;

  @override
  void initState() {
    super.initState();
    _checkBluetooth();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    for (final subscription in _notificationSubscriptions.values) {
      subscription.cancel();
    }
    for (final controller in _writeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _checkBluetooth() async {
    try {
      final available = await QuickBlue.isBluetoothAvailable();
      if (!mounted) {
        return;
      }
      setState(() {
        _bluetoothAvailable = available;
        _availabilityChecked = true;
        _status = available
            ? 'Bluetooth is available.'
            : 'Bluetooth is unavailable or permission is missing.';
      });
    } catch (error) {
      _showError('Bluetooth check failed', error);
      if (!mounted) {
        return;
      }
      setState(() {
        _availabilityChecked = true;
        _status = 'Bluetooth check failed.';
      });
    }
  }

  Future<void> _toggleScan() {
    return _scanning ? _stopScan() : _startScan();
  }

  Future<void> _startScan() async {
    await _scanSubscription?.cancel();
    setState(() {
      _devices.clear();
      _scanning = true;
      _status = 'Scanning...';
    });

    _scanSubscription = QuickBlue.scanResultStream.listen(
      (result) {
        if (!mounted) {
          return;
        }
        setState(() {
          _devices[result.deviceId] = result;
        });
      },
      onError: (Object error) {
        _showError('Scan failed', error);
        if (mounted) {
          setState(() {
            _scanning = false;
          });
        }
      },
    );

    try {
      await QuickBlue.startScan();
    } catch (error) {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _showError('Start scan failed', error);
      if (!mounted) {
        return;
      }
      setState(() {
        _scanning = false;
        _status = 'Scan could not start.';
      });
    }
  }

  Future<void> _stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await QuickBlue.stopScan();
    } catch (error) {
      _showError('Stop scan failed', error);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _scanning = false;
      _status = 'Scan stopped.';
    });
  }

  Future<void> _selectDevice(String deviceId) async {
    if (_selectedDeviceId == deviceId) {
      return;
    }
    await _connectionSubscription?.cancel();
    for (final subscription in _notificationSubscriptions.values) {
      await subscription.cancel();
    }
    _notificationSubscriptions.clear();

    final device = QuickBlue.device(deviceId);
    _connectionSubscription = device.connectionStateStream.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _connectionState = event.state;
        _status = 'Connection ${event.state.value} (${event.status.name}).';
      });
    });

    setState(() {
      _selectedDeviceId = deviceId;
      _connectionState = BlueConnectionState.disconnected;
      _services.clear();
      _latestValues.clear();
      _status = 'Selected ${_deviceTitle(deviceId)}.';
    });
  }

  Future<void> _connectSelected() async {
    final deviceId = _selectedDeviceId;
    if (deviceId == null) {
      return;
    }
    setState(() {
      _connecting = true;
      _status = 'Connecting...';
    });
    try {
      await _stopScan();
      await QuickBlue.device(deviceId).connect();
    } catch (error) {
      _showError('Connect failed', error);
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  Future<void> _disconnectSelected() async {
    final deviceId = _selectedDeviceId;
    if (deviceId == null) {
      return;
    }
    try {
      await QuickBlue.device(deviceId).disconnect();
      if (!mounted) {
        return;
      }
      setState(() {
        _services.clear();
        _latestValues.clear();
        _status = 'Disconnected.';
      });
    } catch (error) {
      _showError('Disconnect failed', error);
    }
  }

  Future<void> _discoverServices() async {
    final deviceId = _selectedDeviceId;
    if (deviceId == null) {
      return;
    }
    setState(() {
      _discovering = true;
      _services.clear();
      _status = 'Discovering services...';
    });
    try {
      final services = await QuickBlue.device(deviceId).discoverServices();
      if (!mounted) {
        return;
      }
      setState(() {
        _services.addAll(services);
        _status = 'Found ${services.length} service(s).';
      });
    } catch (error) {
      _showError('Discover services failed', error);
    } finally {
      if (mounted) {
        setState(() {
          _discovering = false;
        });
      }
    }
  }

  Future<void> _readCharacteristic(
    BluetoothService service,
    String characteristicId,
  ) async {
    try {
      final characteristic = QuickBlue.device(
        service.deviceId,
      ).characteristic(service.uuid, characteristicId);
      final value = await characteristic.read();
      if (!mounted) {
        return;
      }
      setState(() {
        _latestValues[_characteristicKey(service.uuid, characteristicId)] =
            value;
        _status = 'Read ${value.length} byte(s).';
      });
    } catch (error) {
      _showError('Read failed', error);
    }
  }

  Future<void> _writeCharacteristic(
    BluetoothService service,
    String characteristicId,
  ) async {
    final key = _characteristicKey(service.uuid, characteristicId);
    final text = _writeControllers[key]?.text ?? '';
    if (text.trim().isEmpty) {
      _showMessage('Enter bytes as hex or text before writing.');
      return;
    }

    try {
      final value = _parseValue(text);
      final characteristic = QuickBlue.device(
        service.deviceId,
      ).characteristic(service.uuid, characteristicId);
      await characteristic.write(value, BleOutputProperty.withResponse);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Wrote ${value.length} byte(s).';
      });
    } catch (error) {
      _showError('Write failed', error);
    }
  }

  Future<void> _toggleNotify(
    BluetoothService service,
    String characteristicId,
  ) async {
    final key = _characteristicKey(service.uuid, characteristicId);
    final subscription = _notificationSubscriptions.remove(key);
    if (subscription != null) {
      await subscription.cancel();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Notifications stopped.';
      });
      return;
    }

    try {
      final characteristic = QuickBlue.device(
        service.deviceId,
      ).characteristic(service.uuid, characteristicId);
      final newSubscription = characteristic.notifications().listen(
        (value) {
          if (!mounted) {
            return;
          }
          setState(() {
            _latestValues[key] = value;
            _status = 'Notification: ${value.length} byte(s).';
          });
        },
        onError: (Object error) {
          _notificationSubscriptions.remove(key);
          _showError('Notification failed', error);
        },
      );
      setState(() {
        _notificationSubscriptions[key] = newSubscription;
        _status = 'Notifications started.';
      });
    } catch (error) {
      _showError('Notify failed', error);
    }
  }

  Uint8List _parseValue(String text) {
    final trimmed = text.trim();
    final normalized = trimmed
        .replaceAll(RegExp(r'0x', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\s,;:-]+'), '');
    final looksHex =
        normalized.isNotEmpty &&
        normalized.length.isEven &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized);

    if (!looksHex) {
      return Uint8List.fromList(utf8.encode(text));
    }

    final bytes = <int>[];
    for (var i = 0; i < normalized.length; i += 2) {
      bytes.add(int.parse(normalized.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  TextEditingController _writeController(String key) {
    return _writeControllers.putIfAbsent(key, TextEditingController.new);
  }

  String _characteristicKey(String serviceId, String characteristicId) {
    return '$serviceId::$characteristicId';
  }

  String _deviceTitle(String deviceId) {
    final name = _devices[deviceId]?.name.trim();
    return name == null || name.isEmpty ? deviceId : name;
  }

  void _showError(String label, Object error) {
    _showMessage('$label: $error');
    if (!mounted) {
      return;
    }
    setState(() {
      _status = '$label.';
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((a, b) => b.advertisedDateTime.compareTo(a.advertisedDateTime));
    final selectedDeviceId = _selectedDeviceId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Blue'),
        actions: [
          IconButton(
            tooltip: 'Refresh Bluetooth status',
            onPressed: _checkBluetooth,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final scanPane = _ScanPane(
              availabilityChecked: _availabilityChecked,
              bluetoothAvailable: _bluetoothAvailable,
              scanning: _scanning,
              devices: devices,
              selectedDeviceId: selectedDeviceId,
              onToggleScan: _toggleScan,
              onSelectDevice: _selectDevice,
            );
            final detailPane = _DevicePane(
              deviceId: selectedDeviceId,
              title: selectedDeviceId == null
                  ? null
                  : _deviceTitle(selectedDeviceId),
              connectionState: _connectionState,
              connecting: _connecting,
              discovering: _discovering,
              services: _services,
              latestValues: _latestValues,
              notificationKeys: _notificationSubscriptions.keys.toSet(),
              status: _status,
              onConnect: _connectSelected,
              onDisconnect: _disconnectSelected,
              onDiscoverServices: _discoverServices,
              onRead: _readCharacteristic,
              onWrite: _writeCharacteristic,
              onToggleNotify: _toggleNotify,
              writeControllerFor: _writeController,
            );

            if (wide) {
              return Row(
                children: [
                  SizedBox(width: 360, child: scanPane),
                  const VerticalDivider(width: 1),
                  Expanded(child: detailPane),
                ],
              );
            }

            return Column(
              children: [
                SizedBox(height: 300, child: scanPane),
                const Divider(height: 1),
                Expanded(child: detailPane),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScanPane extends StatelessWidget {
  const _ScanPane({
    required this.availabilityChecked,
    required this.bluetoothAvailable,
    required this.scanning,
    required this.devices,
    required this.selectedDeviceId,
    required this.onToggleScan,
    required this.onSelectDevice,
  });

  final bool availabilityChecked;
  final bool bluetoothAvailable;
  final bool scanning;
  final List<BlueScanResult> devices;
  final String? selectedDeviceId;
  final ToggleScanCallback onToggleScan;
  final SelectDeviceCallback onSelectDevice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nearby devices',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusText,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: availabilityChecked ? onToggleScan : null,
                icon: Icon(scanning ? Icons.stop : Icons.bluetooth_searching),
                label: Text(scanning ? 'Stop' : 'Scan'),
              ),
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
                  itemCount: devices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final result = devices[index];
                    final name = result.name.trim();
                    final selected = result.deviceId == selectedDeviceId;
                    return ListTile(
                      selected: selected,
                      leading: const Icon(Icons.bluetooth),
                      title: Text(name.isEmpty ? 'Unnamed device' : name),
                      subtitle: Text(result.deviceId),
                      trailing: Text('${result.rssi} dBm'),
                      onTap: () => onSelectDevice(result.deviceId),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String get _statusText {
    if (!availabilityChecked) {
      return 'Checking Bluetooth...';
    }
    if (!bluetoothAvailable) {
      return 'Bluetooth is off or permission is missing.';
    }
    return scanning ? '${devices.length} found' : 'Ready';
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
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? deviceId!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${connectionState.value}${status == null ? '' : ' - $status'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
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
                  padding: const EdgeInsets.all(12),
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
  });

  final BluetoothService service;
  final Map<String, Uint8List> latestValues;
  final Set<String> notificationKeys;
  final CharacteristicActionCallback onRead;
  final CharacteristicActionCallback onWrite;
  final CharacteristicActionCallback onToggleNotify;
  final WriteControllerFactory writeControllerFor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: service.characteristics.length <= 4,
        title: Text(service.uuid),
        subtitle: Text('${service.characteristics.length} characteristic(s)'),
        children: [
          for (final characteristicId in service.characteristics)
            _CharacteristicRow(
              service: service,
              characteristicId: characteristicId,
              value:
                  latestValues[_characteristicKey(
                    service.uuid,
                    characteristicId,
                  )],
              notifying: notificationKeys.contains(
                _characteristicKey(service.uuid, characteristicId),
              ),
              onRead: onRead,
              onWrite: onWrite,
              onToggleNotify: onToggleNotify,
              writeController: writeControllerFor(
                _characteristicKey(service.uuid, characteristicId),
              ),
            ),
        ],
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
    required this.onRead,
    required this.onWrite,
    required this.onToggleNotify,
    required this.writeController,
  });

  final BluetoothService service;
  final String characteristicId;
  final Uint8List? value;
  final bool notifying;
  final CharacteristicActionCallback onRead;
  final CharacteristicActionCallback onWrite;
  final CharacteristicActionCallback onToggleNotify;
  final TextEditingController writeController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            characteristicId,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => onRead(service, characteristicId),
                icon: const Icon(Icons.download),
                label: const Text('Read'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => onToggleNotify(service, characteristicId),
                icon: Icon(
                  notifying ? Icons.notifications_off : Icons.notifications,
                ),
                label: Text(notifying ? 'Stop notify' : 'Notify'),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: writeController,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Hex bytes or text',
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => onWrite(service, characteristicId),
                icon: const Icon(Icons.upload),
                label: const Text('Write'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value == null ? 'Value: <none>' : 'Value: ${_formatBytes(value!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

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
      child: Padding(
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

String _characteristicKey(String serviceId, String characteristicId) {
  return '$serviceId::$characteristicId';
}

String _formatBytes(Uint8List value) {
  if (value.isEmpty) {
    return '<empty>';
  }
  return value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
}
