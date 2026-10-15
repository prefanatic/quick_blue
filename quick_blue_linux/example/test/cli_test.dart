import 'dart:async';

import 'package:quick_blue_linux_cli/cli.dart';
import 'package:quick_blue_linux_cli/fake_runtime.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  test('interrupted long interval cancels its timer', () async {
    late Timer timer;
    await runZoned(
      () async {
        await waitInterval(
          3600,
          Future<void>.value(),
          Completer<void>().future,
        );
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          timer = parent.createTimer(zone, duration, callback);
          return timer;
        },
      ),
    );
    expect(timer.isActive, isFalse);
  });
  test(
    'notification stop cancels before disconnect without implicit pair/write',
    () async {
      final fake = FakeRuntime();
      final stop = Completer<void>();
      final args = flowArgs.take(10).toList()
        ..addAll(['--notify-seconds', '3600']);
      await runCli(
        args,
        createRuntime: fake.runtime,
        stop: stop.future,
        output: (line) {
          if (line.startsWith('notify ') && !stop.isCompleted) stop.complete();
        },
      );
      expect(fake.calls, [
        'scan',
        'stopScan',
        'connect $deviceId',
        'discover $deviceId',
        'notify notification $deviceId',
        'notify disabled $deviceId',
        'disconnect $deviceId',
        'close',
      ]);
    },
  );
  test(
    'selected discover-only workflow performs no pairing or attribute IO',
    () async {
      final fake = FakeRuntime();
      await runCli(
        flowArgs.take(8).toList(),
        output: (_) {},
        createRuntime: fake.runtime,
      );
      expect(fake.calls, [
        'scan',
        'stopScan',
        'connect $deviceId',
        'discover $deviceId',
        'disconnect $deviceId',
        'close',
      ]);
    },
  );
  test('compiled-flow source exercises public sequence', () async {
    await fakeFlow((_) {});
  });
  test('help and invalid inputs never initialize a platform', () async {
    CliRuntime forbidden(String? _) => throw StateError('must not initialize');
    await runCli(['--help'], output: (_) {}, createRuntime: forbidden);
    for (final args in [
      <String>[],
      ['--write-hex', 'zz'],
      [...flowArgs, '--pair'],
      ['--adapter', adapterId, '--service', 'invalid'],
      ['--adapter', adapterId, '--service', serviceId, '--read'],
    ]) {
      await expectLater(
        runCli(args, output: (_) {}, createRuntime: forbidden),
        throwsFormatException,
      );
    }
  });
  test('scan only never connects, pairs, or writes', () async {
    final fake = FakeRuntime();
    await runCli(
      flowArgs.take(6).toList(),
      output: (_) {},
      createRuntime: fake.runtime,
    );
    expect(fake.calls, ['scan', 'stopScan', 'close']);
  });
  test('device must appear in current filtered scan', () async {
    final fake = FakeRuntime();
    final args = flowArgs.toList();
    args[7] = '02:00:00:00:00:99';
    await expectLater(
      runCli(args, output: (_) {}, createRuntime: fake.runtime),
      throwsStateError,
    );
    expect(fake.calls, ['scan', 'stopScan', 'close']);
  });
  test('scan error remains observable and closes runtime', () async {
    final failure = StateError('scan');
    final fake = FakeRuntime()..scanError = failure;
    await expectLater(
      runCli(flowArgs, output: (_) {}, createRuntime: fake.runtime),
      throwsA(same(failure)),
    );
    expect(fake.calls, ['scan', 'stopScan', 'close']);
  });
  for (final stage in ['pair', 'read', 'notify']) {
    test(
      '$stage error stays observable with cleanup and no hidden pairing',
      () async {
        const failure = QuickBlueSecurityException(
          operation: 'synthetic',
          nativeDomain: 'synthetic',
          nativeCode: 5,
          reason: QuickBlueSecurityErrorReason.insufficientAuthentication,
          message: 'operator action needed',
        );
        final fake = FakeRuntime();
        if (stage == 'pair') fake.pairError = failure;
        if (stage == 'read') fake.readError = failure;
        if (stage == 'notify') fake.notifyError = failure;
        final args = flowArgs.toList();
        if (stage != 'pair') args.remove('--pair');
        await expectLater(
          runCli(args, output: (_) {}, createRuntime: fake.runtime),
          throwsA(isA<QuickBlueSecurityException>()),
        );
        expect(
          fake.calls.where((c) => c.startsWith('pair ')).length,
          stage == 'pair' ? 1 : 0,
        );
        expect(
          fake.calls.where((c) => c.startsWith('read ')).length,
          stage == 'read'
              ? 1
              : stage == 'notify'
              ? 1
              : 0,
        );
        expect(fake.calls.sublist(fake.calls.length - 2), [
          'disconnect $deviceId',
          'close',
        ]);
        expect(fake.scans.hasListener, isFalse);
      },
    );
  }
  test('primary pairing failure survives close failure', () async {
    final error = StateError('pair');
    final fake = FakeRuntime()
      ..pairError = error
      ..closeError = StateError('close');
    final output = <String>[];
    await expectLater(
      runCli(flowArgs, output: output.add, createRuntime: fake.runtime),
      throwsA(same(error)),
    );
    expect(output.any((line) => line.contains('cleanup close failed')), isTrue);
    expect(fake.closed, isTrue);
  });
  test('stop scan cancels subscription and never connects', () async {
    final stop = Completer<void>();
    final fake = FakeRuntime();
    await runCli(
      flowArgs,
      createRuntime: fake.runtime,
      stop: stop.future,
      output: (line) {
        if (line.contains('serviceData') && !stop.isCompleted) stop.complete();
      },
    );
    expect(fake.calls, ['scan', 'stopScan', 'close']);
  });
}
