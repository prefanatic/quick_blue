import 'dart:io';

import 'package:quick_blue_linux_cli/fake_runtime.dart';

Future<void> main() => fakeFlow(stdout.writeln);
