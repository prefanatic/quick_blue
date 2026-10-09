import 'dart:async';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'android_repair_observation.dart';
import 'messages.g.dart' as messages;

final class AndroidSecurityRecovery {
  AndroidSecurityRecovery({
    required this.stateChanges,
    required this.readState,
    required this.startPairing,
    this.repairChanges =
        const Stream<messages.PlatformRepairObservation>.empty(),
    this.readRepair,
    this.implicitBondStartTimeout = const Duration(milliseconds: 500),
    this.bondCompletionTimeout = const Duration(seconds: 30),
    this.bondStateQueryTimeout = const Duration(seconds: 2),
  });

  final Stream<BluetoothBondStateChange> stateChanges;
  final Future<BluetoothBondState> Function(String deviceId) readState;
  final Future<void> Function(String deviceId) startPairing;
  final Stream<messages.PlatformRepairObservation> repairChanges;
  final Future<messages.PlatformRepairObservation> Function(String deviceId)?
  readRepair;
  final Duration implicitBondStartTimeout;
  final Duration bondCompletionTimeout;
  final Duration bondStateQueryTimeout;

  Future<QuickBlueSecurityRecoveryResult> perform(String deviceId) async {
    final repair = AndroidRepairObservation(deviceId, repairChanges);
    final observation = _AndroidBondStateObservation(
      deviceId: deviceId,
      stateChanges: stateChanges,
      readState: () => readState(deviceId),
      stateQueryTimeout: bondStateQueryTimeout,
      repairStarted: repair.started.future,
    );
    final initialEventSequence = observation.eventSequence;

    try {
      final query = readRepair;
      if (query != null) {
        repair.acceptSnapshot(
          await query(deviceId).timeout(bondStateQueryTimeout),
        );
      }
      if (repair.wasActive) return await repair.result(bondCompletionTimeout);
      final result = await _recoverBond(
        deviceId,
        observation,
        repair,
        initialEventSequence,
      );
      return repair.wasActive
          ? await repair.result(bondCompletionTimeout)
          : result;
    } on Object {
      return QuickBlueSecurityRecoveryResult.userActionRequired;
    } finally {
      await observation.dispose();
      await repair.dispose(bondStateQueryTimeout);
    }
  }

  Future<QuickBlueSecurityRecoveryResult> _recoverBond(
    String deviceId,
    _AndroidBondStateObservation observation,
    AndroidRepairObservation repair,
    int initialEventSequence,
  ) async {
    final initialState = await observation.readCurrentState();
    if (repair.wasActive) {
      return QuickBlueSecurityRecoveryResult.userActionRequired;
    }
    switch (initialState) {
      case BluetoothBondState.bonded:
        return QuickBlueSecurityRecoveryResult.userActionRequired;
      case BluetoothBondState.unknown:
        return QuickBlueSecurityRecoveryResult.unsupported;
      case BluetoothBondState.bonding:
        return await _waitForBondCompletion(
          observation,
          afterEventSequence: initialEventSequence,
        );
      case BluetoothBondState.notBonded:
        break;
    }

    final implicitState = await _waitForBondStart(
      observation,
      afterEventSequence: initialEventSequence,
    );
    if (repair.wasActive) {
      return QuickBlueSecurityRecoveryResult.userActionRequired;
    }
    if (implicitState == BluetoothBondState.bonded) {
      return QuickBlueSecurityRecoveryResult.recovered;
    }
    if (implicitState == BluetoothBondState.bonding) {
      return await _waitForBondCompletion(
        observation,
        afterEventSequence: observation.eventSequence,
      );
    }

    final explicitPairEventSequence = observation.eventSequence;
    await startPairing(deviceId).timeout(bondStateQueryTimeout);
    final explicitState = await _waitForBondStart(
      observation,
      afterEventSequence: explicitPairEventSequence,
    );
    if (explicitState == BluetoothBondState.bonded) {
      return QuickBlueSecurityRecoveryResult.recovered;
    }
    if (explicitState == BluetoothBondState.bonding) {
      return await _waitForBondCompletion(
        observation,
        afterEventSequence: observation.eventSequence,
      );
    }
    return QuickBlueSecurityRecoveryResult.userActionRequired;
  }

  Future<BluetoothBondState?> _waitForBondStart(
    _AndroidBondStateObservation observation, {
    required int afterEventSequence,
  }) {
    return observation.waitForState(
      const <BluetoothBondState>{
        BluetoothBondState.bonding,
        BluetoothBondState.bonded,
      },
      afterEventSequence: afterEventSequence,
      timeout: implicitBondStartTimeout,
    );
  }

