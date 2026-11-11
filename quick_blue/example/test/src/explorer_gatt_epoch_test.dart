import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_example/src/ble_explorer_controller.dart';
import 'package:quick_blue_example/src/ble_value_codec.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import '../fake_quick_blue_platform.dart';
import 'explorer_lifecycle_test.dart' show drain;

// Capture the actual UI listener at the injected Dart boundary. Replaying it
// after cancellation deliberately bypasses normal StreamController delivery;
// this models queued callbacks, not native Bluetooth callback correlation.
class CapturedNotificationStream extends Stream<Uint8List> {
  CapturedNotificationStream({Future<void> Function()? onCancel})
    : _controller = StreamController<Uint8List>(onCancel: onCancel);

  final StreamController<Uint8List> _controller;
  void Function(Uint8List)? _data;
  Function? _error;
  int replayedData = 0;
  int replayedErrors = 0;

  bool get hasListener => _controller.hasListener;
  void add(Uint8List value) => _controller.add(value);
  void addError(Object error) => _controller.addError(error);
  Future<void> close() => _controller.close();

  void replayData(Uint8List value) {
    replayedData++;
    _data!(value);
  }

  void replayError(Object error) {
    replayedErrors++;
    (_error! as void Function(Object))(error);
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _data = onData;
    _error = onError;
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

// Inject result futures at the Dart boundary, deliberately independent of the
// real discovery coordinator's cancellation. This proves UI ownership only,
// not native callback correlation or physical Bluetooth semantics.
class EpochPlatform extends FakeQuickBluePlatform {
  final discoveries = <Completer<List<BluetoothService>>>[];
  Completer<Uint8List>? readGate;
  Completer<void>? writeGate;
  Completer<void>? cancelGate;
  final notifications = <CapturedNotificationStream>[];
  int writes = 0;
  int activeDiscoveries = 0;
  int maxActiveDiscoveries = 0;

  @override
  Future<T> waitForDeviceOperation<T>({
    required String deviceId,
    required String operation,
    required Future<T> Function() action,
    int? argument,
    Duration? timeout,
    QuickBlueCancellationToken? cancellationToken,
  }) {
    if (operation != 'discoverServices') {
      // Deliberate test-boundary override; other operations use the real owner.
      // ignore: invalid_use_of_internal_member
      return super.waitForDeviceOperation(
        deviceId: deviceId,
        operation: operation,
        action: action,
        argument: argument,
        timeout: timeout,
        cancellationToken: cancellationToken,
      );
    }
    final gate = Completer<List<BluetoothService>>();
    discoveries.add(gate);
    activeDiscoveries++;
    if (activeDiscoveries > maxActiveDiscoveries) {
      maxActiveDiscoveries = activeDiscoveries;
    }
    return gate.future.whenComplete(() => activeDiscoveries--) as Future<T>;
  }

  @override
  Future<Uint8List> readCharacteristicValue(String d, String s, String c) {
    return readGate?.future ?? Future.value(Uint8List.fromList([7]));
  }

  @override
  Future<void> writeValue(
    String d,
    String s,
    String c,
    Uint8List value,
    BleOutputProperty mode,
  ) async {
    writes++;
    await writeGate?.future;
  }

  @override
  Stream<Uint8List> characteristicNotifications(
    String d,
    String s,
    String c, {
    BleInputProperty bleInputProperty = BleInputProperty.notification,
  }) {
    final stream = CapturedNotificationStream(
      onCancel: () => cancelGate?.future ?? Future<void>.value(),
    );
    notifications.add(stream);
    return stream;
  }

  @override
  Future<void> dispose() async {
    for (final stream in notifications) {
      await stream.close();
    }
    await super.dispose();
  }
}

BluetoothService row(String device, {String uuid = 'service'}) =>
    BluetoothService(
      deviceId: device,
      uuid: uuid,
      characteristics: ['char'],
      characteristicDetails: [BluetoothCharacteristicInfo(uuid: 'char')],
    );

void main() {
  late QuickBluePlatform previous;
  late EpochPlatform platform;
  late BleExplorerController controller;

  setUp(() {
    previous = QuickBluePlatform.instance;
    platform = EpochPlatform();
    QuickBluePlatform.instance = platform;
    controller = BleExplorerController();
  });
  tearDown(() async {
    QuickBluePlatform.instance = previous;
    await platform.dispose();
  });

  void epochTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        final shutdown = controller.shutdown();
        await drain(tester);
        await shutdown;
        controller.dispose();
      }
    });
  }

  Future<void> connect(WidgetTester tester, String device) async {
    final selection = controller.selectDevice(device);
    await drain(tester);
    await selection;
    final pending = controller.connectSelected();
    await drain(tester);
    platform.discoveries.last.complete([row(device)]);
    await drain(tester);
    await pending;
  }

  Future<void> switchAway(WidgetTester tester, bool returnToA) async {
    final selection = controller.selectDevice('b');
    await drain(tester);
    await selection;
    if (returnToA) {
      final returning = controller.selectDevice('a');
      await drain(tester);
      await returning;
    }
    await drain(tester);
  }

  for (final returnToA in [false, true]) {
    final route = returnToA ? 'A-B-A' : 'A-B';
    for (final fail in [false, true]) {
      epochTest('$route delayed discovery ($fail) is retired', (tester) async {
        final selection = controller.selectDevice('a');
        await drain(tester);
        await selection;
        final pending = controller.connectSelected();
        await drain(tester);
        final old = platform.discoveries.last;
        await switchAway(tester, returnToA);
        final status = controller.status;
        if (fail) {
          old.completeError(StateError('retired discovery'));
        } else {
          old.complete([row('a', uuid: 'old')]);
        }
        await drain(tester);
        await pending;
        expect(controller.status, status);
        expect(controller.services, isEmpty);
        expect(controller.discovering, isFalse);
        expect(tester.takeException(), isNull);
      });

      for (final write in [false, true]) {
        epochTest(
          '$route delayed ${write ? 'write' : 'read'} ($fail) is retired',
          (tester) async {
            await connect(tester, 'a');
            final service = controller.services.single;
            platform.readGate = Completer<Uint8List>();
            platform.writeGate = Completer<void>();
            controller
                    .writeControllerFor(characteristicKey('service', 'char'))
                    .text =
                '01';
            final pending = write
                ? controller.writeCharacteristic(service, 'char')
                : controller.readCharacteristic(service, 'char');
            await drain(tester);
            await switchAway(tester, returnToA);
            await connect(tester, returnToA ? 'a' : 'b');
            final oldRead = platform.readGate;
            platform.readGate = null;
            await controller.readCharacteristic(
              controller.services.single,
              'char',
            );
            platform.readGate = oldRead;
            final status = controller.status;
            if (write) {
              if (fail) {
                platform.writeGate!.completeError(StateError('retired write'));
              } else {
                platform.writeGate!.complete();
              }
            } else {
              if (fail) {
                platform.readGate!.completeError(StateError('retired read'));
              } else {
                platform.readGate!.complete(Uint8List.fromList([1, 2]));
              }
            }
            await drain(tester);
            await pending;
            expect(controller.status, status);
            expect(controller.latestValues.values.single, [7]);
            expect(platform.writes, write ? 1 : 0);
            if (fail) expect(controller.gattErrors, isNotEmpty);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    epochTest('$route delayed notification stop cannot alter new status', (
      tester,
    ) async {
      await connect(tester, 'a');
      final service = controller.services.single;
      await controller.toggleNotify(service, 'char');
      platform.notifications.last.add(Uint8List.fromList([9]));
      await drain(tester);
      expect(controller.latestValues, isNotEmpty);
      platform.cancelGate = Completer<void>();
      final pending = controller.toggleNotify(service, 'char');
      await drain(tester);
      await switchAway(tester, returnToA);
      final status = controller.status;
      platform.cancelGate!.complete();
      await drain(tester);
      await pending;
      expect(controller.status, status);
      expect(controller.latestValues, isEmpty);
      expect(controller.notificationKeys, isEmpty);
    });
  }

  epochTest(
    'invalidation clears rows, values and claims and coalesces refresh',
    (tester) async {
      await connect(tester, 'a');
      await controller.readCharacteristic(controller.services.single, 'char');
      await controller.toggleNotify(controller.services.single, 'char');
      platform.handleGattServicesChanged('a');
      platform.handleGattServicesChanged('a');
      await drain(tester);
      expect(controller.services, isEmpty);
      expect(controller.latestValues, isEmpty);
      expect(controller.notificationKeys, isEmpty);
      expect(platform.discoveries, hasLength(2));
      platform.discoveries.last.complete([row('a', uuid: 'fresh')]);
      await drain(tester);
      expect(controller.services.single.uuid, 'fresh');
      expect(platform.maxActiveDiscoveries, 1);
    },
  );

  epochTest(
    'invalidation during refresh queues one replacement without overlap',
    (tester) async {
      await connect(tester, 'a');
      final refresh = controller.discoverServices();
      await drain(tester);
      final old = platform.discoveries.last;
      platform.handleGattServicesChanged('a');
      platform.handleGattServicesChanged('a');
      await drain(tester);
      expect(platform.discoveries, hasLength(2));
      old.complete([row('a', uuid: 'obsolete')]);
      await drain(tester);
      expect(controller.services, isEmpty);
      expect(platform.discoveries, hasLength(3));
      platform.discoveries.last.complete([row('a', uuid: 'fresh')]);
      await drain(tester);
      await refresh;
      expect(controller.services.single.uuid, 'fresh');
      expect(platform.maxActiveDiscoveries, 1);
    },
  );

  epochTest(
    'retirement drops queued refresh and ignores unrelated invalidation',
    (tester) async {
      await connect(tester, 'a');
      platform.handleGattServicesChanged('b');
      await drain(tester);
      expect(platform.discoveries, hasLength(1));
      final refresh = controller.discoverServices();
      await drain(tester);
      platform.handleGattServicesChanged('a');
      await drain(tester);
      final selection = controller.selectDevice('b');
      await drain(tester);
      await selection;
      final status = controller.status;
      platform.discoveries.last.completeError(StateError('retired refresh'));
      await drain(tester);
      await refresh;
      expect(platform.discoveries, hasLength(2));
      expect(controller.status, status);
      expect(tester.takeException(), isNull);
    },
  );

  for (final returnToA in [false, true]) {
    for (final fail in [false, true]) {
      epochTest(
        'notification retirement preserves fresh claims ($returnToA, $fail)',
        (tester) async {
          await connect(tester, 'a');
          final oldService = controller.services.single;
          await controller.toggleNotify(oldService, 'char');
          final oldStream = platform.notifications.last;
          platform.cancelGate = Completer<void>();
          final stopping = controller.toggleNotify(oldService, 'char');
          await drain(tester);
          await switchAway(tester, returnToA);
          await connect(tester, returnToA ? 'a' : 'b');
          // Old and fresh rows deliberately have the same characteristic key.
          await controller.toggleNotify(controller.services.single, 'char');
          platform.notifications.last.add(Uint8List.fromList([42]));
          await drain(tester);
          final status = controller.status;
          final freshService = controller.services.single;
          final claims = controller.notificationKeys.toSet();
          final message = controller.message;
          final freshStream = platform.notifications.last;
          final failure = StateError('retired notification stop');
          if (fail) {
            platform.cancelGate!.completeError(failure);
          } else {
            platform.cancelGate!.complete();
          }
          platform.cancelGate = null;
          expect(oldStream.hasListener, isFalse);
          expect(freshStream.hasListener, isTrue);
          final eventFailure = StateError('retired notification event');
          oldStream.replayData(Uint8List.fromList([99]));
          oldStream.replayError(eventFailure);
          await drain(tester);
          await stopping;
          expect(oldStream.replayedData, 1);
          expect(oldStream.replayedErrors, 1);
          expect(controller.services.single, same(freshService));
          expect(controller.message, message);
          expect(controller.status, status);
          expect(controller.latestValues.values.single, [42]);
          expect(controller.notificationKeys.toSet(), claims);
          expect(freshStream.hasListener, isTrue);
          expect(controller.gattErrors, contains(same(eventFailure)));
          if (fail) expect(controller.gattErrors, contains(same(failure)));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  epochTest('equal obsolete rows cannot dispatch work after A-B-A', (
    tester,
  ) async {
    await connect(tester, 'a');
    final old = controller.services.single;
    await switchAway(tester, true);
    await connect(tester, 'a');
    expect(old, controller.services.single);
    final status = controller.status;
    controller.writeControllerFor(characteristicKey('service', 'char')).text =
        '01';
    await controller.readCharacteristic(old, 'char');
    await controller.writeCharacteristic(old, 'char');
    await controller.toggleNotify(old, 'char');
    expect(controller.status, status);
    expect(controller.latestValues, isEmpty);
    expect(platform.writes, 0);
    expect(platform.notifications, isEmpty);
  });

  epochTest('current notification error releases claim and remains visible', (
    tester,
  ) async {
    await connect(tester, 'a');
    await controller.toggleNotify(controller.services.single, 'char');
    final failure = StateError('current notification failed');
    platform.notifications.last.addError(failure);
    await drain(tester);
    expect(controller.notificationKeys, isEmpty);
    expect(controller.status, 'Notification failed.');
    expect(controller.gattErrors, contains(same(failure)));
    expect(tester.takeException(), isNull);
  });

  epochTest('new selection discovery waits for retired work without overlap', (
    tester,
  ) async {
    await connect(tester, 'a');
    final oldRefresh = controller.discoverServices();
    await drain(tester);
    final old = platform.discoveries.last;
    await switchAway(tester, true);
    final freshConnect = controller.connectSelected();
    await drain(tester);
    expect(platform.discoveries, hasLength(2));
    expect(controller.discovering, isTrue);
    old.complete([row('a', uuid: 'obsolete')]);
    await drain(tester);
    expect(platform.discoveries, hasLength(3));
    expect(controller.services, isEmpty);
    platform.discoveries.last.complete([row('a', uuid: 'new')]);
    await drain(tester);
    await Future.wait([oldRefresh, freshConnect]);
    expect(controller.services.single.uuid, 'new');
    expect(platform.maxActiveDiscoveries, 1);
  });

  epochTest('invalidation retires pending read and write without retries', (
    tester,
  ) async {
    await connect(tester, 'a');
    final old = controller.services.single;
    platform.readGate = Completer<Uint8List>();
    platform.writeGate = Completer<void>();
    controller.writeControllerFor(characteristicKey('service', 'char')).text =
        '01';
    final reading = controller.readCharacteristic(old, 'char');
    final writing = controller.writeCharacteristic(old, 'char');
    await drain(tester);
    platform.handleGattServicesChanged('a');
    await drain(tester);
    platform.discoveries.last.complete([row('a')]);
    await drain(tester);
    final status = controller.status;
    platform.readGate!.complete(Uint8List.fromList([99]));
    platform.writeGate!.completeError(StateError('obsolete write'));
    await drain(tester);
    await Future.wait([reading, writing]);
    expect(controller.status, status);
    expect(controller.latestValues, isEmpty);
    expect(platform.writes, 1);
    expect(controller.gattErrors, isNotEmpty);
  });
}
