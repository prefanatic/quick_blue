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

/// Optionally receives payload-free characteristic value measurements.
///
/// An operation observer can also implement this interface when it needs
/// timely metrics for long-lived notification subscriptions. Quick Blue calls
/// this once for every characteristic value received from the platform,
/// including values delivered through the explicit `valueStream` /
/// `setNotifiable` lifecycle.
abstract interface class QuickBlueValueObserver {
  /// Called synchronously without exposing the characteristic payload.
  void onValueReceived(QuickBlueValueObservation observation);
}

/// Receives the end of one observed Quick Blue operation.
abstract interface class QuickBlueOperationObservation {
  /// Called at most once when the operation completes, is stopped or
  /// cancelled, or fails.
  void onOperationEnded(QuickBlueOperationEnd operation);
}

/// Dispatches observations to multiple independent observers.
///
/// A failure in one child observer does not prevent the remaining observers
/// from receiving the event.
final class CompositeQuickBlueObserver
    implements QuickBlueObserver, QuickBlueValueObserver {
  /// Creates an observer that fans out to [observers] in iteration order.
  CompositeQuickBlueObserver(Iterable<QuickBlueObserver> observers)
    : observers = List<QuickBlueObserver>.unmodifiable(observers);

  /// The observers that receive each operation.
  final List<QuickBlueObserver> observers;

  @override
  QuickBlueOperationObservation? onOperationStarted(
    QuickBlueOperation operation,
  ) {
    final observations = <QuickBlueOperationObservation>[];
    for (final observer in observers) {
      try {
        final observation = observer.onOperationStarted(operation);
        if (observation != null) {
          observations.add(observation);
        }
      } on Object {
        // Diagnostics must never change the behavior of Bluetooth operations.
      }
    }
    return observations.isEmpty
        ? null
        : _CompositeQuickBlueOperationObservation(observations);
  }

  @override
  void onValueReceived(QuickBlueValueObservation observation) {
    for (final observer in observers.whereType<QuickBlueValueObserver>()) {
      try {
        observer.onValueReceived(observation);
      } on Object {
        // Diagnostics must never change the behavior of Bluetooth operations.
      }
    }
  }
}

final class _CompositeQuickBlueOperationObservation
    implements QuickBlueOperationObservation {
  _CompositeQuickBlueOperationObservation(this.observations);

  final List<QuickBlueOperationObservation> observations;

  @override
  void onOperationEnded(QuickBlueOperationEnd operation) {
    for (final observation in observations) {
      try {
        observation.onOperationEnded(operation);
      } on Object {
        // Keep dispatching to the remaining observers.
      }
    }
  }
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
enum QuickBlueOperationOutcome {
  /// The operation or source stream completed normally.
  completed,

  /// A stream subscriber stopped consuming an otherwise healthy stream.
  stopped,

  /// The operation was superseded or explicitly cancelled by Quick Blue.
  cancelled,

  /// The operation failed.
  failed,
}

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
/// physical devices. Adapters should redact or hash them before export.
/// Characteristic values and advertisement results are never included, but a
/// [scanFilter] can contain service/manufacturer data prefixes and must also be
/// treated as sensitive context.
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
    List<String>? serviceUuids,
  }) : serviceUuids = serviceUuids == null
           ? null
           : List<String>.unmodifiable(serviceUuids);

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
  ///
  /// This can contain service/manufacturer data prefixes. Do not stringify or
  /// export it without applying the application's privacy policy.
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

  /// Service UUIDs supplied to a connected-device lookup.
  final List<String>? serviceUuids;
}

/// Export-safe metadata derived from a failed Quick Blue operation.
///
/// This deliberately excludes messages, device identifiers, arbitrary native
/// details, and stack traces. Use [QuickBlueOperationEnd.error] only for local
/// diagnostics after applying the application's privacy policy.
final class QuickBlueOperationFailure {
  @internal
  const QuickBlueOperationFailure({
    required this.errorType,
    this.code,
    this.nativeDomain,
    this.nativeStatus,
    this.securityReason,
    this.securityRecoveryResult,
  });

  /// The Dart error type without its message or fields.
  final String errorType;

  /// Portable Quick Blue error category, when available.
  final QuickBlueErrorCode? code;

