import 'dart:async';

import 'package:meta/meta.dart';

import '../models.dart';
import 'quick_blue_exception.dart';

/// Observes Quick Blue operations without depending on a telemetry SDK.
///
/// Return a per-operation [QuickBlueOperationObservation] to retain any state
/// needed by an adapter, such as an OpenTelemetry span or a `TimelineTask`.
/// Observer failures are ignored so diagnostics cannot change Bluetooth
/// behavior.
abstract interface class QuickBlueObserver {
  /// Called synchronously when an instrumented operation starts.
  ///
  /// Return null when this operation should not be observed.
  QuickBlueOperationObservation? onOperationStarted(
    QuickBlueOperation operation,
  );
}

/// Receives the end of one observed Quick Blue operation.
abstract interface class QuickBlueOperationObservation {
  /// Called at most once when the operation completes, is canceled, or fails.
  void onOperationEnded(QuickBlueOperationEnd operation);
}

/// A stable kind of Quick Blue operation.
enum QuickBlueOperationKind {
  configure,
  isBluetoothAvailable,
  scan,
  connectedDevices,
  connect,
  disconnect,
  bondState,
  waitForBondState,
  pair,
  discoverServices,
  setNotifiable,
  notifications,
  readCharacteristic,
  writeCharacteristic,
  requestMtu,
  openL2cap,
  companionIsSupported,
  companionAssociate,
  companionDisassociate,
  companionAssociations,
  appleAccessorySetupIsSupported,
  appleAccessorySetupShowPicker,
  appleAccessorySetupAccessories,
  appleAccessorySetupRemove,
}

/// How a Quick Blue operation ended.
enum QuickBlueOperationOutcome { completed, cancelled, failed }

/// A numeric result produced by an operation.
///
/// Telemetry adapters decide whether a measurement belongs on a trace, metric,
/// or log and which dimensions are safe to export.
enum QuickBlueOperationMeasurement {
  resultCount,
  valueCount,
  byteCount,
  negotiatedMtu,
}

/// Typed context captured when a Quick Blue operation starts.
///
/// Device identifiers are useful for in-process correlation but can identify
/// physical devices. Adapters should redact or hash them before export. Byte
/// payloads are never included.
final class QuickBlueOperation {
  @internal
  QuickBlueOperation({
    required this.kind,
    required this.startTime,
    this.deviceId,
    this.serviceId,
    this.characteristicId,
    this.scanFilter,
    this.scanOptions,
    this.inputProperty,
    this.outputProperty,
    this.targetBondState,
    this.maintainState,
    this.valueSize,
    this.requestedMtu,
    this.l2capPsm,
    this.associationId,
  });

  /// The API operation being performed.
  final QuickBlueOperationKind kind;

  /// The UTC wall-clock time at which the operation started.
  final DateTime startTime;

  /// The platform-specific device identifier, when the operation has one.
  final String? deviceId;

  /// The GATT service UUID, when the operation targets a characteristic.
  final String? serviceId;

  /// The GATT characteristic UUID, when the operation targets one.
  final String? characteristicId;

  /// The filter used by a managed scan.
  final ScanFilter? scanFilter;

  /// The options used by a managed scan.
  final ScanOptions? scanOptions;

  /// The requested notification or indication mode.
  final BleInputProperty? inputProperty;

  /// The requested characteristic write mode.
  final BleOutputProperty? outputProperty;

  /// The bond state awaited by a wait operation.
  final BluetoothBondState? targetBondState;

  /// Whether platform state restoration was requested during configuration.
  final bool? maintainState;

  /// The size of a value supplied to the operation, without its payload.
  final int? valueSize;

  /// The MTU requested by the client.
  final int? requestedMtu;

  /// The protocol/service multiplexer used to open an L2CAP socket.
  final int? l2capPsm;

  /// The companion-device association targeted by the operation.
  final int? associationId;
}

