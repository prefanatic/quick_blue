import 'dart:async';
import 'dart:io';

import 'package:quick_blue_linux_cli/cli.dart';

Future<void> main(List<String> args) async {
  StreamSubscription<ProcessSignal>? interrupt;
  final stop = Completer<void>();
  try {
    if (!args.contains('--help')) {
      interrupt = ProcessSignal.sigint.watch().listen((_) {
        if (!stop.isCompleted) stop.complete();
      });
    }
    await runCli(args, output: stdout.writeln, stop: stop.future);
  } catch (error, stack) {
    stderr.writeln(error);
    if (error is! FormatException) stderr.writeln(stack);
    exitCode = 1;
  } finally {
    await interrupt?.cancel();
  }
}
