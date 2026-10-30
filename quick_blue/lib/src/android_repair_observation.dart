import 'dart:async';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'messages.g.dart' as messages;

/// One recovery attempt observes one native repair generation. A cached success
/// from an earlier operation is not evidence that this operation was repaired.
final class AndroidRepairObservation {
  AndroidRepairObservation(
    this.deviceId,
    Stream<messages.PlatformRepairObservation> changes,
  ) {
    _subscription = changes
        .where((event) => event.deviceId == deviceId)
        .listen(
          _accept,
          onError: (Object error, StackTrace stackTrace) => _unavailable(),
          onDone: () {
            if (wasActive) _unavailable();
          },
        );
  }

  final String deviceId;
  late final StreamSubscription<messages.PlatformRepairObservation>
  _subscription;
  final started = Completer<void>();
  final _terminal = Completer<messages.PlatformRepairState>();
  int _generation = -1;
  int? _activeGeneration;
  bool _receivedEvent = false;

  bool get wasActive => started.isCompleted;

  void acceptSnapshot(messages.PlatformRepairObservation snapshot) {
    // A query can complete after a newer stream event. Never overwrite it.
    if (!_receivedEvent && snapshot.deviceId == deviceId) _accept(snapshot);
  }

  void _accept(messages.PlatformRepairObservation event) {
    _receivedEvent = true;
    if (event.generation < _generation) return;
    _generation = event.generation;
    if (_terminal.isCompleted) return;
    if (_activeGeneration != null && event.generation != _activeGeneration) {
      _unavailable();
      return;
    }
    switch (event.state) {
      case messages.PlatformRepairState.inProgress:
        _activeGeneration = event.generation;
        if (!started.isCompleted) started.complete();
      case messages.PlatformRepairState.failed:
        _unavailable();
      case messages.PlatformRepairState.succeeded:
        if (_activeGeneration == event.generation) {
          _terminal.complete(event.state);
        }
      case messages.PlatformRepairState.unknown:
        if (wasActive) _unavailable();
    }
  }

  void _unavailable() {
    if (!started.isCompleted) started.complete();
    if (!_terminal.isCompleted) {
      _terminal.complete(messages.PlatformRepairState.unknown);
    }
  }

  Future<QuickBlueSecurityRecoveryResult> result(Duration timeout) async {
    final state = await _terminal.future.timeout(
      timeout,
      onTimeout: () => messages.PlatformRepairState.unknown,
    );
    return state == messages.PlatformRepairState.succeeded
        ? QuickBlueSecurityRecoveryResult.recovered
        : QuickBlueSecurityRecoveryResult.userActionRequired;
  }

  Future<void> dispose(Duration timeout) async {
    try {
      await _subscription.cancel().timeout(timeout);
    } on Object {
      // Cleanup cannot replace the original security failure or hang recovery.
    }
  }
}