  /// Native error domain, when exposed by a structured Quick Blue error.
  final String? nativeDomain;

  /// Native GATT status or platform error code, when available.
  final int? nativeStatus;

  /// Portable security failure category, when available.
  final QuickBlueSecurityErrorReason? securityReason;

  /// Result of automatic security recovery, when available.
  final QuickBlueSecurityRecoveryResult? securityRecoveryResult;
}

/// Payload-free metadata for one characteristic value received by Quick Blue.
final class QuickBlueValueObservation {
  @internal
  const QuickBlueValueObservation({
    required this.time,
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
    required this.valueSize,
  });

  /// UTC wall-clock time at which Quick Blue received the value.
  final DateTime time;

  /// Platform-specific device identifier.
  ///
  /// This can identify a physical device and must be redacted or hashed before
  /// export.
  final String deviceId;

  /// GATT service UUID, or an empty string for a legacy unscoped event.
  final String serviceId;

  /// GATT characteristic UUID.
  final String characteristicId;

  /// Number of bytes in the value. The payload itself is never exposed.
  final int valueSize;
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
       ),
       failure = _safeFailure(error);

  /// The UTC wall-clock time at which the operation ended.
  final DateTime endTime;

  /// Monotonic elapsed time between operation start and end.
  final Duration duration;

  /// Whether the operation completed, was canceled, or failed.
  final QuickBlueOperationOutcome outcome;

  /// Aggregate numeric results produced by the operation.
  final Map<QuickBlueOperationMeasurement, num> measurements;

  /// Export-safe structured metadata for [error], when an error was reported.
  final QuickBlueOperationFailure? failure;

  /// The raw thrown error, when available.
  ///
  /// This is sensitive diagnostic data. Its message or string representation
  /// can contain device identifiers and arbitrary native details. Never export
  /// it without applying the application's privacy policy; prefer [failure].
  final Object? error;

  /// The raw error stack trace, when available.
  ///
  /// Stack traces can contain local paths and other sensitive diagnostics.
  final StackTrace? stackTrace;
}

