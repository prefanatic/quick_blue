// JSON observations intentionally go to the test reporter for retained evidence.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  // Flutter's test isolate does not expose Isolate.packageConfig. Pub writes
  // the configuration at the package root or its containing workspace root.
  final packageConfig = [
    File('.dart_tool/package_config.json'),
    File('../.dart_tool/package_config.json'),
  ].firstWhere((file) => file.existsSync()).absolute.path;
  for (final scenario in [
    'send-einval',
    'send-eintr',
    'recv-eintr',
    'recv-data',
    'send-zero',
  ]) {
    test('$scenario: watchdog termination is failure characterization', () async {
      // Standalone SDKs need not be on PATH. Flutter tests run in flutter_tester,
      // so retain the Flutter toolchain's PATH lookup only in that environment.
      final executable = Platform.resolvedExecutable;
      final dart = executable.endsWith('flutter_tester') ? 'dart' : executable;
      final process = await Process.start(dart, [
        '--packages=$packageConfig',
        'test/harness/l2cap_case_runner.dart',
        scenario,
      ]);
      final observations = <Map<String, dynamic>>[];
      final armed = Completer<void>();
      final errors = StringBuffer();
      final outputDone = Completer<void>();
      final errorDone = Completer<void>();
      final output = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final observation = jsonDecode(line) as Map<String, dynamic>;
              observations.add(observation);
              if (observation['kind'] == 'armed' && !armed.isCompleted) {
                armed.complete();
              }
            },
            onDone: outputDone.complete,
            onError: (Object error, StackTrace stack) {
              if (!armed.isCompleted) armed.completeError(error, stack);
            },
          );
      final stderr = process.stderr
          .transform(utf8.decoder)
          .listen(errors.write, onDone: errorDone.complete);
      int? termination;
      bool killed = false;
      final clock = Stopwatch()..start();
      try {
        await armed.future.timeout(const Duration(seconds: 15));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        killed = process.kill(ProcessSignal.sigkill);
        termination = await process.exitCode.timeout(
          const Duration(seconds: 5),
        );
        // exitCode completion is wait/reap, not merely a successful kill request.
        await outputDone.future.timeout(const Duration(seconds: 5));
        await errorDone.future.timeout(const Duration(seconds: 5));
        expect(killed, isTrue);
        expect(termination, -ProcessSignal.sigkill.signalNumber);
        expect(errors.toString(), isEmpty);
        final samples = observations
            .where((o) => o['kind'] == 'observer')
            .toList();
        expect(samples.length, greaterThanOrEqualTo(2));
        final last = samples.last;
        expect(last['observerTicks'], greaterThan(1));
        expect(last['liveFds'], 1);
        expect(last['closeCalls'], 0);
        expect(last['liveAllocations'], greaterThan(0));
        if (scenario == 'send-zero') {
          expect(last['mainTicks'], greaterThan(1));
          expect(last['sendCalls'], greaterThan(1));
          expect(
            last['liveAllocations'],
            1,
          ); // read buffer; write allocation freed on each yield
        } else {
          expect(last['mainTicks'], lessThanOrEqualTo(3));
          final key = scenario.startsWith('send') ? 'sendCalls' : 'recvCalls';
          expect(last[key], greaterThan(1));
        }
        print(
          jsonEncode({
            'case': scenario,
            'outcome': 'watchdog-killed-operation-not-completed',
            'exitCode': termination,
            'reaped': true,
            'elapsedMs': clock.elapsedMilliseconds,
            ...last,
          }),
        );
      } finally {
        if (termination == null) {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode.timeout(const Duration(seconds: 5));
        }
        await output.cancel();
        await stderr.cancel();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  }
}