/// The completion of an observed Quick Blue operation.
final class QuickBlueOperationEnd {
  @internal
  QuickBlueOperationEnd({
    required this.endTime,
    required this.duration,
    required this.outcome,
    Map<QuickBlueOperationMeasurement, num> measurements =
        const <QuickBlueOperationMeasurement, num>{},
    this.error,
    this.stackTrace,
  }) : measurements = Map<QuickBlueOperationMeasurement, num>.unmodifiable(
         measurements,
       );

  /// The UTC wall-clock time at which the operation ended.
  final DateTime endTime;

  /// Monotonic elapsed time between operation start and end.
  final Duration duration;

  /// Whether the operation completed, was canceled, or failed.
  final QuickBlueOperationOutcome outcome;

  /// Aggregate numeric results produced by the operation.
  final Map<QuickBlueOperationMeasurement, num> measurements;

  /// The thrown error when [outcome] is not completed, when available.
  final Object? error;

  /// The error's stack trace, when available.
  final StackTrace? stackTrace;
}

/// Shared instrumentation for Quick Blue and federated platform packages.
///
/// Applications normally configure this through `QuickBlue.observer`.
final class QuickBlueInstrumentation {
  QuickBlueInstrumentation._();

  /// The process-local operation observer.
  static QuickBlueObserver? observer;

