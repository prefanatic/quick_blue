// JSON observations intentionally go to the test reporter for retained evidence.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:quick_blue_linux/src/l2cap_channel.dart';
import 'package:quick_blue_linux/src/l2cap_framing.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'harness/scripted_native.dart';

const deadline = Duration(seconds: 2);
Future<void> until(bool Function() predicate) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > deadline) {
      throw TimeoutException('Observation deadline');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  late ScriptedLibc native;
  late CountingAllocator allocator;
  L2capChannel channel({int psm = 0x1001}) => L2capChannel(
    deviceId: '00:11:22:33:44:55',
    psm: psm,
    addressType: 1,
    libc: native,
    bluetooth: ScriptedBluetooth(),
    allocator: allocator,
    maxPacketLength: 32,
    logger: Logger('characterization'),
  );
  setUp(() {
    native = ScriptedLibc();
    allocator = CountingAllocator();
  });
  void balanced() {
    expect(native.liveFds, isEmpty);
    expect(allocator.live, isEmpty);
    expect(allocator.allocations, allocator.frees);
  }

  for (final scenario in ['success', 'partial', 'eintr', 'eagain']) {
    test('$scenario sends exact bytes and closes once', () async {
      final payload = Uint8List.fromList(List.generate(150, (i) => i));
      if (scenario == 'partial') {
        native.sendResults = List.generate(10, (_) => (7, 0));
      }
      if (scenario == 'eintr') native.sendResults = [(-1, L2capErrno.eintr)];
      if (scenario == 'eagain') {
        native.sendResults = [(-1, L2capErrno.eagain), (-1, L2capErrno.eagain)];
      }
      final socket = await channel().open().timeout(deadline);
      final events = <BleL2CapSocketEvent>[];
      final subscription = socket.stream.listen(events.add);
      var ticks = 0;
      final heartbeat = Timer.periodic(const Duration(milliseconds: 5), (_) {
        ticks++;
      });
      final watch = Stopwatch()..start();
      try {
        socket.sink.add(payload);
        await until(() => native.sent.length == payload.length);
        expect(native.sent, orderedEquals(payload));
        if (scenario == 'eagain') {
          expect(ticks, greaterThan(1));
          expect(native.recvCalls, greaterThan(0));
        }
        if (scenario == 'success') expect(native.sendCalls, 3);
        socket.sink.close();
        socket.sink.close();
        await until(() => events.any((e) => e is BleL2CapSocketEventClosed));
        expect(events.whereType<BleL2CapSocketEventOpened>(), isEmpty);
        expect(native.closeCalls, 1);
        balanced();
        print(
          jsonEncode({
            'case': scenario,
            'outcome': 'completed-and-cleaned',
            'heartbeatTicks': ticks,
            'elapsedMs': watch.elapsedMilliseconds,
            ...native.ledger,
            ...allocator.ledger,
          }),
        );
      } finally {
        heartbeat.cancel();
        socket.sink.close();
        await subscription.cancel().timeout(deadline);
      }
    });
  }
  for (final error in [
    111,
    L2capErrno.einval,
    L2capErrno.eacces,
    L2capErrno.eintr,
  ]) {
    test('failed connect errno $error cleans allocations/fd', () async {
      native.persistentConnect = (-1, error);
      await expectLater(
        channel(
          psm: error == L2capErrno.einval ? 0 : 0x1001,
        ).open().timeout(deadline),
        throwsA(isA<OSError>()),
      );
      expect(native.connectCalls, error == L2capErrno.eintr ? 8 : 1);
      expect(native.closeCalls, 1);
      expect(native.recvCalls, 0);
      balanced();
      print(
        jsonEncode({
          'case': 'connect-$error',
          'outcome': 'open-failed-and-cleaned',
          ...native.ledger,
          ...allocator.ledger,
        }),
      );
    });
  }
  test('socket failure owns no fd and frees read buffer', () async {
    native.socketResult = -1;
    await expectLater(
      channel().open().timeout(deadline),
      throwsA(isA<OSError>()),
    );
    expect(native.closeCalls, 0);
    balanced();
  });
  for (final error in [32, 104, 108, 5]) {
    test('send errno $error closes with typed error and frees frame', () async {
      native.persistentSend = (-1, error);
      final socket = await channel().open().timeout(deadline);
      final events = <BleL2CapSocketEvent>[];
      final subscription = socket.stream.listen(events.add);
      try {
        socket.sink.add(Uint8List.fromList([1, 2]));
        await until(() => events.any((e) => e is BleL2CapSocketEventClosed));
        expect(events.whereType<BleL2CapSocketEventError>(), hasLength(1));
        expect(native.closeCalls, 1);
        balanced();
      } finally {
        socket.sink.close();
        await subscription.cancel().timeout(deadline);
      }
    });
  }
  for (final error in [0, 5]) {
    test(
      'recv data then ${error == 0 ? 'EOF' : 'fatal error'} cleans',
      () async {
        native.recvResults = [(2, 0), error == 0 ? (0, 0) : (-1, error)];
        final socket = await channel().open().timeout(deadline);
        final events = <BleL2CapSocketEvent>[];
        final subscription = socket.stream.listen(events.add);
        try {
          await until(() => events.any((e) => e is BleL2CapSocketEventClosed));
          expect(events.whereType<BleL2CapSocketEventData>().single.data, [
            7,
            7,
          ]);
          expect(
            events.whereType<BleL2CapSocketEventError>().length,
            error == 0 ? 0 : 1,
          );
          balanced();
        } finally {
          socket.sink.close();
          await subscription.cancel().timeout(deadline);
        }
      },
    );
  }
  test(
    'MTU query failure retries but preserves whole-frame send fallback',
    () async {
      native.mtuResult = -1;
      final socket = await channel().open().timeout(deadline);
      final subscription = socket.stream.listen((_) {});
      try {
        socket.sink.add(Uint8List(150));
        await until(() => native.sent.length == 150);
        expect(native.sendCalls, 1);
        socket.sink.close();
        balanced();
      } finally {
        socket.sink.close();
        await subscription.cancel().timeout(deadline);
      }
    },
  );
}
