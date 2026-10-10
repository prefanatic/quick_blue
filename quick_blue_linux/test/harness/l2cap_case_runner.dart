// stdout is the newline-JSON observation protocol consumed by the watchdog.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:quick_blue_linux/src/l2cap_channel.dart';
import 'package:quick_blue_linux/src/l2cap_framing.dart';

import 'scripted_native.dart';

// Independent reporter remains responsive even if the channel isolate spins.
void reporter(SendPort ready) {
  final inbox = ReceivePort();
  var metrics = <String, Object>{};
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
    print(
      jsonEncode({'kind': 'observer', 'observerTicks': ++ticks, ...metrics}),
    );
  });
  inbox.listen((message) {
    if (message == 'stop') {
      timer.cancel();
      inbox.close();
    } else {
      metrics = Map<String, Object>.from(message as Map);
    }
  });
  ready.send(inbox.sendPort);
}

Future<void> main(List<String> args) async {
  final scenario = args.single;
  final native = ScriptedLibc();
  final allocator = CountingAllocator();
  switch (scenario) {
    case 'send-einval':
      native.persistentSend = (-1, L2capErrno.einval);
    case 'send-eintr':
      native.persistentSend = (-1, L2capErrno.eintr);
    case 'recv-eintr':
      native.persistentRecv = (-1, L2capErrno.eintr);
    case 'recv-data':
      native.persistentRecv = (1, 0);
    case 'send-zero':
      native.persistentSend = (0, 0);
    default:
      throw ArgumentError.value(scenario);
  }
  final ready = ReceivePort();
  final observer = await Isolate.spawn(reporter, ready.sendPort);
  final port = await ready.first as SendPort;
  ready.close();
  var mainTicks = 0;
  Map<String, Object> metrics() => {
    ...native.ledger,
    ...allocator.ledger,
    'mainTicks': mainTicks,
  };
  native.observe = () => port.send(metrics());
  final socket = await L2capChannel(
    deviceId: '00:11:22:33:44:55',
    psm: 0x1001,
    addressType: 1,
    libc: native,
    bluetooth: ScriptedBluetooth(),
    allocator: allocator,
    logger: Logger('harness'),
  ).open();
  final subscription = socket.stream.listen((_) {});
  final heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
    mainTicks++;
    port.send(metrics());
  });
  print(jsonEncode({'kind': 'armed', 'case': scenario, ...metrics()}));
  socket.sink.add(Uint8List.fromList([1, 2, 3, 4]));
  // Only the yielding zero-write case gets here. It is not operation success.
  await Future<void>.delayed(const Duration(seconds: 30));
  socket.sink.close();
  await subscription.cancel();
  heartbeat.cancel();
  port.send('stop');
  observer.kill();
}