  /// Records the lifecycle of an asynchronous [action].
  static Future<T> observeFuture<T>({
    required QuickBlueOperationKind kind,
    required Future<T> Function() action,
    String? deviceId,
    String? serviceId,
    String? characteristicId,
    ScanFilter? scanFilter,
    ScanOptions? scanOptions,
    BleInputProperty? inputProperty,
    BleOutputProperty? outputProperty,
    BluetoothBondState? targetBondState,
    bool? maintainState,
    int? valueSize,
    int? requestedMtu,
    int? l2capPsm,
    int? associationId,
    Map<QuickBlueOperationMeasurement, num> Function(T value)? measurements,
  }) {
    if (observer == null) {
      return action();
    }
    final scope = startOperation(
      kind,
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
      scanFilter: scanFilter,
      scanOptions: scanOptions,
      inputProperty: inputProperty,
      outputProperty: outputProperty,
      targetBondState: targetBondState,
      maintainState: maintainState,
      valueSize: valueSize,
      requestedMtu: requestedMtu,
      l2capPsm: l2capPsm,
      associationId: associationId,
    );
    late final Future<T> future;
    try {
      future = action();
    } catch (error, stackTrace) {
      scope.end(
        outcome: _outcomeForError(error),
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    return observeCompletion(future, scope, measurements: measurements);
  }

  /// Observes [future] without wrapping or replacing it.
  ///
  /// Preserving identity is required by the managed connection cancellation
  /// lifecycle.
  static Future<T> observeCompletion<T>(
    Future<T> future,
    QuickBlueOperationScope scope, {
    Map<QuickBlueOperationMeasurement, num> Function(T value)? measurements,
  }) {
    future
        .then<void>(
          (value) => scope.end(measurements: measurements?.call(value)),
          onError: (Object error, StackTrace stackTrace) {
            scope.end(
              outcome: _outcomeForError(error),
              error: error,
              stackTrace: stackTrace,
            );
          },
        )
        .ignore();
    return future;
  }

  /// Records a stream subscription and its aggregate value measurements.
  static Stream<T> observeStream<T>({
    required QuickBlueOperationKind kind,
    required Stream<T> Function() stream,
    String? deviceId,
    String? serviceId,
    String? characteristicId,
    BleInputProperty? inputProperty,
    int Function(T value)? valueSize,
  }) {
    if (observer == null) {
      return stream();
    }
    return _observeStream(
      kind: kind,
      stream: stream,
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
      inputProperty: inputProperty,
      valueSize: valueSize,
    );
  }

  static Stream<T> _observeStream<T>({
    required QuickBlueOperationKind kind,
    required Stream<T> Function() stream,
    String? deviceId,
    String? serviceId,
    String? characteristicId,
    BleInputProperty? inputProperty,
    int Function(T value)? valueSize,
  }) async* {
    final scope = startOperation(
      kind,
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
      inputProperty: inputProperty,
    );
    var valueCount = 0;
    var totalValueSize = 0;
    var sourceCompleted = false;
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      yield* stream().map((value) {
        valueCount++;
        totalValueSize += valueSize?.call(value) ?? 0;
        return value;
      });
      sourceCompleted = true;
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
      rethrow;
    } finally {
      scope.end(
        outcome: failure != null
            ? _outcomeForError(failure)
            : sourceCompleted
            ? QuickBlueOperationOutcome.completed
            : QuickBlueOperationOutcome.cancelled,
        error: failure,
        stackTrace: failureStackTrace,
        measurements: <QuickBlueOperationMeasurement, num>{
          QuickBlueOperationMeasurement.valueCount: valueCount,
          if (valueSize != null)
            QuickBlueOperationMeasurement.byteCount: totalValueSize,
        },
      );
    }
  }

  /// Starts a manually managed operation.
  static QuickBlueOperationScope startOperation(
    QuickBlueOperationKind kind, {
    String? deviceId,
    String? serviceId,
    String? characteristicId,
    ScanFilter? scanFilter,
    ScanOptions? scanOptions,
    BleInputProperty? inputProperty,
    BleOutputProperty? outputProperty,
    BluetoothBondState? targetBondState,
    bool? maintainState,
    int? valueSize,
    int? requestedMtu,
    int? l2capPsm,
    int? associationId,
  }) {
    final currentObserver = observer;
    if (currentObserver == null) {
      return QuickBlueOperationScope._disabled();
    }

    final stopwatch = Stopwatch()..start();
    QuickBlueOperationObservation? observation;
    try {
      observation = currentObserver.onOperationStarted(
        QuickBlueOperation(
          kind: kind,
          startTime: DateTime.now().toUtc(),
          deviceId: deviceId,
          serviceId: serviceId,
          characteristicId: characteristicId,
          scanFilter: scanFilter,
          scanOptions: scanOptions,
          inputProperty: inputProperty,
          outputProperty: outputProperty,
          targetBondState: targetBondState,
          maintainState: maintainState,
          valueSize: valueSize,
          requestedMtu: requestedMtu,
          l2capPsm: l2capPsm,
          associationId: associationId,
        ),
      );
    } on Object {
      stopwatch.stop();
      return QuickBlueOperationScope._disabled();
    }
    if (observation == null) {
      stopwatch.stop();
      return QuickBlueOperationScope._disabled();
    }
    return QuickBlueOperationScope._(
      observation: observation,
      stopwatch: stopwatch,
    );
  }

  static QuickBlueOperationOutcome _outcomeForError(Object error) {
    return error is QuickBlueException &&
            error.code == QuickBlueErrorCode.cancelled
        ? QuickBlueOperationOutcome.cancelled
        : QuickBlueOperationOutcome.failed;
  }
}

/// A running operation created by [QuickBlueInstrumentation.startOperation].
///
/// Call [end] exactly once. Later calls are ignored.
final class QuickBlueOperationScope {
  QuickBlueOperationScope._disabled() : _observation = null, _stopwatch = null;

  QuickBlueOperationScope._({
    required QuickBlueOperationObservation observation,
    required Stopwatch stopwatch,
  }) : _observation = observation,
       _stopwatch = stopwatch;

  final QuickBlueOperationObservation? _observation;
  final Stopwatch? _stopwatch;
  bool _ended = false;

  /// Ends the operation and reports its typed result to the observer.
  void end({
    QuickBlueOperationOutcome outcome = QuickBlueOperationOutcome.completed,
    Object? error,
    StackTrace? stackTrace,
    Map<QuickBlueOperationMeasurement, num>? measurements,
  }) {
    if (_observation == null || _ended) {
      return;
    }
    _ended = true;
    _stopwatch!.stop();

    try {
      _observation.onOperationEnded(
        QuickBlueOperationEnd(
          endTime: DateTime.now().toUtc(),
          duration: _stopwatch.elapsed,
          outcome: outcome,
          measurements:
              measurements ?? const <QuickBlueOperationMeasurement, num>{},
          error: error,
          stackTrace: stackTrace,
        ),
      );
    } on Object {
      // Diagnostics must never change the behavior of Bluetooth operations.
    }
  }
}
