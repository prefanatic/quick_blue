import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_example/src/ble_explorer_controller.dart';
import 'package:quick_blue_example/src/ble_explorer_page.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import '../fake_quick_blue_platform.dart';

// Raw primitives only: the real public lifecycle coordinator remains in use.
class LifecyclePlatform extends FakeQuickBluePlatform {
  int connectionListeners = 0;
  final terminalEvents =
      StreamController<BluetoothConnectionStateChange>.broadcast();
  @override
  Stream<BluetoothConnectionStateChange> get connectionStateStream {
    final source = super.connectionStateStream;
    return Stream.multi((sink) {
      connectionListeners++;
      final subscription = source.listen(sink.add, onError: sink.addError);
      final injected = terminalEvents.stream.listen(
        sink.add,
        onError: sink.addError,
      );
      sink.onCancel = () async {
        connectionListeners--;
        await injected.cancel();
        await subscription.cancel();
      };
    });
  }

  final connectGates = <String, Completer<void>>{};
  final disconnectGates = <String, Completer<void>>{};
  Object? connectError;
  Object? disconnectError;
  bool emitConnect = true;
  bool emitDisconnect = true;
  Completer<void>? stopScanGate;

  @override
  Future<void> stopScan() async {
    calls.add('stopScan');
    await stopScanGate?.future;
  }

  @override
  Future<void> dispose() async {
    await terminalEvents.close();
    await super.dispose();
  }

  @override
  Future<void> connect(String id) async {
    calls.add('connect $id');
    if (connectError case final error?) throw error;
    await connectGates[id]?.future;
    if (emitConnect) {
      onConnectionChanged!(
        id,
        BlueConnectionState.connected,
        BleStatus.success,
      );
    }
  }

  @override
  Future<void> disconnect(String id) async {
    calls.add('disconnect $id');
    if (disconnectError case final error?) throw error;
    await disconnectGates[id]?.future;
    if (emitDisconnect) {
      onConnectionChanged!(
        id,
        BlueConnectionState.disconnected,
        BleStatus.success,
      );
    }
  }
}

Future<void> drain(WidgetTester tester) async {
  // SDK stream cancellation can complete in the root zone. Yield there without
  // advancing fake time, so exact deadline assertions remain clock-controlled.
  for (var i = 0; i < 20; i++) {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
  }
}

