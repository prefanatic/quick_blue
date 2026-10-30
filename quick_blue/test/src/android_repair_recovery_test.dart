import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/src/android_security_recovery.dart';
import 'package:quick_blue/src/messages.g.dart' as messages;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  late StreamController<messages.PlatformRepairObservation> repairs;
  late StreamController<BluetoothBondStateChange> bonds;
  late messages.PlatformRepairObservation snapshot;
  late BluetoothBondState bond;
  late int pairCalls;
  late int cancelCalls;

  messages.PlatformRepairObservation event(
    messages.PlatformRepairState state, {
    int generation = 2,
    String device = 'a',
  }) => messages.PlatformRepairObservation(
    deviceId: device,
    generation: generation,
    state: state,
  );

  setUp(() {
    cancelCalls = 0;
    repairs = StreamController<messages.PlatformRepairObservation>.broadcast(
      onCancel: () => cancelCalls++,
    );
    bonds = StreamController<BluetoothBondStateChange>.broadcast();
    snapshot = event(messages.PlatformRepairState.inProgress);
    bond = BluetoothBondState.bonded;
    pairCalls = 0;
  });
  tearDown(() async {
    await repairs.close();
    await bonds.close();
  });

  AndroidSecurityRecovery recovery({
    Future<messages.PlatformRepairObservation> Function(String)? query,
    Duration completion = const Duration(milliseconds: 30),
  }) => AndroidSecurityRecovery(
    stateChanges: bonds.stream,
    readState: (_) async => bond,
    startPairing: (_) async {
      pairCalls++;
    },
    repairChanges: repairs.stream,
    readRepair: query ?? (_) async => snapshot,
    implicitBondStartTimeout: const Duration(milliseconds: 5),
    bondStateQueryTimeout: const Duration(milliseconds: 20),
    bondCompletionTimeout: completion,
  );

  test(
    'retained bonded waits for repair proof with no extra bond request',
    () async {
      var completed = false;
      final result = recovery().perform('a').then((value) {
        completed = true;
        return value;
      });
      await pumpEventQueue();
      bonds.add(
        BluetoothBondStateChange(
          deviceId: 'a',
          state: BluetoothBondState.bonded,
          previousState: BluetoothBondState.bonded,
        ),
      );
      await pumpEventQueue();
      expect(completed, isFalse);
      repairs.add(event(messages.PlatformRepairState.succeeded));
      expect(await result, QuickBlueSecurityRecoveryResult.recovered);
      expect(pairCalls, 0);
      expect(cancelCalls, 1);
    },
  );

  test('rejection KEY_MISSING cannot report recovery', () async {
    final result = recovery().perform('a');
    await pumpEventQueue();
    repairs.add(event(messages.PlatformRepairState.failed));
    repairs.add(event(messages.PlatformRepairState.succeeded));
    expect(await result, QuickBlueSecurityRecoveryResult.userActionRequired);
    expect(pairCalls, 0);
  });

  test('cached success alone is not proof for a new operation', () async {
    snapshot = event(messages.PlatformRepairState.succeeded);
    expect(
      await recovery().perform('a'),
      QuickBlueSecurityRecoveryResult.userActionRequired,
    );
    expect(pairCalls, 0);
  });

  test('failure snapshot remains conservative even when unbonded', () async {
    snapshot = event(messages.PlatformRepairState.failed);
    bond = BluetoothBondState.notBonded;
    expect(
      await recovery().perform('a'),
      QuickBlueSecurityRecoveryResult.userActionRequired,
    );
    expect(pairCalls, 0);
  });

  test('missing context retains older bonded behavior', () async {
    snapshot = event(messages.PlatformRepairState.unknown);
    expect(
      await recovery().perform('a'),
      QuickBlueSecurityRecoveryResult.userActionRequired,
    );
    expect(pairCalls, 0);
  });

  test(
    'repair stream error before query completion prevents pairing',
    () async {
      bond = BluetoothBondState.notBonded;
      final query = Completer<messages.PlatformRepairObservation>();
      final result = recovery(query: (_) => query.future).perform('a');
      repairs.addError(StateError('stream failed'));
      await pumpEventQueue();
      query.complete(event(messages.PlatformRepairState.unknown));
      expect(await result, QuickBlueSecurityRecoveryResult.userActionRequired);
      expect(pairCalls, 0);
    },
  );

  test(
    'repair query failure never guesses recovery or starts pairing',
    () async {
      expect(
        await recovery(
          query: (_) async => throw StateError('query failed'),
        ).perform('a'),
        QuickBlueSecurityRecoveryResult.userActionRequired,
      );
      expect(pairCalls, 0);
      expect(cancelCalls, 1);
    },
  );

  test('repair query never returning is bounded', () async {
    expect(
      await recovery(
        query: (_) => Completer<messages.PlatformRepairObservation>().future,
      ).perform('a'),
      QuickBlueSecurityRecoveryResult.userActionRequired,
    );
    expect(pairCalls, 0);
  });

  test('stream error during repair and engine detach end wait', () async {
    final result = recovery().perform('a');
    await pumpEventQueue();
    repairs.addError(StateError('channel failed'));
    expect(await result, QuickBlueSecurityRecoveryResult.userActionRequired);
    expect(pairCalls, 0);
  });

  test(
    'engine detach stream closure does not leave recovery pending',
    () async {
      final result = recovery().perform('a');
      await pumpEventQueue();
      await repairs.close();
      expect(await result, QuickBlueSecurityRecoveryResult.userActionRequired);
      expect(pairCalls, 0);
    },
  );

  test('late stale terminal event cannot settle a new generation', () async {
    snapshot = event(messages.PlatformRepairState.inProgress, generation: 4);
    var completed = false;
    final result = recovery().perform('a').then((value) {
      completed = true;
      return value;
    });
    await pumpEventQueue();
    repairs.add(event(messages.PlatformRepairState.succeeded, generation: 2));
    await pumpEventQueue();
    expect(completed, isFalse);
    repairs.add(event(messages.PlatformRepairState.succeeded, generation: 4));
    expect(await result, QuickBlueSecurityRecoveryResult.recovered);
  });

  test('disconnect invalidates repair before reconnect success', () async {
    final result = recovery().perform('a');
    await pumpEventQueue();
    repairs.add(event(messages.PlatformRepairState.unknown, generation: 3));
    repairs.add(event(messages.PlatformRepairState.succeeded, generation: 4));
    expect(await result, QuickBlueSecurityRecoveryResult.userActionRequired);
  });

  test('two simultaneous devices remain isolated', () async {
    final first = recovery().perform('a');
    final second = recovery(
      query: (_) async =>
          event(messages.PlatformRepairState.inProgress, device: 'b'),
    ).perform('b');
    await pumpEventQueue();
    repairs.add(event(messages.PlatformRepairState.failed, device: 'b'));
    repairs.add(event(messages.PlatformRepairState.succeeded));
    expect(await first, QuickBlueSecurityRecoveryResult.recovered);
    expect(await second, QuickBlueSecurityRecoveryResult.userActionRequired);
    expect(pairCalls, 0);
  });

  test('new stream evidence wins over a stale query reply', () async {
    final query = Completer<messages.PlatformRepairObservation>();
    final result = recovery(query: (_) => query.future).perform('a');
    repairs.add(event(messages.PlatformRepairState.inProgress, generation: 4));
    repairs.add(event(messages.PlatformRepairState.succeeded, generation: 4));
    await pumpEventQueue();
    query.complete(event(messages.PlatformRepairState.unknown, generation: 1));
    expect(await result, QuickBlueSecurityRecoveryResult.recovered);
    expect(pairCalls, 0);
  });

  test(
    'repair starts during legacy implicit observation and prevents explicit pairing',
    () async {
      snapshot = event(messages.PlatformRepairState.unknown, generation: 1);
      bond = BluetoothBondState.notBonded;
      final result = recovery().perform('a');
      await pumpEventQueue();
      repairs.add(event(messages.PlatformRepairState.inProgress));
      await pumpEventQueue();
      repairs.add(event(messages.PlatformRepairState.succeeded));
      expect(await result, QuickBlueSecurityRecoveryResult.recovered);
      expect(pairCalls, 0);
    },
  );

  testWidgets(
    'ignored or delayed dialog beyond 30 seconds is not definitive OS failure',
    (tester) async {
      QuickBlueSecurityRecoveryResult? result;
      final pending = recovery(completion: const Duration(seconds: 30))
          .perform('a')
          .then((value) {
            result = value;
          });
      await tester.pump();
      await tester.pump(const Duration(seconds: 29));
      expect(result, isNull);
      await tester.pump(const Duration(seconds: 2));
      await pending;
      expect(result, QuickBlueSecurityRecoveryResult.userActionRequired);
      expect(pairCalls, 0);
      expect(snapshot.state, messages.PlatformRepairState.inProgress);
      repairs.add(event(messages.PlatformRepairState.succeeded));
      await tester.pump();
      expect(result, QuickBlueSecurityRecoveryResult.userActionRequired);
      expect(cancelCalls, 1);
    },
  );
}
