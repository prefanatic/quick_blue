import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuickBluePlatform previousPlatform;
  late FakeQuickBluePlatform platform;

  setUp(() {
    previousPlatform = QuickBluePlatform.instance;
    platform = FakeQuickBluePlatform();
    QuickBluePlatform.instance = platform;
    QuickBlue.observer = null;
  });

  tearDown(() async {
    QuickBlue.observer = null;
    QuickBluePlatform.instance = previousPlatform;
    await platform.dispose();
  });

  test('configure delegates maintainState to the platform', () async {
    await QuickBlue.configure(maintainState: true);

    expect(platform.calls, <String>['configure true']);
  });

  test('instrumentation preserves future and stream identity', () async {
    final completer = Completer<void>();
    final streamController = StreamController<int>.broadcast();
    final stream = streamController.stream;

    expect(
      identical(
        QuickBlueInstrumentation.observeFuture<void>(
          kind: QuickBlueOperationKind.configure,
          action: () => completer.future,
        ),
        completer.future,
      ),
      isTrue,
    );
    expect(
      identical(
        QuickBlueInstrumentation.observeStream<int>(
          kind: QuickBlueOperationKind.notifications,
          stream: () => stream,
        ),
        stream,
      ),
      isTrue,
    );

    final observer = _RecordingObserver();
    QuickBlue.observer = observer;
    expect(
      identical(
        QuickBlueInstrumentation.observeFuture<void>(
          kind: QuickBlueOperationKind.configure,
          action: () => completer.future,
        ),
        completer.future,
      ),
      isTrue,
    );

    completer.complete();
    await completer.future;
    await streamController.close();
  });

  test('observer reports typed operation context and measurements', () async {
    final observer = _RecordingObserver();
    QuickBlue.observer = observer;

    final mtu = await QuickBlue.device('private-device').requestMtu(128);

    expect(mtu, 128);
    final observed = observer.operations.single;
    expect(observed.start.kind, QuickBlueOperationKind.requestMtu);
    expect(observed.start.deviceId, 'private-device');
    expect(observed.start.requestedMtu, 128);
    expect(observed.start.startTime.isUtc, isTrue);
    expect(observed.end!.outcome, QuickBlueOperationOutcome.completed);
    expect(observed.end!.duration, greaterThanOrEqualTo(Duration.zero));
    expect(observed.end!.measurements, <QuickBlueOperationMeasurement, num>{
      QuickBlueOperationMeasurement.negotiatedMtu: 128,
    });
  });

  test('observer records failed operations', () async {
    final observer = _RecordingObserver();
    QuickBlue.observer = observer;
    final notification = Completer<void>();
    platform.nextSetNotifiable = notification;

    final operation = QuickBlue.device('device-a')
        .characteristic('service-a', 'characteristic-a')
        .setNotifiable(BleInputProperty.notification);
    notification.completeError(StateError('notification setup failed'));

    await expectLater(operation, throwsStateError);
    final observed = observer.operations.single;
    expect(observed.start.kind, QuickBlueOperationKind.setNotifiable);
    expect(observed.start.serviceId, 'service-a');
    expect(observed.start.characteristicId, 'characteristic-a');
    expect(observed.end!.outcome, QuickBlueOperationOutcome.failed);
    expect(observed.end!.error, isA<StateError>());
  });

  test('observer callback failures do not affect operations', () async {
    QuickBlue.observer = _ThrowingObserver(throwOnStart: true);

    await QuickBlue.configure();

    QuickBlue.observer = _ThrowingObserver(throwOnStart: false);

    await QuickBlue.configure();

    expect(platform.calls, <String>['configure false', 'configure false']);
  });

  test('observer records the managed connection lifecycle', () async {
    final observer = _RecordingObserver();
    QuickBlue.observer = observer;

    await QuickBlue.device('device-a').connect();

    final observed = observer.operations.single;
    expect(observed.start.kind, QuickBlueOperationKind.connect);
    expect(observed.start.deviceId, 'device-a');
    expect(observed.end!.outcome, QuickBlueOperationOutcome.completed);
  });

  test('connect waits for the connected state', () async {
    platform.connectsImmediately = false;

    final connect = QuickBlue.connect('device-a');
    var connectCompleted = false;
    final connectCompletedFuture = connect.then((_) => connectCompleted = true);

    await pumpEventQueue();
    expect(platform.calls, <String>['connect device-a']);
    expect(connectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    await connectCompletedFuture;

    expect(connectCompleted, isTrue);
  });

  test('deprecated scanResultStream returns platform stream', () async {
    final results = <BlueScanResult>[];
    final subscription = QuickBlue.scanResultStream.listen(results.add);

    await pumpEventQueue();
    platform.addScanResult('device-a');
    await pumpEventQueue();

    expect(results.single.deviceId, 'device-a');
    expect(platform.calls, isEmpty);

    await subscription.cancel();
  });

  test('deprecated bluetoothDeviceStream returns platform stream', () async {
    final devices = <BluetoothDevice>[];
    final subscription = QuickBlue.bluetoothDeviceStream.listen(devices.add);

    await pumpEventQueue();
    platform.addScanResult('device-a');
    await pumpEventQueue();

    expect(devices.single.id, 'device-a');
    expect(platform.calls, <String>['startScan']);
    await subscription.cancel();
    await pumpEventQueue();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test('bluetoothStateStream delegates to the platform', () async {
    final states = <BlueBluetoothState>[];
    final subscription = QuickBlue.bluetoothStateStream.listen(states.add);

    await pumpEventQueue();
    platform.addBluetoothState(BlueBluetoothState.poweredOff);
    await pumpEventQueue();

    expect(states, <BlueBluetoothState>[BlueBluetoothState.poweredOff]);
    expect(platform.calls, <String>['bluetoothStateStream']);

    await subscription.cancel();
  });

  test('bluetoothStateStream replays latest state to new listeners', () async {
    platform.emitInitialBluetoothState = true;

    final stream = QuickBlue.bluetoothStateStream;
    final firstStates = <BlueBluetoothState>[];
    final firstSubscription = stream.listen(firstStates.add);

    await pumpEventQueue();
    expect(firstStates, <BlueBluetoothState>[BlueBluetoothState.poweredOn]);

    platform.addBluetoothState(BlueBluetoothState.poweredOff);
    await pumpEventQueue();
    expect(firstStates, <BlueBluetoothState>[
      BlueBluetoothState.poweredOn,
      BlueBluetoothState.poweredOff,
    ]);

    final secondStates = <BlueBluetoothState>[];
    final secondSubscription = stream.listen(secondStates.add);

    await pumpEventQueue();
    expect(secondStates, <BlueBluetoothState>[BlueBluetoothState.poweredOff]);

    await firstSubscription.cancel();
    await secondSubscription.cancel();
  });

  test('disconnect waits for the disconnected state', () async {
    platform.disconnectsImmediately = false;

    final disconnect = QuickBlue.disconnect('device-a');
    var disconnectCompleted = false;
    final disconnectCompletedFuture = disconnect.then(
      (_) => disconnectCompleted = true,
    );

    await pumpEventQueue();
    expect(platform.calls, <String>['disconnect device-a']);
    expect(disconnectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
    await disconnectCompletedFuture;

    expect(disconnectCompleted, isTrue);
  });

  test('bondState delegates to the platform device', () async {
    final state = await QuickBlue.bondState('device-a');

    expect(state, BluetoothBondState.notBonded);
    expect(platform.calls, <String>['bondState device-a']);
  });

  test('bondStateStream forwards platform transitions', () async {
    final event = QuickBlue.bondStateStream.first;

    platform.addBondStateChange(
      'device-a',
      BluetoothBondState.bonding,
      previousState: BluetoothBondState.notBonded,
    );

    expect(
      await event,
      const BluetoothBondStateChange(
        deviceId: 'device-a',
        state: BluetoothBondState.bonding,
        previousState: BluetoothBondState.notBonded,
      ),
    );
  });

  test('waitForBondState delegates through the device API', () async {
    final waiting = QuickBlue.waitForBondState(
      'device-a',
      BluetoothBondState.bonded,
    );
    await pumpEventQueue();

    expect(platform.calls, <String>['bondState device-a']);
    platform.addBondStateChange(
      'device-a',
      BluetoothBondState.bonded,
      previousState: BluetoothBondState.bonding,
    );

    expect(await waiting, BluetoothBondState.bonded);
  });

  test('pair delegates to the platform device', () async {
    await QuickBlue.pair('device-a');

    expect(platform.calls, <String>['pair device-a']);
  });

  test('discoverGatt returns a discovered GATT view', () async {
    platform.discoveredServices = <BluetoothService>[
      BluetoothService(
        deviceId: 'device-a',
        uuid: 'service-a',
        characteristics: const <String>['characteristic-a'],
      ),
    ];

    final gatt = await QuickBlue.discoverGatt('device-a');

    expect(platform.calls, <String>['discoverServices device-a']);
    expect(gatt.deviceId, 'device-a');
    expect(gatt.services.map((service) => service.uuid), <String>['service-a']);
  });

  test('scanResults starts and stops scanning', () async {
    final results = <BlueScanResult>[];
    final subscription = QuickBlue.scanResults().listen(results.add);

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    platform.addScanResult('device-a');
    await pumpEventQueue();

    expect(results.single.deviceId, 'device-a');

    await subscription.cancel();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test('observer records scan cancellation and result count', () async {
    final observer = _RecordingObserver();
    QuickBlue.observer = observer;
    final subscription = QuickBlue.scanResults().listen((_) {});

    await pumpEventQueue();
    platform.addScanResult('device-a');
    await pumpEventQueue();
    await subscription.cancel();

    final observed = observer.operations.single;
    expect(observed.start.kind, QuickBlueOperationKind.scan);
    expect(observed.end!.outcome, QuickBlueOperationOutcome.cancelled);
    expect(
      observed.end!.measurements[QuickBlueOperationMeasurement.resultCount],
      1,
    );
  });

  test('scanResults forwards scan options', () async {
    final subscription = QuickBlue.scanResults(
      scanOptions: const ScanOptions(scanMode: ScanMode.balanced),
    ).listen((_) {});

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);
    expect(platform.lastScanOptions!.scanMode, ScanMode.balanced);

    await subscription.cancel();
  });

  test('scan emits BluetoothDevice objects', () async {
    final devices = <BluetoothDevice>[];
    final subscription = QuickBlue.scan().listen(devices.add);

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    platform.addScanResult('device-a');
    await pumpEventQueue();

    expect(devices.single.id, 'device-a');

    await subscription.cancel();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test('scanResults stream is single subscription', () async {
    final stream = QuickBlue.scanResults();
    final subscription = stream.listen((_) {});

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    expect(() => stream.listen((_) {}), throwsStateError);

    await subscription.cancel();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test(
    'notifications waits for setNotifiable before emitting values',
    () async {
      final setNotifiable = Completer<void>();
      platform.nextSetNotifiable = setNotifiable;
      final values = <Uint8List>[];
      final errors = <Object>[];
      final characteristic = QuickBlue.device(
        'device-a',
      ).characteristic('service-a', 'characteristic-a');

      final subscription = characteristic.notifications().listen(
        values.add,
        onError: errors.add,
      );
      await pumpEventQueue();

      platform.handleCharacteristicValueChanged(
        'device-a',
        'service-a',
        'characteristic-a',
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);
      expect(values, isEmpty);
      expect(errors, isEmpty);

      setNotifiable.complete();
      await pumpEventQueue();

      expect(values, <Uint8List>[
        Uint8List.fromList(<int>[1, 2, 3]),
      ]);
      expect(errors, isEmpty);

      await subscription.cancel();
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
    },
  );

  test('legacy companionDissassociate delegates to the platform', () async {
    await QuickBlue.companionDissassociate(42);

    expect(platform.calls, <String>['companionDisassociate 42']);
  });

  test('companionAssociate delegates to the platform', () async {
    platform.companionAssociation = CompanionAssociation(
      id: 42,
      deviceId: 'device-a',
      displayName: 'Device A',
    );

    final device = await QuickBlue.companionAssociate(
      deviceId: 'device-a',
      scanFilter: ScanFilter(serviceUuids: const <String>['180d']),
    );

    expect(
      device,
      // ignore: deprecated_member_use
      CompanionDevice(id: 'device-a', name: 'Device A', associationId: 42),
    );
    expect(platform.calls, <String>['companionAssociate device-a [180d]']);
  });

  test('companionAssociate omits filter when no criteria passed', () async {
    platform.companionAssociation = null;

    final device = await QuickBlue.companionAssociate();

    expect(device, isNull);
    expect(platform.calls, <String>['companionAssociate null []']);
  });

  test(
    'companionAssociate keeps manufacturer data when service UUIDs are empty',
    () async {
      final manufacturerData = <int, Uint8List>{
        76: Uint8List.fromList(<int>[1, 2, 3]),
      };
      platform.companionAssociation = CompanionAssociation(id: 42);

      final device = await QuickBlue.companionAssociate(
        scanFilter: ScanFilter(
          serviceUuids: const <String>[],
          manufacturerData: manufacturerData,
        ),
      );

      expect(
        device,
        // ignore: deprecated_member_use
        CompanionDevice(id: '', name: '', associationId: 42),
      );
      final request = platform.lastCompanionAssociateRequest;
      expect(request, isNotNull);
      expect(
        request!.filters.single,
        BleCompanionFilter(
          serviceUuids: const <String>[],
          manufacturerData: manufacturerData,
        ),
      );
    },
  );

  test('getCompanionAssociations delegates to the platform', () async {
    platform.companionAssociations = <CompanionAssociation>[
      CompanionAssociation(
        id: 42,
        deviceId: 'device-a',
        displayName: 'Device A',
      ),
    ];

    final associations = await QuickBlue.getCompanionAssociations();

    // ignore: deprecated_member_use
    expect(associations, <CompanionDevice>[
      // ignore: deprecated_member_use
      CompanionDevice(id: 'device-a', name: 'Device A', associationId: 42),
    ]);
    expect(platform.calls, <String>['getCompanionAssociations']);
  });

  test(
    'getCompanionAssociations maps missing fields in legacy model',
    () async {
      platform.companionAssociations = <CompanionAssociation>[
        CompanionAssociation(id: 42),
      ];

      final associations = await QuickBlue.getCompanionAssociations();

      // ignore: deprecated_member_use
      expect(associations, <CompanionDevice>[
        // ignore: deprecated_member_use
        CompanionDevice(id: '', name: '', associationId: 42),
      ]);
      expect(platform.calls, <String>['getCompanionAssociations']);
    },
  );

  test('appleAccessorySetup delegates typed operations', () async {
    const accessory = AppleAccessory(
      deviceId: 'device-a',
      displayName: 'Sensor',
    );
    platform
      ..selectedAppleAccessory = accessory
      ..appleAccessories = const <AppleAccessory>[accessory];
    final item = AppleAccessoryPickerItem(
      displayName: 'Sensor',
      productImage: Uint8List.fromList(<int>[1, 2, 3]),
      discovery: AppleAccessoryDiscovery(serviceUuid: '180d'),
    );

    expect(await QuickBlue.appleAccessorySetup.isSupported(), isTrue);
    expect(
      await QuickBlue.appleAccessorySetup.showPicker(<AppleAccessoryPickerItem>[
        item,
      ]),
      accessory,
    );
    expect(await QuickBlue.appleAccessorySetup.accessories(), <AppleAccessory>[
      accessory,
    ]);
    await QuickBlue.appleAccessorySetup.remove('device-a');

    expect(platform.lastAppleAccessoryPickerItems, <AppleAccessoryPickerItem>[
      item,
    ]);
    expect(platform.calls, <String>[
      'isAppleAccessorySetupSupported',
      'showAppleAccessoryPicker',
      'getAppleAccessories',
      'removeAppleAccessory device-a',
    ]);
  });

  test('appleAccessorySetup rejects an empty picker', () {
    expect(
      () => QuickBlue.appleAccessorySetup.showPicker(
        const <AppleAccessoryPickerItem>[],
      ),
      throwsArgumentError,
    );
  });
}

final class _RecordingObserver implements QuickBlueObserver {
  final operations = <_ObservedOperation>[];

  @override
  QuickBlueOperationObservation onOperationStarted(
    QuickBlueOperation operation,
  ) {
    final observed = _ObservedOperation(operation);
    operations.add(observed);
    return _RecordingOperationObservation(observed);
  }
}

final class _ObservedOperation {
  _ObservedOperation(this.start);

  final QuickBlueOperation start;
  QuickBlueOperationEnd? end;
}

final class _RecordingOperationObservation
    implements QuickBlueOperationObservation {
  _RecordingOperationObservation(this.observed);

  final _ObservedOperation observed;

  @override
  void onOperationEnded(QuickBlueOperationEnd operation) {
    observed.end = operation;
  }
}

final class _ThrowingObserver implements QuickBlueObserver {
  _ThrowingObserver({required this.throwOnStart});

  final bool throwOnStart;

  @override
  QuickBlueOperationObservation onOperationStarted(
    QuickBlueOperation operation,
  ) {
    if (throwOnStart) {
      throw StateError('operation start failed');
    }
    return _ThrowingOperationObservation();
  }
}

final class _ThrowingOperationObservation
    implements QuickBlueOperationObservation {
  @override
  void onOperationEnded(QuickBlueOperationEnd operation) {
    throw StateError('operation end failed');
  }
}