QuickBlueOperationFailure? _safeFailure(Object? error) {
  if (error == null) {
    return null;
  }
  if (error is QuickBlueSecurityException) {
    return QuickBlueOperationFailure(
      errorType: error.runtimeType.toString(),
      code: error.code,
      nativeDomain: error.nativeDomain,
      nativeStatus: error.nativeCode,
      securityReason: error.reason,
      securityRecoveryResult: error.recoveryResult,
    );
  }
  if (error is QuickBlueGattException) {
    return QuickBlueOperationFailure(
      errorType: error.runtimeType.toString(),
      code: error.code,
      nativeStatus: error.status,
    );
  }
  if (error is QuickBlueException) {
    return QuickBlueOperationFailure(
      errorType: error.runtimeType.toString(),
      code: error.code,
    );
  }
  return QuickBlueOperationFailure(errorType: error.runtimeType.toString());
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
    List<String>? serviceUuids,
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
      serviceUuids: serviceUuids,
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

  /// Observes [future] while preserving its value or original failure.
  ///
  /// When observation is enabled, the returned Future forwards failures rather
  /// than consuming them so uncaught asynchronous errors remain observable.
  static Future<T> observeCompletion<T>(
    Future<T> future,
    QuickBlueOperationScope scope, {
    Map<QuickBlueOperationMeasurement, num> Function(T value)? measurements,
  }) {
    if (!scope._isEnabled) {
      return future;
    }
    return future.then<T>(
      (value) {
        Map<QuickBlueOperationMeasurement, num>? resultMeasurements;
        try {
          resultMeasurements = measurements?.call(value);
        } on Object {
          // Diagnostics must never change the operation's result.
        }
        scope.end(measurements: resultMeasurements);
        return value;
      },
      onError: (Object error, StackTrace stackTrace) {
        scope.end(
          outcome: _outcomeForError(error),
          error: error,
          stackTrace: stackTrace,
        );
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
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
    return _ObservedStream<T>(
      kind: kind,
      source: stream(),
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
      inputProperty: inputProperty,
      valueSize: valueSize,
    );
  }

  /// Reports a payload-free characteristic value measurement.
  static void recordCharacteristicValue({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required int valueSize,
  }) {
    final currentObserver = observer;
    if (currentObserver is! QuickBlueValueObserver) {
      return;
    }
    final valueObserver = currentObserver as QuickBlueValueObserver;
    try {
      valueObserver.onValueReceived(
        QuickBlueValueObservation(
          time: DateTime.now().toUtc(),
          deviceId: deviceId,
          serviceId: serviceId,
          characteristicId: characteristicId,
          valueSize: valueSize,
        ),
      );
    } on Object {
      // Diagnostics must never change characteristic value delivery.
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
    List<String>? serviceUuids,
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
          serviceUuids: serviceUuids,
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

  bool get _isEnabled => _observation != null;

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

final class _ObservedStream<T> extends Stream<T> {
  _ObservedStream({
    required this.kind,
    required this.source,
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
    required this.inputProperty,
    required this.valueSize,
  });

  final QuickBlueOperationKind kind;
  final Stream<T> source;
  final String? deviceId;
  final String? serviceId;
  final String? characteristicId;
  final BleInputProperty? inputProperty;
  final int Function(T value)? valueSize;

  @override
  bool get isBroadcast => source.isBroadcast;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final scope = QuickBlueInstrumentation.startOperation(
      kind,
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
      inputProperty: inputProperty,
    );
    var valueCount = 0;
    var totalValueSize = 0;
    Object? failure;
    StackTrace? failureStackTrace;

    Map<QuickBlueOperationMeasurement, num> measurements() =>
        <QuickBlueOperationMeasurement, num>{
          QuickBlueOperationMeasurement.valueCount: valueCount,
          if (valueSize != null)
            QuickBlueOperationMeasurement.byteCount: totalValueSize,
        };

    void end({required QuickBlueOperationOutcome outcome}) {
      scope.end(
        outcome: outcome,
        error: failure,
        stackTrace: failureStackTrace,
        measurements: measurements(),
      );
    }

    final transformed = source.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleData: (value, sink) {
          valueCount++;
          try {
            totalValueSize += valueSize?.call(value) ?? 0;
          } on Object {
            // Diagnostics must never change stream delivery.
          }
          sink.add(value);
        },
        handleError: (error, stackTrace, sink) {
          failure ??= error;
          failureStackTrace ??= stackTrace;
          if (cancelOnError ?? false) {
            end(outcome: QuickBlueInstrumentation._outcomeForError(error));
          }
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          end(
            outcome: failure == null
                ? QuickBlueOperationOutcome.completed
                : QuickBlueInstrumentation._outcomeForError(failure!),
          );
          sink.close();
        },
      ),
    );

    try {
      final subscription = transformed.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
      return _ObservedStreamSubscription<T>(
        subscription,
        onCancel: () => end(
          outcome: failure == null
              ? QuickBlueOperationOutcome.stopped
              : QuickBlueInstrumentation._outcomeForError(failure!),
        ),
        onCancelError: (error, stackTrace) {
          failure = error;
          failureStackTrace = stackTrace;
          end(outcome: QuickBlueInstrumentation._outcomeForError(error));
        },
      );
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
      end(outcome: QuickBlueInstrumentation._outcomeForError(error));
      rethrow;
    }
  }
}

final class _ObservedStreamSubscription<T> implements StreamSubscription<T> {
  _ObservedStreamSubscription(
    this._subscription, {
    required this.onCancel,
    required this.onCancelError,
  });

  final StreamSubscription<T> _subscription;
  final void Function() onCancel;
  final void Function(Object error, StackTrace stackTrace) onCancelError;

  @override
  Future<void> cancel() {
    return _subscription.cancel().then<void>(
      (_) {
        onCancel();
      },
      onError: (Object error, StackTrace stackTrace) {
        onCancelError(error, stackTrace);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  @override
  void onData(void Function(T data)? handleData) {
    _subscription.onData(handleData);
  }

  @override
  void onError(Function? handleError) {
    _subscription.onError(handleError);
  }

  @override
  void onDone(void Function()? handleDone) {
    _subscription.onDone(handleDone);
  }

  @override
  void pause([Future<void>? resumeSignal]) {
    _subscription.pause(resumeSignal);
  }

  @override
  void resume() {
    _subscription.resume();
  }

  @override
  bool get isPaused => _subscription.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    return _subscription.asFuture<E>(futureValue);
  }
}
