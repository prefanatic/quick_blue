import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:quick_blue_windows/quick_blue_windows.dart';
import 'package:quick_blue_windows/src/messages.g.dart' as messages;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const isBluetoothAvailableChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.isBluetoothAvailable';
  const startScanChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.startScan';
  const stopScanChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.stopScan';
  const connectedDeviceIdsChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.connectedDeviceIds';
  const connectChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.connect';
  const disconnectChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.disconnect';
  const discoverServicesChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.discoverServices';
  const setNotifiableChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.setNotifiable';
  const readValueChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.readValue';
  const requestMtuChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.requestMtu';
  const writeValueChannelName =
      'dev.flutter.pigeon.quick_blue_windows.QuickBlueApi.writeValue';
  const scanResultEventChannelName = 'quick_blue/event.scanResult';

  tearDown(() {
    for (final name in const [
      isBluetoothAvailableChannelName,
      startScanChannelName,
      stopScanChannelName,
      connectedDeviceIdsChannelName,
      connectChannelName,
      disconnectChannelName,
      discoverServicesChannelName,
      setNotifiableChannelName,
      readValueChannelName,
      requestMtuChannelName,
      writeValueChannelName,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            BasicMessageChannel<Object?>(
              name,
              messages.QuickBlueApi.pigeonChannelCodec,
            ),
            null,
          );
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel(scanResultEventChannelName),
          null,
        );
    messages.QuickBlueFlutterApi.setUp(null);
  });

  test('registers as platform implementation', () {
    final previous = QuickBluePlatform.instance;
    try {
      QuickBlueWindows.registerWith();
      expect(QuickBluePlatform.instance, isA<QuickBlueWindows>());
    } finally {
      QuickBluePlatform.instance = previous;
    }
  });

  test('forwards core host API calls', () async {
    final sentMessages = <String, Object?>{};
    for (final name in const [
      isBluetoothAvailableChannelName,
      connectedDeviceIdsChannelName,
      stopScanChannelName,
      connectChannelName,
      disconnectChannelName,
      discoverServicesChannelName,
      setNotifiableChannelName,
      readValueChannelName,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            BasicMessageChannel<Object?>(
              name,
              messages.QuickBlueApi.pigeonChannelCodec,
            ),
            (message) async {
              sentMessages[name] = message;
              if (name == isBluetoothAvailableChannelName) {
                return <Object?>[true];
              }
              if (name == connectedDeviceIdsChannelName) {
                return <Object?>[
                  <String>['device-a'],
                ];
              }
              return <Object?>[null];
            },
          );
    }

    final platform = QuickBlueWindows();

    expect(await platform.isBluetoothAvailable(), isTrue);
    final connectedDevices = await platform.connectedDevices(
      serviceUuids: const <String>['180d'],
    );
    await platform.stopScan();
    await platform.connect('device-a');
    await platform.disconnect('device-a');
    await platform.discoverServices('device-a');
    await platform.setNotifiable(
      'device-a',
      'service-a',
      'characteristic-a',
      BleInputProperty.indication,
    );
    await platform.readValue('device-a', 'service-a', 'characteristic-a');

    expect(sentMessages[isBluetoothAvailableChannelName], isNull);
    expect(sentMessages[connectedDeviceIdsChannelName], <Object?>[
      <String>['180d'],
    ]);
    expect(connectedDevices.map((device) => device.id), <String>['device-a']);
    expect(sentMessages[stopScanChannelName], isNull);
    expect(sentMessages[connectChannelName], <Object?>['device-a']);
    expect(sentMessages[disconnectChannelName], <Object?>['device-a']);
    expect(sentMessages[discoverServicesChannelName], <Object?>['device-a']);
    expect(sentMessages[setNotifiableChannelName], <Object?>[
      'device-a',
      'service-a',
      'characteristic-a',
      messages.PlatformBleInputProperty.indication,
    ]);
    expect(sentMessages[readValueChannelName], <Object?>[
      'device-a',
      'service-a',
      'characteristic-a',
    ]);
  });

  test('unsupported APIs throw QuickBlueException', () async {
    final platform = QuickBlueWindows();

    expect(await platform.isCompanionAssociationSupported(), isFalse);
    expect(
      platform.companionAssociate(CompanionAssociationRequest.ble()),
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.unsupported,
        ),
      ),
    );
    expect(
      () => platform.companionDisassociate(42),
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.unsupported,
        ),
      ),
    );
    expect(
      platform.getCompanionAssociations(),
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.unsupported,
        ),
      ),
    );
    expect(
      () => platform.openL2cap('device-a', 25),
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.unsupported,
        ),
      ),
    );
    expect(
      () => platform.bondState('device-a'),
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.unsupported,
        ),
      ),
    );
    expect(
      () => platform.pair('device-a'),
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.unsupported,
        ),
      ),
    );
  });

  test('maps scan result events', () async {
    final scanEventChannel = const EventChannel(scanResultEventChannelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          scanEventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              events.success(<String, dynamic>{
                'name': 'device-a',
                'deviceId': 'device-a',
                'rssi': -40,
                'manufacturerDataHead': Uint8List.fromList(<int>[1, 2]),
                'manufacturerData': Uint8List.fromList(<int>[3, 4]),
                'serviceUuids': <String>['180d'],
                'serviceData': {
                  '180d': Uint8List.fromList(<int>[7, 8]),
                },
              });
            },
          ),
        );

    await expectLater(
      QuickBlueWindows().scanResultStream,
      emits(
        isA<BlueScanResult>()
            .having((result) => result.name, 'name', 'device-a')
            .having((result) => result.deviceId, 'deviceId', 'device-a')
            .having((result) => result.rssi, 'rssi', -40)
            .having(
              (result) => result.serviceData['180d'],
              'serviceData',
              Uint8List.fromList(<int>[7, 8]),
            ),
      ),
    );
  });

  test('raw scan results apply the active service-data filter', () async {
    const scanEventChannel = EventChannel(scanResultEventChannelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          scanEventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              events
                ..success(<String, dynamic>{
                  'name': 'non-match',
                  'deviceId': 'device-a',
                  'rssi': -40,
                  'manufacturerDataHead': Uint8List(0),
                  'manufacturerData': Uint8List(0),
                  'serviceUuids': <String>[],
                  'serviceData': <String, Uint8List>{
                    '180f': Uint8List.fromList(<int>[1, 2]),
                  },
                })
                ..success(<String, dynamic>{
                  'name': 'match',
                  'deviceId': 'device-b',
                  'rssi': -40,
                  'manufacturerDataHead': Uint8List(0),
                  'manufacturerData': Uint8List(0),
                  'serviceUuids': <String>[],
                  'serviceData': <String, Uint8List>{
                    '0000180a-0000-1000-8000-00805f9b34fb': Uint8List.fromList(
                      <int>[1, 2, 3],
                    ),
                  },
                });
            },
          ),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          const BasicMessageChannel<Object?>(
            startScanChannelName,
            messages.QuickBlueApi.pigeonChannelCodec,
          ),
          (_) async => <Object?>[],
        );

    final platform = QuickBlueWindows();
    await platform.startScan(
      scanFilter: ScanFilter(
        serviceData: <String, Uint8List>{
          '180a': Uint8List.fromList(<int>[1, 2]),
        },
      ),
    );

    await expectLater(
      platform.scanResultStream.take(1),
      emits(
        isA<BlueScanResult>().having(
          (result) => result.deviceId,
          'deviceId',
          'device-b',
        ),
      ),
    );
  });

  test('reuses the scan result event stream', () {
    final platform = QuickBlueWindows();

    expect(platform.scanResultStream, same(platform.scanResultStream));
  });

  test(
    'forwards known connection states and ignores unknown connection states',
    () async {
      const channel = BasicMessageChannel<Object?>(
        isBluetoothAvailableChannelName,
        messages.QuickBlueApi.pigeonChannelCodec,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            channel,
            (_) async => <Object?>[true],
          );

      final platform = QuickBlueWindows();
      await platform.isBluetoothAvailable();

      final connectionEvents = <BluetoothConnectionStateChange>[];
      final subscription = platform.connectionStateStream.listen(
        connectionEvents.add,
      );

      await _sendFlutterApiMessage(
        'onConnectionStateChange',
        messages.PlatformConnectionStateChange(
          deviceId: 'device-a',
          state: messages.PlatformConnectionState.connected,
          gattStatus: messages.PlatformGattStatus.success,
        ),
      );
      await _sendFlutterApiMessage(
        'onConnectionStateChange',
        messages.PlatformConnectionStateChange(
          deviceId: 'device-a',
          state: messages.PlatformConnectionState.unknown,
          gattStatus: messages.PlatformGattStatus.failure,
        ),
      );
      await _sendFlutterApiMessage(
        'onConnectionStateChange',
        messages.PlatformConnectionStateChange(
          deviceId: 'device-a',
          state: messages.PlatformConnectionState.disconnected,
          gattStatus: messages.PlatformGattStatus.failure,
        ),
      );

      await pumpEventQueue();

      expect(connectionEvents, <BluetoothConnectionStateChange>[
        BluetoothConnectionStateChange(
          deviceId: 'device-a',
          state: BlueConnectionState.connected,
          status: BleStatus.success,
        ),
        BluetoothConnectionStateChange(
          deviceId: 'device-a',
          state: BlueConnectionState.disconnected,
          status: BleStatus.failure,
        ),
      ]);

      await subscription.cancel();
    },
  );

  test(
    'startScan forwards non-empty service UUID and manufacturer filters',
    () async {
      Object? sentMessage;
      const channel = BasicMessageChannel<Object?>(
        startScanChannelName,
        messages.QuickBlueApi.pigeonChannelCodec,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, (message) async {
            sentMessage = message;
            return <Object?>[];
          });

      final manufacturerData = <int, Uint8List>{
        76: Uint8List.fromList(<int>[1, 2, 3]),
      };

      await QuickBlueWindows().startScan(
        scanFilter: ScanFilter(
          serviceUuids: const <String>['180d'],
          manufacturerData: manufacturerData,
        ),
      );

      final message = sentMessage as List<Object?>;
      expect(message[0], <String>['180d']);
      expect(message[1], manufacturerData);
      expect(message[2], isNull);
      final options = message[3] as messages.PlatformWindowsScanOptions;
      expect(options.scanningMode, isNull);
      expect(options.signalStrengthFilter, isNull);
    },
  );

  test('startScan forwards Windows scan options', () async {
    Object? sentMessage;
    const channel = BasicMessageChannel<Object?>(
      startScanChannelName,
      messages.QuickBlueApi.pigeonChannelCodec,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (message) async {
          sentMessage = message;
          return <Object?>[];
        });

    await QuickBlueWindows().startScan(
      scanOptions: const ScanOptions(
        windows: WindowsScanOptions(
          scanningMode: WindowsScanMode.active,
          signalStrengthFilter: WindowsSignalStrengthFilter(
            inRangeThresholdInDBm: -65,
            outOfRangeThresholdInDBm: -75,
            outOfRangeTimeout: Duration(seconds: 3),
            samplingInterval: Duration(milliseconds: 500),
          ),
        ),
      ),
    );

    final message = sentMessage as List<Object?>;
    expect(message[2], isNull);
    final options = message[3] as messages.PlatformWindowsScanOptions;
    expect(options.scanningMode, messages.PlatformWindowsScanMode.active);
    expect(options.signalStrengthFilter!.inRangeThresholdInDBm, -65);
    expect(options.signalStrengthFilter!.outOfRangeThresholdInDBm, -75);
    expect(options.signalStrengthFilter!.outOfRangeTimeoutMillis, 3000);
    expect(options.signalStrengthFilter!.samplingIntervalMillis, 500);
  });

  test('startScan maps common scan options for Windows', () async {
    Object? sentMessage;
    const channel = BasicMessageChannel<Object?>(
      startScanChannelName,
      messages.QuickBlueApi.pigeonChannelCodec,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (message) async {
          sentMessage = message;
          return <Object?>[];
        });

    await QuickBlueWindows().startScan(
      scanFilter: ScanFilter(rssi: -70),
      scanOptions: const ScanOptions(scanMode: ScanMode.lowLatency),
    );

    final message = sentMessage as List<Object?>;
    expect(message[2], -70);
    final options = message[3] as messages.PlatformWindowsScanOptions;
    expect(options.scanningMode, messages.PlatformWindowsScanMode.active);
    expect(options.signalStrengthFilter!.inRangeThresholdInDBm, -70);
  });

  test(
    'requestMtu forwards the device and returns the negotiated MTU',
    () async {
      Object? sentMessage;
      const channel = BasicMessageChannel<Object?>(
        requestMtuChannelName,
        messages.QuickBlueApi.pigeonChannelCodec,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, (message) async {
            sentMessage = message;
            return <Object?>[247];
          });

      final mtu = await QuickBlueWindows().requestMtu('device-a', 512);

      expect(sentMessage, <Object?>['device-a', 512]);
      expect(mtu, 247);
    },
  );

  test('writeValue completes when the host replies with success', () async {
    Object? sentMessage;
    const channel = BasicMessageChannel<Object?>(
      writeValueChannelName,
      messages.QuickBlueApi.pigeonChannelCodec,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (message) async {
          sentMessage = message;
          return <Object?>[null];
        });

    final value = Uint8List.fromList(<int>[0xab, 0xcd]);
    await QuickBlueWindows().writeValue(
      'device-a',
      '180d',
      '2a37',
      value,
      BleOutputProperty.withResponse,
    );

    expect(sentMessage, <Object?>[
      'device-a',
      '180d',
      '2a37',
      value,
      messages.PlatformBleOutputProperty.withResponse,
    ]);
  });

  test('flutter API callbacks surface shared event streams', () async {
    const channel = BasicMessageChannel<Object?>(
      isBluetoothAvailableChannelName,
      messages.QuickBlueApi.pigeonChannelCodec,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          channel,
          (_) async => <Object?>[true],
        );

    final platform = QuickBlueWindows();
    await platform.isBluetoothAvailable();

    final connection = platform.connectionStateStream.first;
    final service = platform.serviceDiscoveryStream.first;
    final serviceComplete = platform.serviceDiscoveryCompleteStream.first;
    final value = platform.characteristicValueStream.first;

    await _sendFlutterApiMessage(
      'onConnectionStateChange',
      messages.PlatformConnectionStateChange(
        deviceId: 'device-a',
        state: messages.PlatformConnectionState.connected,
        gattStatus: messages.PlatformGattStatus.success,
      ),
    );
    await _sendFlutterApiMessage(
      'onServiceDiscovered',
      messages.PlatformServiceDiscovered(
        deviceId: 'device-a',
        serviceUuid: 'service-a',
        characteristics: <messages.PlatformCharacteristic>[
          messages.PlatformCharacteristic(
            uuid: 'characteristic-a',
            canRead: true,
            canWriteWithResponse: false,
            canWriteWithoutResponse: true,
            canNotify: true,
            canIndicate: false,
          ),
        ],
      ),
    );
    await _sendFlutterApiMessage('onServiceDiscoveryComplete', 'device-a');
    await _sendFlutterApiMessage(
      'onCharacteristicValueChanged',
      messages.PlatformCharacteristicValueChanged(
        deviceId: 'device-a',
        serviceUuid: 'service-a',
        characteristicId: 'characteristic-a',
        value: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );

    expect(
      await connection,
      BluetoothConnectionStateChange(
        deviceId: 'device-a',
        state: BlueConnectionState.connected,
        status: BleStatus.success,
      ),
    );
    expect(
      await service,
      BluetoothService(
        deviceId: 'device-a',
        uuid: 'service-a',
        characteristics: const <String>['characteristic-a'],
        characteristicDetails: <BluetoothCharacteristicInfo>[
          BluetoothCharacteristicInfo(
            uuid: 'characteristic-a',
            canRead: true,
            canWriteWithoutResponse: true,
            canNotify: true,
          ),
        ],
      ),
    );
    expect(await serviceComplete, 'device-a');
    expect(
      await value,
      BluetoothCharacteristicValue(
        deviceId: 'device-a',
        serviceId: 'service-a',
        characteristicId: 'characteristic-a',
        value: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );
  });
}

Future<void> _sendFlutterApiMessage(String method, Object argument) async {
  final data = messages.QuickBlueFlutterApi.pigeonChannelCodec.encodeMessage(
    <Object?>[argument],
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'dev.flutter.pigeon.quick_blue_windows.QuickBlueFlutterApi.$method',
        data,
        (_) {},
      );
  await pumpEventQueue();
}
