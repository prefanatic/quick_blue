import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_darwin/src/messages.g.dart' as messages;
import 'package:quick_blue_darwin/src/quick_blue_darwin.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

const eventChannel =
    'dev.flutter.pigeon.quick_blue_darwin.QuickBlueEventApi.l2CapSocketEvents';
const apiPrefix = 'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var closes = 0;
  var cancels = 0;
  void mock(String method, Future<Object?> Function(Object?) handler) {
    messenger.setMockDecodedMessageHandler<Object?>(
      BasicMessageChannel<Object?>(
        '$apiPrefix$method',
        messages.QuickBlueApi.pigeonChannelCodec,
      ),
      handler,
    );
  }

  Future<void> emit(messages.PlatformL2CapSocketEvent event) async {
    await messenger.handlePlatformMessage(
      eventChannel,
      messages.pigeonMethodCodec.encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  setUp(() {
    closes = 0;
    cancels = 0;
    messenger.setMockMessageHandler(eventChannel, (data) async {
      if (data != null &&
          messages.pigeonMethodCodec.decodeMethodCall(data).method ==
              'cancel') {
        cancels++;
      }
      return messages.pigeonMethodCodec.encodeSuccessEnvelope(null);
    });
    mock('closeL2cap', (_) async {
      closes++;
      return <Object?>[null];
    });
    mock('writeL2cap', (_) async => <Object?>[null]);
  });
  tearDown(() {
    messenger.setMockMessageHandler(eventChannel, null);
    for (final method in ['openL2cap', 'closeL2cap', 'writeL2cap']) {
      messenger.setMockMessageHandler('$apiPrefix$method', null);
    }
  });

  testWidgets('observes opened delivered before host reply', (tester) async {
    mock('openL2cap', (_) async {
      await emit(
        messages.PlatformL2CapSocketEvent(deviceId: 'd', opened: true),
      );
      return <Object?>[null];
    });
    BleL2capSocket? socket;
    final opening = QuickBlueDarwin()
        .openL2cap('d', 25)
        .then((s) => socket = s);
    await tester.pump();
    expect(socket, isNotNull);
    await opening;
    socket!.sink.close();
    await tester.pump();
  });

  for (final terminal in ['error', 'closed']) {
    testWidgets('$terminal settles opening without timeout', (tester) async {
      mock('openL2cap', (_) async => <Object?>[null]);
      Object? failure;
      final opening = QuickBlueDarwin()
          .openL2cap('d', 25)
          .then<void>(
            (_) => fail('unexpected socket'),
            onError: (Object error) => failure = error,
          );
      await tester.pump();
      await emit(
        messages.PlatformL2CapSocketEvent(
          deviceId: 'd',
          error: terminal == 'error' ? 'failed' : null,
          closed: terminal == 'closed',
        ),
      );
      await tester.pump();
      expect(failure, isA<QuickBlueException>());
      await opening;
    });
  }

  Future<BleL2capSocket> open(WidgetTester tester) async {
    mock('openL2cap', (_) async => <Object?>[null]);
    final opening = QuickBlueDarwin().openL2cap('d', 25);
    await tester.pump();
    await emit(messages.PlatformL2CapSocketEvent(deviceId: 'd', opened: true));
    await tester.pump();
    return opening;
  }

  Future<BleL2capSocket> openOn(
    QuickBlueDarwin platform,
    WidgetTester tester,
  ) async {
    mock('openL2cap', (_) async => <Object?>[null]);
    final opening = platform.openL2cap('d', 25);
    await tester.pump();
    await emit(messages.PlatformL2CapSocketEvent(deviceId: 'd', opened: true));
    await tester.pump();
    final socket = await opening;
    socket.stream.listen((_) {});
    return socket;
  }

  testWidgets('stale remote-closed sink cannot close replacement', (
    tester,
  ) async {
    final platform = QuickBlueDarwin();
    final first = await openOn(platform, tester);
    await emit(messages.PlatformL2CapSocketEvent(deviceId: 'd', closed: true));
    await tester.pump();
    final second = await openOn(platform, tester);
    first.sink.close();
    first.sink.close();
    expect(() => first.sink.add(Uint8List(1)), throwsStateError);
    expect(() => first.sink.addError(StateError('stale')), throwsStateError);
    await tester.pump();
    final staleCloses = closes;
    second.sink.close();
    await tester.pump();
    expect(staleCloses, 0, reason: 'device-only close targets replacement');
    expect(closes, 1);
  });

  for (final fails in [false, true]) {
    testWidgets('late close reply (failure: $fails) preserves replacement', (
      tester,
    ) async {
      final platform = QuickBlueDarwin();
      final first = await openOn(platform, tester);
      final reply = Completer<Object?>();
      mock('closeL2cap', (_) {
        closes++;
        return reply.future;
      });
      first.sink.close();
      await tester.pump();
      await emit(
        messages.PlatformL2CapSocketEvent(deviceId: 'd', closed: true),
      );
      await tester.pump();
      final second = await openOn(platform, tester);
      reply.complete(
        fails ? <Object?>['CloseFailed', 'late', null] : <Object?>[null],
      );
      await tester.pump();
      if (fails) expect(tester.takeException(), isA<PlatformException>());
      await expectLater(
        platform.openL2cap('d', 25),
        throwsA(isA<QuickBlueException>()),
      );
      mock('closeL2cap', (_) async {
        closes++;
        return <Object?>[null];
      });
      second.sink.close();
      await tester.pump();
      expect(closes, 2);
    });
  }

  testWidgets(
    'late write failure is observable without affecting replacement',
    (tester) async {
      final platform = QuickBlueDarwin();
      final first = await openOn(platform, tester);
      final reply = Completer<Object?>();
      mock('writeL2cap', (_) => reply.future);
      first.sink.add(Uint8List(1));
      await tester.pump();
      await emit(
        messages.PlatformL2CapSocketEvent(deviceId: 'd', closed: true),
      );
      await tester.pump();
      final second = await openOn(platform, tester);
      reply.complete(<Object?>['WriteFailed', 'late', null]);
      await tester.pump();
      expect(tester.takeException(), isA<PlatformException>());
      await expectLater(
        platform.openL2cap('d', 25),
        throwsA(isA<QuickBlueException>()),
      );
      second.sink.close();
      await tester.pump();
      expect(closes, 1);
    },
  );

  testWidgets('sink close invokes native close exactly once', (tester) async {
    final socket = await open(tester);
    socket.sink.close();
    socket.sink.close();
    await tester.pump();
    expect(closes, 1);
  });

  testWidgets('write and close bridge failures reach socket stream', (
    tester,
  ) async {
    final socket = await open(tester);
    final errors = <Object>[];
    socket.stream.listen((_) {}, onError: errors.add);
    mock('writeL2cap', (_) async => <Object?>['WriteFailed', 'write', null]);
    mock('closeL2cap', (_) async => <Object?>['CloseFailed', 'close', null]);
    socket.sink.add(Uint8List.fromList([1]));
    await tester.pump();
    // EventSink.close has no awaitable contract: the stream is the error path.
    socket.sink.close();
    await tester.pump();
    expect(errors, hasLength(2));
    expect(errors, everyElement(isA<PlatformException>()));
  });

  testWidgets('deadline closes and controlled late opened is closed again', (
    tester,
  ) async {
    mock('openL2cap', (_) async => <Object?>[null]);
    Object? failure;
    final platform = QuickBlueDarwin();
    final opening = platform
        .openL2cap('d', 25)
        .then<void>(
          (_) => fail('unexpected socket'),
          onError: (Object e) => failure = e,
        );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(failure, isA<TimeoutException>());
    expect(closes, 1);
    Object? retryError;
    final retry = platform
        .openL2cap('d', 25)
        .then<void>(
          (_) => fail('quarantine allowed retry'),
          onError: (Object e) => retryError = e,
        );
    await tester.pump();
    await retry;
    expect(retryError, isA<QuickBlueException>());
    await emit(messages.PlatformL2CapSocketEvent(deviceId: 'd', opened: true));
    await tester.pump();
    expect(closes, 2);
    expect(cancels, 1);
    await opening;
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('remote closed is delivered and ends the socket stream', (
    tester,
  ) async {
    final socket = await open(tester);
    final events = <BleL2CapSocketEvent>[];
    var done = false;
    socket.stream.listen(events.add, onDone: () => done = true);
    await emit(messages.PlatformL2CapSocketEvent(deviceId: 'd', closed: true));
    await tester.pump();
    expect(events.last, isA<BleL2CapSocketEventClosed>());
    expect(done, isTrue);
    expect(() => socket.sink.add(Uint8List(1)), throwsStateError);
  });

  testWidgets('host open failure settles without waiting for events', (
    tester,
  ) async {
    mock('openL2cap', (_) async => <Object?>['OpenFailed', 'failed', null]);
    Object? failure;
    final opening = QuickBlueDarwin()
        .openL2cap('d', 25)
        .then<void>(
          (_) => fail('unexpected socket'),
          onError: (Object e) => failure = e,
        );
    await tester.pump();
    expect(failure, isA<PlatformException>());
    await opening;
  });

  testWidgets(
    'terminal event rejects even after opened while host reply is pending',
    (tester) async {
      final reply = Completer<Object?>();
      mock('openL2cap', (_) => reply.future);
      Object? failure;
      final opening = QuickBlueDarwin()
          .openL2cap('d', 25)
          .then<void>(
            (_) => fail('unexpected socket'),
            onError: (Object e) => failure = e,
          );
      await tester.pump();
      await emit(
        messages.PlatformL2CapSocketEvent(deviceId: 'd', opened: true),
      );
      await emit(
        messages.PlatformL2CapSocketEvent(deviceId: 'd', error: 'failed'),
      );
      await tester.pump();
      expect(failure, isA<QuickBlueException>());
      await opening;
      reply.complete(<Object?>[null]);
      await tester.pump();
    },
  );

  testWidgets('silent deadline cleanup expires and removes the listener', (
    tester,
  ) async {
    mock('openL2cap', (_) async => <Object?>[null]);
    final opening = QuickBlueDarwin()
        .openL2cap('d', 25)
        .then<void>((_) => fail('unexpected socket'), onError: (Object e) {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(cancels, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(cancels, 1);
    expect(closes, 1);
    await opening;
  });
}
