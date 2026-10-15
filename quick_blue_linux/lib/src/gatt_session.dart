import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'device_property.dart';
import 'uuid_rules.dart';

typedef _BlueZPropertySubscription = StreamSubscription<List<String>>;
typedef _DevicePropertySubscriptions = Map<String, _BlueZPropertySubscription>;
typedef _NotificationSubscriptions = Map<String, _DevicePropertySubscriptions>;

/// Owns a client's GATT discovery, characteristic cache and notification watches.
/// Connection lifecycle and device lookup are supplied by the platform shell.
class LinuxGattSession {
  LinuxGattSession({
    required BlueZDevice Function(String) getDevice,
    required Future<void> Function(BlueZDevice) ensureConnected,
    required this.handleServiceDiscovered,
    required this.onServiceDiscoveryComplete,
    required this.handleCharacteristicValueChanged,
    required this.handleGattServicesChanged,
    required Logger logger,
  }) : _getDevice = getDevice,
       _ensureConnected = ensureConnected,
       _logger = logger;

  final BlueZDevice Function(String) _getDevice;
  final Future<void> Function(BlueZDevice) _ensureConnected;
  final void Function(String, String, List<BluetoothCharacteristicInfo>)
  handleServiceDiscovered;
  final void Function(String) onServiceDiscoveryComplete;
  final void Function(String, String, String, Uint8List)
  handleCharacteristicValueChanged;
  final void Function(String) handleGattServicesChanged;
  final Logger _logger;

  final _NotificationSubscriptions _notificationSubscriptions =
      <String, _DevicePropertySubscriptions>{};
  final Map<String, Future<void>> _serviceDiscoveryEmits =
      <String, Future<void>>{};
  final Map<String, Completer<void>> _deviceCancellations = {};
  // Survives clearDevice: retired native setup must settle and release its
  // client claim before a new generation can acquire the same claim.
  final Map<String, Future<void>> _notificationOperations = {};

  Completer<void> _cancellation(String deviceId) =>
      _deviceCancellations.putIfAbsent(deviceId, Completer<void>.new);

