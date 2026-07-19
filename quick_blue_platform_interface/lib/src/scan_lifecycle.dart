import 'dart:async';

import 'package:meta/meta.dart';

import '../models.dart';
import 'observability.dart';
import 'quick_blue_exception.dart';
import 'scan_filter.dart';

@internal
class ScanLifecycleCoordinator {
  ScanLifecycleCoordinator({
    required this.startScan,
    required this.stopScan,
    required this.scanResultStream,
  });

  final Future<void> Function({
    required ScanFilter scanFilter,
    required ScanOptions scanOptions,
  })
  startScan;
  final Future<void> Function() stopScan;
  final Stream<BlueScanResult> Function() scanResultStream;

  _ScanConfiguration? _activeConfiguration;
  var _activeListeners = 0;
  var _started = false;
  Future<void> _lifecycle = Future<void>.value();

  Stream<BlueScanResult> results({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) async* {
    final configuration = _ScanConfiguration(
      scanFilter: _copyScanFilter(scanFilter),
      scanOptions: _copyScanOptions(scanOptions),
    );
    final observation = QuickBlueInstrumentation.startOperation(
      QuickBlueOperationKind.scan,
      scanFilter: configuration.scanFilter,
      scanOptions: configuration.scanOptions,
    );
    var resultCount = 0;
    var sourceCompleted = false;
    Object? failure;
    StackTrace? failureStackTrace;

    try {
      await _acquire(configuration);
      try {
        final seenDeviceIds = <String>{};
        yield* scanResultStream()
            .where(
              (result) =>
                  _matchesConfiguration(result, configuration, seenDeviceIds),
            )
            .map((result) {
              resultCount++;
              return result;
            });
        sourceCompleted = true;
      } finally {
        await _release();
      }
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
      rethrow;
    } finally {
      observation.end(
        outcome: failure != null
            ? failure is QuickBlueException &&
                      failure.code == QuickBlueErrorCode.cancelled
                  ? QuickBlueOperationOutcome.cancelled
                  : QuickBlueOperationOutcome.failed
            : sourceCompleted
            ? QuickBlueOperationOutcome.completed
            : QuickBlueOperationOutcome.stopped,
        error: failure,
        stackTrace: failureStackTrace,
        measurements: <QuickBlueOperationMeasurement, num>{
          QuickBlueOperationMeasurement.resultCount: resultCount,
        },
      );
    }
  }

  bool _matchesConfiguration(
    BlueScanResult result,
    _ScanConfiguration configuration,
    Set<String> seenDeviceIds,
  ) {
    if (!matchesServiceDataFilter(
      configuration.scanFilter.serviceData,
      result.serviceData,
    )) {
      return false;
    }

    final rssi = configuration.scanFilter.rssi;
    if (rssi != null && result.rssi < rssi) {
      return false;
    }

    if (configuration.scanOptions.allowDuplicates == false &&
        !seenDeviceIds.add(result.deviceId)) {
      return false;
    }

    return true;
  }

  Future<void> _acquire(_ScanConfiguration configuration) {
    return _queue(() async {
      final activeConfiguration = _activeConfiguration;
      if (_activeListeners == 0) {
        _activeConfiguration = configuration;
        try {
          await startScan(
            scanFilter: configuration.scanFilter,
            scanOptions: configuration.scanOptions,
          );
          _started = true;
        } catch (_) {
          _activeConfiguration = null;
          rethrow;
        }
      } else if (activeConfiguration == null ||
          activeConfiguration != configuration) {
        throw QuickBlueException(
          code: QuickBlueErrorCode.invalidState,
          operation: 'scanResults',
          message:
              'Cannot start scanning with a different scan configuration while '
              'another scanResults stream is active.',
        );
      }

      _activeListeners++;
    });
  }

  Future<void> _release() {
    return _queue(() async {
      if (_activeListeners == 0) {
        return;
      }

      _activeListeners--;
      if (_activeListeners != 0) {
        return;
      }

      _activeConfiguration = null;
      if (_started) {
        _started = false;
        await stopScan();
      }
    });
  }

  Future<void> _queue(Future<void> Function() action) {
    final next = _lifecycle.then((_) => action());
    _lifecycle = next.catchError((Object _) {});
    return next;
  }

  ScanFilter _copyScanFilter(ScanFilter scanFilter) {
    return ScanFilter(
      serviceUuids: scanFilter.serviceUuids,
      serviceData: scanFilter.serviceData,
      manufacturerData: scanFilter.manufacturerData,
      rssi: scanFilter.rssi,
    );
  }

  ScanOptions _copyScanOptions(ScanOptions scanOptions) {
    return ScanOptions(
      allowDuplicates: scanOptions.allowDuplicates,
      scanMode: scanOptions.scanMode,
      android: scanOptions.android,
      darwin: DarwinScanOptions(
        allowDuplicates: scanOptions.darwin.allowDuplicates,
        solicitedServiceUuids: scanOptions.darwin.solicitedServiceUuids,
      ),
      linux: scanOptions.linux,
      windows: scanOptions.windows,
    );
  }
}

class _ScanConfiguration {
  const _ScanConfiguration({
    required this.scanFilter,
    required this.scanOptions,
  });

  final ScanFilter scanFilter;
  final ScanOptions scanOptions;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _ScanConfiguration &&
            other.scanFilter == scanFilter &&
            other.scanOptions == scanOptions;
  }

  @override
  int get hashCode => Object.hash(scanFilter, scanOptions);
}
