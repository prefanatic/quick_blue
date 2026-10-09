import 'dart:async';

/// A one-shot fake native call: await [entered] before teardown, then [release]
/// explicitly. No sleeps or timing assumptions determine the release order.
class FutureGate {
  final _entered = Completer<void>();
  final _released = Completer<void>();

  Future<void> get entered => _entered.future;

  Future<void> suspend() async {
    _entered.complete();
    await _released.future;
  }

  void release() => _released.complete();
}