  Future<QuickBlueSecurityRecoveryResult> _waitForBondCompletion(
    _AndroidBondStateObservation observation, {
    required int afterEventSequence,
  }) async {
    final state = await observation.waitForState(
      const <BluetoothBondState>{
        BluetoothBondState.bonded,
        BluetoothBondState.notBonded,
      },
      afterEventSequence: afterEventSequence,
      timeout: bondCompletionTimeout,
    );
    return state == BluetoothBondState.bonded
        ? QuickBlueSecurityRecoveryResult.recovered
        : QuickBlueSecurityRecoveryResult.userActionRequired;
  }
}

final class _AndroidBondStateObservation {
  _AndroidBondStateObservation({
    required this.deviceId,
    required Stream<BluetoothBondStateChange> stateChanges,
    required Future<BluetoothBondState> Function() readState,
    required this.stateQueryTimeout,
    required Future<void> repairStarted,
  }) : _readState = readState {
    _subscription = stateChanges
        .where((change) => change.deviceId == deviceId)
        .listen(_handleStateChange, onError: _handleStateError);
    repairStarted.then((_) {
      _repairStarted = true;
      final wait = _pendingWait;
      if (wait != null && !wait.completer.isCompleted) {
        wait.completer.complete(null);
      }
    });
  }

  final String deviceId;
  final Future<BluetoothBondState> Function() _readState;
  final Duration stateQueryTimeout;
  late final StreamSubscription<BluetoothBondStateChange> _subscription;
  _AndroidBondStateWait? _pendingWait;
  BluetoothBondState? _latestEventState;
  int _eventSequence = 0;
  bool _repairStarted = false;

  int get eventSequence => _eventSequence;

  Future<BluetoothBondState> readCurrentState() {
    return _readState().timeout(stateQueryTimeout);
  }

  Future<BluetoothBondState?> waitForState(
    Set<BluetoothBondState> targetStates, {
    required int afterEventSequence,
    required Duration timeout,
  }) async {
    if (_repairStarted) return null;
    if (_pendingWait != null) {
      throw StateError('An Android bond-state wait is already active.');
    }

    final wait = _AndroidBondStateWait(
      targetStates: targetStates,
      afterEventSequence: afterEventSequence,
    );
    _pendingWait = wait;
    _completeFromLatestEvent(wait);

    try {
      if (!wait.completer.isCompleted) {
        final currentState = await readCurrentState();
        if (!wait.completer.isCompleted &&
            targetStates.contains(currentState)) {
          wait.completer.complete(currentState);
        }
      }
      if (!wait.completer.isCompleted) {
        wait.timer = Timer(timeout, () async {
          await _completeAfterFinalSnapshot(wait);
        });
      }
      return await wait.completer.future;
    } finally {
      wait.timer?.cancel();
      if (identical(_pendingWait, wait)) {
        _pendingWait = null;
      }
    }
  }

  void _handleStateChange(BluetoothBondStateChange change) {
    _eventSequence += 1;
    _latestEventState = change.state;
    final wait = _pendingWait;
    if (wait != null) {
      _completeFromLatestEvent(wait);
    }
  }

  void _handleStateError(Object error, StackTrace stackTrace) {
    final wait = _pendingWait;
    if (wait != null && !wait.completer.isCompleted) {
      wait.completer.completeError(error, stackTrace);
    }
  }

  void _completeFromLatestEvent(_AndroidBondStateWait wait) {
    final state = _latestEventState;
    if (!wait.completer.isCompleted &&
        _eventSequence > wait.afterEventSequence &&
        state != null &&
        wait.targetStates.contains(state)) {
      wait.completer.complete(state);
    }
  }

  Future<void> _completeAfterFinalSnapshot(_AndroidBondStateWait wait) async {
    try {
      final state = await readCurrentState();
      if (!identical(_pendingWait, wait) || wait.completer.isCompleted) {
        return;
      }
      wait.completer.complete(wait.targetStates.contains(state) ? state : null);
    } on Object catch (error, stackTrace) {
      if (identical(_pendingWait, wait) && !wait.completer.isCompleted) {
        wait.completer.completeError(error, stackTrace);
      }
    }
  }

  Future<void> dispose() async {
    _pendingWait?.timer?.cancel();
    try {
      await _subscription.cancel().timeout(stateQueryTimeout);
    } on Object {
      // The bounded recovery must not replace the original security failure.
    }
  }
}

final class _AndroidBondStateWait {
  _AndroidBondStateWait({
    required this.targetStates,
    required this.afterEventSequence,
  });

  final Set<BluetoothBondState> targetStates;
  final int afterEventSequence;
  final Completer<BluetoothBondState?> completer =
      Completer<BluetoothBondState?>();
  Timer? timer;
}