void main() {
  late QuickBluePlatform previous;
  late LifecyclePlatform platform;
  setUp(() {
    previous = QuickBluePlatform.instance;
  });
  void initialize() {
    platform = LifecyclePlatform();
    QuickBluePlatform.instance = platform;
  }

  tearDown(() async {
    QuickBluePlatform.instance = previous;
    await platform.dispose();
  });

  testWidgets('LC-01 deadline actively abandons stalled raw connect', (
    tester,
  ) async {
    initialize();
    final controller = BleExplorerController(
      connectTimeout: const Duration(seconds: 5),
    );
    await drain(tester);
    await controller.selectDevice('a');
    platform.connectGates['a'] = Completer<void>();
    var done = false;
    final connecting = controller.connectSelected().then((_) => done = true);
    await drain(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(done, isFalse);
    await tester.pump(const Duration(seconds: 1));

    await drain(tester);
    await drain(tester);
    expect(platform.calls.where((c) => c == 'disconnect a'), hasLength(1));
    expect(done, isTrue);
    expect(controller.connecting, isFalse);
    await connecting;
    controller.dispose();
    await drain(tester);
    await controller.shutdown();
    platform.connectGates['a']!.complete();
    await drain(tester);
  });

  testWidgets('total connect deadline also bounds stalled scan preparation', (
    tester,
  ) async {
    initialize();
    final controller = BleExplorerController(
      connectTimeout: const Duration(seconds: 5),
    );
    await drain(tester);
    await controller.selectDevice('a');
    await controller.startScan();
    await drain(tester);
    platform.stopScanGate = Completer<void>();
    var done = false;
    final pending = controller.connectSelected().then((_) => done = true);
    await drain(tester);
    await tester.pump(const Duration(milliseconds: 4999));
    await drain(tester);
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await drain(tester);
    expect(done, isTrue);
    expect(controller.connecting, isFalse);
    expect(platform.calls, isNot(contains('connect a')));
    platform.stopScanGate!.complete();
    await drain(tester);
    await pending;
    expect(platform.calls, isNot(contains('connect a')));
    controller.dispose();
    await drain(tester);
    await controller.shutdown();
  });

  testWidgets('LC-02 raw completion does not reset total deadline', (
    tester,
  ) async {
    initialize();
    final controller = BleExplorerController(
      connectTimeout: const Duration(seconds: 5),
    );
    await drain(tester);
    await controller.selectDevice('a');
    platform.emitConnect = false;
    final gate = platform.connectGates['a'] = Completer<void>();
    var done = false;
    final connecting = controller.connectSelected().then((_) => done = true);
    await drain(tester);
    await tester.pump(const Duration(seconds: 4));
    gate.complete();
    await drain(tester);
    await tester.pump(const Duration(seconds: 1));
    await drain(tester);
    await drain(tester);
    expect(done, isTrue);
    expect(platform.calls, contains('disconnect a'));
    await connecting;
    controller.dispose();
    await drain(tester);
    await controller.shutdown();
  });

  testWidgets('LC-04 raw failure leaves no unused stream waiter', (
    tester,
  ) async {
    initialize();
    final controller = BleExplorerController();
    await drain(tester);
    await controller.selectDevice('a');
    platform.connectError = const QuickBlueException(
      code: QuickBlueErrorCode.invalidState,
      operation: 'connect',
      message: 'raw failure',
    );
    final connecting = controller.connectSelected();
    await drain(tester);
    await drain(tester);
    await drain(tester);
    await connecting;
    final switching = controller.selectDevice('b');
    await drain(tester);
    await switching;
    expect(
      platform.connectionListeners,
      1,
      reason:
          'Only the selected-device UI subscription remains; no orphan firstWhere waiter.',
    );
    expect(controller.lastConnectionError, same(platform.connectError));
    platform.terminalEvents.addError(StateError('late stream failure'));
    await drain(tester);
    platform.onConnectionChanged!(
      'a',
      BlueConnectionState.disconnected,
      BleStatus.failure,
    );
    await drain(tester);
    expect(tester.takeException(), isNull);
    controller.dispose();
    await drain(tester);
    await controller.shutdown();
  });

  testWidgets('LC-09 dispose detaches pending connection exactly once', (
    tester,
  ) async {
    initialize();
    final controller = BleExplorerController();
    await drain(tester);
    await controller.selectDevice('a');
    platform.connectGates['a'] = Completer<void>();
    final connecting = controller.connectSelected();
    await drain(tester);
    controller.dispose();
    await drain(tester);
    await controller.shutdown();
    await drain(tester);
    expect(platform.calls.where((c) => c == 'disconnect a'), hasLength(1));
    platform.connectGates['a']!.complete();
    await drain(tester);
    await connecting;
  });

  testWidgets('widget removal abandons pending connect without late UI work', (
    tester,
  ) async {
    initialize();
    platform.connectGates['a'] = Completer<void>();
    await tester.pumpWidget(const MaterialApp(home: BleExplorerPage()));
    await drain(tester);
    await tester.tap(find.text('Scan 10s'));
    await drain(tester);
    platform.addScanResult(
      BlueScanResult(name: 'Lifecycle sensor', deviceId: 'a', rssi: -40),
    );
    await drain(tester);
    await tester.tap(
      find.byKey(const ValueKey('ble_device_row_name_Lifecycle sensor')),
    );
    await tester.pumpAndSettle();
    await drain(tester);
    await tester.tap(find.byKey(const ValueKey('ble_connect_button')));
    await drain(tester);
    expect(find.text('Connecting'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
    expect(platform.calls.where((c) => c == 'disconnect a'), hasLength(1));
    platform.connectGates['a']!.complete();
    await drain(tester);
    expect(platform.calls, isNot(contains('discoverServices a')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('A1 public disconnect cancels pending connect as cancelled', (
    tester,
  ) async {
    initialize();
    platform.connectGates['a'] = Completer<void>();
    Object? failure;
    final connecting = platform.device('a').connect().catchError((
      Object error,
    ) {
      failure = error;
    });
    await drain(tester);
    final disconnecting = platform.device('a').disconnect();
    await drain(tester);
    await Future.wait([connecting, disconnecting]);
    expect(
      failure,
      isA<QuickBlueException>().having(
        (e) => e.code,
        'code',
        QuickBlueErrorCode.cancelled,
      ),
    );
    // A6: redundant public disconnect is permitted; controller ownership
    // guards prevent the second detach for its own lease.
    final redundant = platform.device('a').disconnect();
    await drain(tester);
    await redundant;
    expect(platform.calls.where((c) => c == 'disconnect a'), hasLength(2));
    platform.emitConnect = false;
    platform.connectGates['a']!.complete();
    await drain(tester);
  });

  testWidgets(
    'LC-09 shutdown during stalled connect is awaitable and bounded',
    (tester) async {
      initialize();
      final controller = BleExplorerController();
      await drain(tester);
      await controller.selectDevice('a');
      platform.connectGates['a'] = Completer<void>();
      platform.disconnectGates['a'] = Completer<void>();
      final pending = controller.connectSelected();
      await drain(tester);
      var done = false;
      final shutdown = controller.shutdown().then((_) => done = true);
      await drain(tester);
      await tester.pump(const Duration(milliseconds: 2999));
      await drain(tester);
      expect(done, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await drain(tester);
      expect(done, isTrue);
      await Future.wait([pending, shutdown]);
      expect(platform.calls.where((c) => c == 'disconnect a'), hasLength(1));
      expect(controller.cleanupErrors, isNotEmpty);
      platform.connectGates['a']!.complete();
      platform.disconnectGates['a']!.complete();
      await drain(tester);
      controller.dispose();
    },
  );

  for (final structured in [true, false]) {
    testWidgets('LC-03 terminal failure preserves typed error ($structured)', (
      tester,
    ) async {
      initialize();
      final controller = BleExplorerController();
      await drain(tester);
      await controller.selectDevice('a');
      platform.emitConnect = false;
      final pending = controller.connectSelected();
      await drain(tester);
      const error = QuickBlueException(
        code: QuickBlueErrorCode.unavailable,
        failureReason: QuickBlueFailureReason.connectionFailed,
        operation: 'connect',
        message: 'gone',
      );
      platform.terminalEvents.add(
        BluetoothConnectionStateChange(
          deviceId: 'a',
          state: BlueConnectionState.disconnected,
          status: BleStatus.failure,
          error: structured ? error : null,
        ),
      );
      await drain(tester);
      await pending;
      if (structured) {
        expect(controller.lastConnectionError, same(error));
      } else {
        expect(
          controller.lastConnectionError,
          isA<QuickBlueException>().having(
            (e) => e.code,
            'code',
            QuickBlueErrorCode.operationFailed,
          ),
        );
      }
      controller.dispose();
      await drain(tester);
      await controller.shutdown();
    });
  }

  testWidgets('LC-05 late success is inert and fresh connect succeeds', (
    tester,
  ) async {
    initialize();
    final controller = BleExplorerController(
      connectTimeout: const Duration(seconds: 5),
    );
    await drain(tester);
    await controller.selectDevice('a');
    final gate = platform.connectGates['a'] = Completer<void>();
    final pending = controller.connectSelected();
    await drain(tester);
    await tester.pump(const Duration(seconds: 5));
    await drain(tester);
    await pending;
    gate.complete();
    await drain(tester);
    expect(controller.connected, isFalse);
    expect(platform.calls, isNot(contains('discoverServices a')));
    platform.connectGates.clear();
    final fresh = controller.connectSelected();
    await drain(tester);
    await fresh;
    expect(controller.connected, isTrue);
    controller.dispose();
    await drain(tester);
    await controller.shutdown();
  });

  testWidgets(
    'LC-06/07/12 stalled release bounds switching and late event is inert',
    (tester) async {
      initialize();
      final controller = BleExplorerController();
      await drain(tester);
      await controller.selectDevice('a');
      final connecting = controller.connectSelected();
      await drain(tester);
      await connecting;
      final gate = platform.disconnectGates['a'] = Completer<void>();
      var done = false;
      final switching = controller.selectDevice('b').then((_) => done = true);
      await drain(tester);
      await tester.pump(const Duration(milliseconds: 2999));
      await drain(tester);
      expect(done, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await drain(tester);
      expect(done, isTrue);
      await switching;
      expect(platform.calls.where((c) => c == 'disconnect a'), hasLength(1));
      expect(controller.cleanupErrors, contains(isA<TimeoutException>()));
      final fresh = controller.connectSelected();
      await drain(tester);
      await fresh;
      final status = controller.status;
      gate.complete();
      await drain(tester);
      expect(controller.selectedDeviceId, 'b');
      expect(controller.connected, isTrue);
      expect(controller.status, status);
      controller.dispose();
      await drain(tester);
      await controller.shutdown();
    },
  );

  testWidgets('LC-08 rapid A B A shares detach and reconnects', (tester) async {
    initialize();
    final controller = BleExplorerController();
    await drain(tester);
    await controller.selectDevice('a');
    platform.connectGates['a'] = Completer<void>();
    final pending = controller.connectSelected();
    await drain(tester);
    final toB = controller.selectDevice('b');
    final toA = controller.selectDevice('a');
    await drain(tester);
    await Future.wait([toA, toB, pending]);
    expect(platform.calls.where((c) => c == 'disconnect a'), hasLength(1));
    platform.emitConnect = false;
    platform.connectGates['a']!.complete();
    await drain(tester);
    platform.connectGates.clear();
    platform.emitConnect = true;
    final fresh = controller.connectSelected();
    await drain(tester);
    await fresh;
    expect(controller.connected, isTrue);
    expect(controller.lastConnectionError, isNull);
    controller.dispose();
    await drain(tester);
    await controller.shutdown();
  });

  testWidgets(
    'LC-10/11/15 shutdown shares stalled release and retains errors',
    (tester) async {
      initialize();
      final controller = BleExplorerController();
      await drain(tester);
      await controller.selectDevice('a');
      final pending = controller.connectSelected();
      await drain(tester);
      await pending;
      final gate = platform.disconnectGates['a'] = Completer<void>();
      final switching = controller.selectDevice('b');
      await drain(tester);
      var done = false;
      final shutdown = controller.shutdown().then((_) => done = true);
      expect(controller.shutdown(), same(controller.shutdown()));
      await tester.pump(const Duration(milliseconds: 2999));
      await drain(tester);
      expect(done, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await drain(tester);
      expect(done, isTrue);
      await Future.wait([switching, shutdown]);
      expect(platform.calls.where((c) => c == 'disconnect a'), hasLength(1));
      expect(controller.cleanupErrors, isNotEmpty);
      final status = controller.status;
      gate.complete();
      await drain(tester);
      await controller.connectSelected();
      await controller.selectDevice('c');
      expect(controller.status, status);
      controller.dispose();
    },
  );

  testWidgets('LC-11 cleanup failure is observed without blocking selection', (
    tester,
  ) async {
    initialize();
    final controller = BleExplorerController();
    await drain(tester);
    await controller.selectDevice('a');
    final pending = controller.connectSelected();
    await drain(tester);
    await pending;
    final error = StateError('detach failed');
    platform.disconnectError = error;
    final switching = controller.selectDevice('b');
    await drain(tester);
    await switching;
    expect(controller.cleanupErrors, contains(same(error)));
    expect(controller.selectedDeviceId, 'b');
    expect(
      controller.events.any((e) => e.message.contains('detach failed')),
      isTrue,
    );
    controller.dispose();
    await drain(tester);
    await controller.shutdown();
  });

  testWidgets('LC-13/14 detach is client-local and disconnect is reentrant', (
    tester,
  ) async {
    initialize();
    final other = LifecyclePlatform();
    var otherConnected = false;
    final subscription = other
        .device('a')
        .connectionStateStream
        .listen(
          (e) => otherConnected = e.state == BlueConnectionState.connected,
        );
    final otherConnect = other.device('a').connect();
    await drain(tester);
    await otherConnect;
    final controller = BleExplorerController();
    await drain(tester);
    await controller.selectDevice('a');
    final pending = controller.connectSelected();
    await drain(tester);
    await pending;
    final first = controller.disconnectSelected();
    final second = controller.disconnectSelected();
    await drain(tester);
    await Future.wait([first, second]);
    controller.dispose();
    await drain(tester);
    await controller.shutdown();
    expect(platform.calls.where((c) => c == 'disconnect a'), hasLength(1));
    expect(otherConnected, isTrue);
    expect(other.calls, isNot(contains('disconnect a')));
    final cancel = subscription.cancel();
    await drain(tester);
    await cancel;
    await other.dispose();
  });
}