  void _checkCurrent(String deviceId, Completer<void> cancellation) {
    if (cancellation.isCompleted) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.cancelled,
        operation: 'gatt',
        deviceId: deviceId,
        message: 'Device state was cleared.',
      );
    }
  }

  final Map<String, bool> _servicesResolvedStates = <String, bool>{};
  final Map<String, String> _gattFingerprints = <String, String>{};
  final Map<String, _ResolvedCharacteristic> _resolvedCharacteristics =
      <String, _ResolvedCharacteristic>{};

  void watchDevice(BlueZDevice device) {
    _servicesResolvedStates[device.address] = device.servicesResolved;
  }

  void servicesResolvedChanged(BlueZDevice device) {
    final deviceId = device.address;
    final wasResolved = _servicesResolvedStates[deviceId] ?? false;
    final isResolved = device.servicesResolved;
    _servicesResolvedStates[deviceId] = isResolved;
    final fingerprint = isResolved ? _gattFingerprint(device) : null;
    final previousFingerprint = _gattFingerprints[deviceId];
    if ((wasResolved && !isResolved) ||
        (isResolved &&
            previousFingerprint != null &&
            previousFingerprint != fingerprint)) {
      _gattFingerprints.remove(deviceId);
      clearResolvedCharacteristics(deviceId);
      handleGattServicesChanged(deviceId);
    }
  }

  Future<void> clearDevice(String deviceId) async {
    _deviceCancellations.remove(deviceId)?.complete();
    _servicesResolvedStates.remove(deviceId);
    _gattFingerprints.remove(deviceId);
    _serviceDiscoveryEmits.remove(deviceId);
    clearResolvedCharacteristics(deviceId);
    await clearNotificationSubscriptions(deviceId);
  }

  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    final cancellation = _cancellation(deviceId);
    final operationKey =
        '$deviceId/${_characteristicKey(service, characteristic)}';
    await _serializeNotification(operationKey, () async {
      _checkCurrent(deviceId, cancellation);
      await _setNotifiable(
        deviceId,
        service,
        characteristic,
        bleInputProperty,
        cancellation,
      );
    });
  }

  Future<void> _serializeNotification(
    String operationKey,
    Future<void> Function() action,
  ) async {
    final previous = _notificationOperations[operationKey];
    final done = Completer<void>();
    _notificationOperations[operationKey] = done.future;
    try {
      await previous;
      await action();
    } finally {
      done.complete();
      if (identical(_notificationOperations[operationKey], done.future)) {
        _notificationOperations.remove(operationKey);
      }
    }
  }

  Future<void> _setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
    Completer<void> cancellation,
  ) async {
    final resolved = await _resolveCharacteristic(
      deviceId,
      service,
      characteristic,
    );
    final device = resolved.device;
    final targetCharacteristic = resolved.characteristic;

    final key = _characteristicKey(service, characteristic);

    if (bleInputProperty == BleInputProperty.disabled) {
      if (targetCharacteristic.notifying) {
        await _runBlueZGattOperation(
          operation: 'setNotifiable',
          deviceId: deviceId,
          serviceId: service,
          characteristicId: characteristic,
          action: targetCharacteristic.stopNotify,
        );
      }
      await _removeNotificationSubscription(deviceId, key);
      return;
    }

    final requiredFlag = bleInputProperty == BleInputProperty.indication
        ? BlueZGattCharacteristicFlag.indicate
        : BlueZGattCharacteristicFlag.notify;
    if (!targetCharacteristic.flags.contains(requiredFlag)) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.unsupported,
        operation: 'setNotifiable',
        deviceId: deviceId,
        serviceId: service,
        characteristicId: characteristic,
        message:
            'Characteristic $characteristic on $service does not support '
            '${bleInputProperty.value}.',
      );
    }

    try {
      // BlueZ reference-counts StartNotify by D-Bus client. Call it even when
      // another engine already made the global Notifying property true.
      await _runBlueZGattOperation(
        operation: 'setNotifiable',
        deviceId: deviceId,
        serviceId: service,
        characteristicId: characteristic,
        action: targetCharacteristic.startNotify,
      );
    } on BlueZAlreadyExistsException {
      // This D-Bus client already enabled notifications.
    }

    if (cancellation.isCompleted) {
      try {
        await targetCharacteristic.stopNotify();
      } catch (error, stack) {
        _logger.warning('Late notification cleanup failed', error, stack);
      }
      _checkCurrent(deviceId, cancellation);
    }
    await _removeNotificationSubscription(deviceId, key);
    _checkCurrent(deviceId, cancellation);

    final subscription = targetCharacteristic.propertiesChanged.listen(
      (changed) {
        if (changed.contains('Value')) {
          _emitCharacteristicValue(
            device.address,
            resolved.serviceId,
            resolved.characteristicId,
            targetCharacteristic,
          );
        }
        if (changed.contains('Notifying') && !targetCharacteristic.notifying) {
          _observeBackgroundOperation(
            _removeNotificationSubscription(device.address, key),
            'Unable to remove notification subscription for $deviceId',
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning(
          'Notification stream error for $deviceId ($service/$characteristic)',
          error,
          stackTrace,
        );
      },
    );

    final deviceSubscriptions = _notificationSubscriptions.putIfAbsent(
      deviceId,
      () => <String, _BlueZPropertySubscription>{},
    );
    deviceSubscriptions[key] = subscription;

    _emitCharacteristicValue(
      device.address,
      resolved.serviceId,
      resolved.characteristicId,
      targetCharacteristic,
    );
  }

  Future<Uint8List> readCharacteristicValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    final resolved = await _resolveCharacteristic(
      deviceId,
      service,
      characteristic,
    );
    final device = resolved.device;
    final targetCharacteristic = resolved.characteristic;

    final data = await _runBlueZGattOperation(
      operation: 'readValue',
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      action: targetCharacteristic.readValue,
    );
    final value = _emitCharacteristicValue(
      device.address,
      resolved.serviceId,
      resolved.characteristicId,
      targetCharacteristic,
      overrideValue: data,
    );
    return value;
  }

  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    final resolved = await _resolveCharacteristic(
      deviceId,
      service,
      characteristic,
    );
    final targetCharacteristic = resolved.characteristic;

    final writeType = bleOutputProperty == BleOutputProperty.withResponse
        ? BlueZGattCharacteristicWriteType.request
        : BlueZGattCharacteristicWriteType.command;

    await _runBlueZGattOperation(
      operation: 'writeValue',
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      action: () => targetCharacteristic.writeValue(value, type: writeType),
    );
  }

  Future<void> discoverServices(BlueZDevice device) async {
    final existing = _serviceDiscoveryEmits[device.address];
    if (existing != null) {
      return existing;
    }

    final cancellation = _cancellation(device.address);
    final emit = () async {
      await _waitForServicesResolved(device, cancellation: cancellation);
      _checkCurrent(device.address, cancellation);
      _emitResolvedServices(device);
    }();
    _serviceDiscoveryEmits[device.address] = emit;
    try {
      await emit;
    } finally {
      if (identical(_serviceDiscoveryEmits[device.address], emit)) {
        _serviceDiscoveryEmits.remove(device.address);
      }
    }
  }

  void _emitResolvedServices(BlueZDevice device) {
    for (final service in device.gattServices) {
      final serviceId = formatUuid(service.uuid);
      final characteristics = service.characteristics
          .map(
            (characteristic) => BluetoothCharacteristicInfo(
              uuid: formatUuid(characteristic.uuid),
              canRead: characteristic.flags.contains(
                BlueZGattCharacteristicFlag.read,
              ),
              canWriteWithResponse: characteristic.flags.contains(
                BlueZGattCharacteristicFlag.write,
              ),
              canWriteWithoutResponse: characteristic.flags.contains(
                BlueZGattCharacteristicFlag.writeWithoutResponse,
              ),
              canNotify: characteristic.flags.contains(
                BlueZGattCharacteristicFlag.notify,
              ),
              canIndicate: characteristic.flags.contains(
                BlueZGattCharacteristicFlag.indicate,
              ),
            ),
          )
          .toList(growable: false);
      handleServiceDiscovered(device.address, serviceId, characteristics);
    }
    _servicesResolvedStates[device.address] = device.servicesResolved;
    _gattFingerprints[device.address] = _gattFingerprint(device);
    onServiceDiscoveryComplete(device.address);
  }

  String _gattFingerprint(BlueZDevice device) {
    final services = device.gattServices.map((service) {
      final characteristics =
          service.characteristics
              .map((characteristic) => formatUuid(characteristic.uuid))
              .toList()
            ..sort();
      return '${formatUuid(service.uuid)}:${characteristics.join(',')}';
    }).toList()..sort();
    return services.join('|');
  }

  Future<void> _waitForServicesResolved(
    BlueZDevice device, {
    Duration timeout = const Duration(seconds: 15),
    Completer<void>? cancellation,
  }) async {
    return waitForDeviceProperty(
      device,
      propertyName: 'ServicesResolved',
      isReady: () => device.servicesResolved,
      timeout: timeout,
      cancelled: (cancellation ?? _cancellation(device.address)).future,
    );
  }

  Future<_ResolvedCharacteristic> _resolveCharacteristic(
    String deviceId,
    String serviceId,
    String characteristicId,
  ) async {
    final device = _getDevice(deviceId);
    final cancellation = _cancellation(deviceId);
    await _ensureConnected(device);
    _checkCurrent(deviceId, cancellation);
    await _waitForServicesResolved(device, cancellation: cancellation);
    _checkCurrent(deviceId, cancellation);

    final canonicalService = canonicalizeUuid(serviceId);
    final canonicalCharacteristic = canonicalizeUuid(characteristicId);
    final key = '$deviceId|$canonicalService|$canonicalCharacteristic';
    final cached = _resolvedCharacteristics[key];
    if (cached != null) {
      return cached;
    }

    final service = device.gattServices.firstWhereOrNull(
      (candidate) => bluezUuidToCanonical(candidate.uuid) == canonicalService,
    );
    if (service == null) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.notFound,
        operation: 'resolveCharacteristic',
        deviceId: deviceId,
        serviceId: serviceId,
        message: 'Service $serviceId not found on $deviceId.',
      );
    }

    final characteristic = service.characteristics.firstWhereOrNull(
      (candidate) =>
          bluezUuidToCanonical(candidate.uuid) == canonicalCharacteristic,
    );
    if (characteristic == null) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.notFound,
        operation: 'resolveCharacteristic',
        deviceId: deviceId,
        serviceId: serviceId,
        characteristicId: characteristicId,
        message:
            'Characteristic $characteristicId not found on $serviceId for '
            '$deviceId.',
      );
    }

    final resolved = _ResolvedCharacteristic(
      device: device,
      serviceId: formatUuid(service.uuid),
      characteristicId: formatUuid(characteristic.uuid),
      characteristic: characteristic,
    );
    _resolvedCharacteristics[key] = resolved;
    return resolved;
  }

  Uint8List _emitCharacteristicValue(
    String deviceId,
    String serviceId,
    String characteristicId,
    BlueZGattCharacteristic characteristic, {
    List<int>? overrideValue,
  }) {
    final data = overrideValue ?? characteristic.value;
    final value = data is Uint8List ? data : Uint8List.fromList(data);
    handleCharacteristicValueChanged(
      deviceId,
      serviceId,
      characteristicId,
      value,
    );
    return value;
  }

  void clearResolvedCharacteristics(String deviceId) {
    _resolvedCharacteristics.removeWhere(
      (key, _) => key.startsWith('$deviceId|'),
    );
  }

  Future<void> clearNotificationSubscriptions(String deviceId) async {
    final subscriptions = _notificationSubscriptions.remove(deviceId);
    if (subscriptions == null) {
      return;
    }
    await _cancelSubscriptions(subscriptions.values);
  }

  Future<void> stopNotificationsForClient(String deviceId) async {
    final subscriptions = Map<String, _BlueZPropertySubscription>.of(
      _notificationSubscriptions[deviceId] ?? {},
    );
    // Enqueue every release before yielding. Both setup and teardown share this
    // boundary across clearDevice generations; a late native stop must finish
    // before a retry can acquire the same D-Bus client's notification claim.
    final releases = <Future<void>>[];
    for (final entry in subscriptions.entries) {
      final key = entry.key;
      final resolved = _resolvedCharacteristics['$deviceId|$key'];
      if (resolved == null) {
        continue;
      }
      releases.add(
        _serializeNotification('$deviceId/$key', () async {
          // A queued release belongs only to the subscription captured above,
          // never to a replacement installed while it waited.
          if (!identical(
            _notificationSubscriptions[deviceId]?[key],
            entry.value,
          )) {
            return;
          }
          try {
            await resolved.characteristic.stopNotify();
          } on Object catch (error, stackTrace) {
            _logger.warning(
              'Failed to release this engine\'s notification for $deviceId',
              error,
              stackTrace,
            );
          }
        }),
      );
    }
    await Future.wait(releases);
  }

  Future<void> _removeNotificationSubscription(
    String deviceId,
    String key,
  ) async {
    final subscriptions = _notificationSubscriptions[deviceId];
    if (subscriptions == null) {
      return;
    }
    await _cancelMappedSubscription(subscriptions, key);
    if (subscriptions.isEmpty) {
      _notificationSubscriptions.remove(deviceId);
    }
  }

  Future<void> _cancelMappedSubscription<T>(
    Map<String, StreamSubscription<T>> subscriptions,
    String key,
  ) async {
    final subscription = subscriptions.remove(key);
    await _cancelSubscription(subscription);
  }

  Future<void> _cancelSubscriptions<T>(
    Iterable<StreamSubscription<T>> subscriptions,
  ) async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> _cancelSubscription<T>(
    StreamSubscription<T>? subscription,
  ) async {
    await subscription?.cancel();
  }

  void _observeBackgroundOperation(
    Future<void> operation,
    String failureMessage,
  ) {
    operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning(failureMessage, error, stackTrace);
      },
    );
  }

  String _characteristicKey(String serviceId, String characteristicId) {
    final serviceCanonical = canonicalizeUuid(serviceId);
    final characteristicCanonical = canonicalizeUuid(characteristicId);
    return '$serviceCanonical|$characteristicCanonical';
  }
}

Future<T> _runBlueZGattOperation<T>({
  required String operation,
  required String deviceId,
  required String serviceId,
  required String characteristicId,
  required Future<T> Function() action,
}) async {
  try {
    return await action();
  } on BlueZNotAuthorizedException catch (error, stackTrace) {
    Error.throwWithStackTrace(
      QuickBlueSecurityException(
        reason: QuickBlueSecurityErrorReason.insufficientAuthorization,
        nativeDomain: 'org.bluez.Error.NotAuthorized',
        nativeCode: null,
        operation: operation,
        deviceId: deviceId,
        serviceId: serviceId,
        characteristicId: characteristicId,
        message: error.message.isEmpty
            ? '$operation was not authorized by BlueZ.'
            : error.message,
      ),
      stackTrace,
    );
  }
}

class _ResolvedCharacteristic {
  _ResolvedCharacteristic({
    required this.device,
    required this.serviceId,
    required this.characteristicId,
    required this.characteristic,
  });

  final BlueZDevice device;
  final String serviceId;
  final String characteristicId;
  final BlueZGattCharacteristic characteristic;
}
