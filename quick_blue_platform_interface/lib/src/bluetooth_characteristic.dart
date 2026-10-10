import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../models.dart';
import 'observability.dart';
import 'quick_blue_platform.dart';
import 'quick_blue_exception.dart';

/// A handle for a Bluetooth LE characteristic.
///
/// The handle is service-scoped so duplicate characteristic UUIDs under
/// different services can be addressed safely.
class BluetoothCharacteristic {
  @internal
  BluetoothCharacteristic.internal({
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
    required QuickBluePlatform platform,
    bool Function()? isValidSnapshot,
  }) : _platform = platform,
       _isValidSnapshot = isValidSnapshot;

  /// The platform-specific device identifier.
  final String deviceId;

  /// The service UUID containing this characteristic.
  final String serviceId;

  /// The characteristic UUID.
  final String characteristicId;
  final QuickBluePlatform _platform;
  final bool Function()? _isValidSnapshot;

  void _ensureSnapshotValid(String operation) {
    if (_isValidSnapshot?.call() ?? true) return;
    throw QuickBlueException(
      code: QuickBlueErrorCode.invalidState,
      operation: operation,
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
      message:
          'The bound GATT snapshot is invalid. Rediscover services and '
          'resolve a fresh bound characteristic before submitting new IO.',
    );
  }

  /// Value updates for this characteristic.
  ///
  /// Legacy platform events without a service id are still matched by
  /// characteristic UUID for compatibility.
  Stream<Uint8List> get valueStream {
    return _platform.characteristicValueStreamFor(
      deviceId,
      serviceId,
      characteristicId,
    );
  }

  /// Enables notifications, enables indications, or disables updates for this
  /// characteristic.
  ///
  /// Use [notifications] when the subscription should own setup and teardown.
  /// Use this method with [valueStream] when callers need to attach listeners
  /// before enabling updates, or when notification lifetime is managed
  /// separately from a single stream subscription.
  ///
  /// Security failures trigger one coordinated recovery attempt and retry.
  Future<void> setNotifiable(BleInputProperty bleInputProperty) {
    _ensureSnapshotValid('setNotifiable');
    return QuickBlueInstrumentation.observeFuture<void>(
      kind: QuickBlueOperationKind.setNotifiable,
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
      inputProperty: bleInputProperty,
      action: () => _platform.runWithSecurityRecovery(
        deviceId,
        () => _platform.setNotifiable(
          deviceId,
          serviceId,
          characteristicId,
          bleInputProperty,
        ),
      ),
    );
  }

  /// Enables notifications or indications while the returned stream is active.
  ///
  /// Values are not forwarded until notification setup succeeds. Canceling the
  /// stream disables updates again.
  /// Security failures during setup trigger one coordinated recovery attempt.
  Stream<Uint8List> notifications({
    BleInputProperty bleInputProperty = BleInputProperty.notification,
  }) {
    if (_isValidSnapshot != null) {
      return Stream<Uint8List>.multi((controller) {
        try {
          _ensureSnapshotValid('notifications');
        } catch (error, stack) {
          controller.addError(error, stack);
          controller.close();
          return;
        }
        final subscription = _notifications(bleInputProperty).listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller
          ..onPause = subscription.pause
          ..onResume = subscription.resume
          ..onCancel = subscription.cancel;
      });
    }
    return _notifications(bleInputProperty);
  }

  Stream<Uint8List> _notifications(BleInputProperty bleInputProperty) {
    return QuickBlueInstrumentation.observeStream<Uint8List>(
      kind: QuickBlueOperationKind.notifications,
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
      inputProperty: bleInputProperty,
      stream: () => _platform.characteristicNotifications(
        deviceId,
        serviceId,
        characteristicId,
        bleInputProperty: bleInputProperty,
      ),
      valueSize: (value) => value.length,
    );
  }

  /// Reads the current characteristic value.
  ///
  /// The future completes with the bytes returned by the platform read.
  /// Security failures trigger one coordinated recovery attempt and retry.
  Future<Uint8List> read() async {
    _ensureSnapshotValid('read');
    return QuickBlueInstrumentation.observeFuture<Uint8List>(
      kind: QuickBlueOperationKind.readCharacteristic,
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
      action: () => _platform.runWithSecurityRecovery(
        deviceId,
        () => _platform.readCharacteristicValue(
          deviceId,
          serviceId,
          characteristicId,
        ),
      ),
      measurements: (value) => <QuickBlueOperationMeasurement, num>{
        QuickBlueOperationMeasurement.byteCount: value.length,
      },
    );
  }

  /// Returns the device's native payload limit for this write mode, or null
  /// when no direct native query exists. Does not infer a limit from MTU or
  /// validate the characteristic's application-level constraints.
  Future<int?> maximumWriteValueLength(BleOutputProperty bleOutputProperty) {
    return _platform.maximumWriteValueLength(deviceId, bleOutputProperty);
  }

  /// Writes [value] to the characteristic.
  ///
  /// Without response, completion means local acceptance, not peer receipt:
  /// Darwin completes at CoreBluetooth handoff (or rejects a full native buffer
  /// with an invalid-state error); Android awaits its native write callback;
  /// Linux awaits the BlueZ D-Bus reply; Windows awaits the WinRT write result.
  /// Await writes sequentially to respect platform backpressure. No automatic
  /// retry of busy errors, chunking, or protocol framing is performed.
  /// A rejected acknowledged write is retried once after security recovery.
  Future<void> write(Uint8List value, BleOutputProperty bleOutputProperty) {
    _ensureSnapshotValid('write');
    return QuickBlueInstrumentation.observeFuture<void>(
      kind: QuickBlueOperationKind.writeCharacteristic,
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
      outputProperty: bleOutputProperty,
      valueSize: value.length,
      action: () => _platform.runWithSecurityRecovery(
        deviceId,
        () => _platform.writeValue(
          deviceId,
          serviceId,
          characteristicId,
          value,
          bleOutputProperty,
        ),
      ),
    );
  }

  /// Writes [value] as sequential chunks of at most [chunkSize] bytes.
  ///
  /// Each chunk is a separate characteristic write. The next chunk is not
  /// submitted until the previous [write] future completes, and processing
  /// stops on the first error. The value is copied before the first write so
  /// later caller mutations cannot change pending chunks. An empty value is
  /// preserved as one empty write.
  ///
  /// [chunkSize] must be greater than zero. Callers must choose a size that
  /// matches the peripheral's application protocol and the active transport.
  /// In particular, this helper does not implement the Bluetooth GATT long
  /// write procedure or add framing that lets a peripheral reassemble chunks.
  /// Completion timing for each chunk follows [bleOutputProperty] and the
  /// platform implementation.
  Future<void> writeInChunks(
    Uint8List value,
    BleOutputProperty bleOutputProperty, {
    required int chunkSize,
  }) async {
    if (chunkSize <= 0) {
      throw ArgumentError.value(
        chunkSize,
        'chunkSize',
        'must be greater than zero',
      );
    }
    final bytes = Uint8List.fromList(value);

    if (bytes.isEmpty) {
      await write(bytes, bleOutputProperty);
      return;
    }

    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      await write(Uint8List.sublistView(bytes, offset, end), bleOutputProperty);
    }
  }
}
