import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_darwin/quick_blue_darwin.dart';
import 'package:quick_blue_darwin/src/messages.g.dart' as messages;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const isBluetoothAvailableChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.isBluetoothAvailable';
  const startScanChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.startScan';
  const stopScanChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.stopScan';
  const getConnectedPeripheralsChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.getConnectedPeripherals';
  const connectChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.connect';
  const disconnectChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.disconnect';
  const discoverServicesChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.discoverServices';
  const setNotifiableChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.setNotifiable';
  const readValueChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.readValue';
  const requestMtuChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.requestMtu';
  const writeValueChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.writeValue';
  const bluetoothStateChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueEventApi.bluetoothState';
  const scanResultChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueEventApi.scanResults';
  const l2capSocketEventsChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueEventApi.l2CapSocketEvents';
  const openL2capChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.openL2cap';
  const writeL2capChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.writeL2cap';

  tearDown(() {
    for (final name in const [
      isBluetoothAvailableChannelName,
      startScanChannelName,
      stopScanChannelName,
      getConnectedPeripheralsChannelName,
      connectChannelName,
      disconnectChannelName,
      discoverServicesChannelName,
      setNotifiableChannelName,
      readValueChannelName,
      requestMtuChannelName,
      writeValueChannelName,
      openL2capChannelName,
      writeL2capChannelName,
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
    for (final name in const [
      bluetoothStateChannelName,
      scanResultChannelName,
      l2capSocketEventsChannelName,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(name, null);
    }
    messages.QuickBlueFlutterApi.setUp(null);
  });

  test('registers as platform implementation', () {
    final previous = QuickBluePlatform.instance;
    try {
      QuickBlueDarwin.registerWith();
      expect(QuickBluePlatform.instance, isA<QuickBlueDarwin>());
    } finally {
      QuickBluePlatform.instance = previous;
    }
  });

  test('forwards core host API calls', () async {
    final sentMessages = <String, Object?>{};
    for (final name in const [
      isBluetoothAvailableChannelName,
      getConnectedPeripheralsChannelName,
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
              if (name == getConnectedPeripheralsChannelName) {
                return <Object?>[
                  <messages.Peripheral>[
                    messages.Peripheral(id: 'device-a', name: 'Device A'),
                  ],
                ];
              }
              return <Object?>[null];
            },
          );
    }

    final platform = QuickBlueDarwin();

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
    expect(sentMessages[getConnectedPeripheralsChannelName], <Object?>[
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

  test('companion APIs throw QuickBlueException', () async {
    final platform = QuickBlueDarwin();

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
  });

  test('maps bluetooth state events', () async {
    _mockEventChannel(bluetoothStateChannelName, <Object?>[
      messages.PlatformBluetoothState.unknown,
      messages.PlatformBluetoothState.unavailable,
      messages.PlatformBluetoothState.unauthorized,
      messages.PlatformBluetoothState.poweredOff,
      messages.PlatformBluetoothState.poweredOn,
    ]);

    await expectLater(
      QuickBlueDarwin().bluetoothStateStream.take(5),
      emitsInOrder(const <BlueBluetoothState>[
        BlueBluetoothState.unknown,
        BlueBluetoothState.unavailable,
        BlueBluetoothState.unauthorized,
        BlueBluetoothState.poweredOff,
        BlueBluetoothState.poweredOn,
      ]),
    );
  });

  test('maps scan result events', () async {
    _mockEventChannel(scanResultChannelName, <Object?>[
      messages.PlatformScanResult(
        name: 'device-a',
        deviceId: 'device-a',
        manufacturerDataHead: Uint8List.fromList(<int>[1, 2]),
        manufacturerData: Uint8List.fromList(<int>[3, 4]),
        rssi: -40,
        serviceUuids: const <String>['180d'],
        serviceData: {
          '180d': Uint8List.fromList(<int>[7, 8]),
        },
      ),
    ]);

    await expectLater(
      QuickBlueDarwin().scanResultStream.take(1),
      emits(
        isA<BlueScanResult>()
            .having((result) => result.name, 'name', 'device-a')
            .having((result) => result.deviceId, 'deviceId', 'device-a')
            .having((result) => result.rssi, 'rssi', -40)
            .having(
              (result) => result.serviceData['180d'],
              'serviceData',
              Uint8List.fromList(<int>[7, 8]),
            )
            .having((result) => result.serviceUuids, 'serviceUuids', ['180d']),
      ),
    );
  });

  test('startScan sends null filters for an unfiltered scan', () async {
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

    await QuickBlueDarwin().startScan();

    final message = sentMessage as List<Object?>;
    expect(message[0], isNull);
    expect(message[1], isNull);
    expect(message[2], isNull);
    final options = message[3] as messages.PlatformDarwinScanOptions;
    expect(options.allowDuplicates, isTrue);
    expect(options.solicitedServiceUuids, isEmpty);
  });

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

      await QuickBlueDarwin().startScan(
        scanFilter: ScanFilter(
          serviceUuids: const <String>['180d'],
          manufacturerData: manufacturerData,
        ),
      );

      final message = sentMessage as List<Object?>;
      expect(message[0], <String>['180d']);
      expect(message[1], manufacturerData);
      expect(message[2], isNull);
      final options = message[3] as messages.PlatformDarwinScanOptions;
      expect(options.allowDuplicates, isTrue);
      expect(options.solicitedServiceUuids, isEmpty);
    },
  );

  test('startScan forwards Darwin scan options', () async {
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

    await QuickBlueDarwin().startScan(
      scanOptions: ScanOptions(
        allowDuplicates: false,
        darwin: DarwinScanOptions(
          solicitedServiceUuids: const <String>['180f'],
        ),
      ),
    );

    final message = sentMessage as List<Object?>;
    expect(message[2], isNull);
    final options = message[3] as messages.PlatformDarwinScanOptions;
    expect(options.allowDuplicates, isFalse);
    expect(options.solicitedServiceUuids, <String>['180f']);
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

      final mtu = await QuickBlueDarwin().requestMtu('device-a', 512);

      expect(sentMessage, <Object?>['device-a', 512]);
      expect(mtu, 247);
    },
  );

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

      final platform = QuickBlueDarwin();
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

  test('maps L2CAP socket events and forwards socket writes', () async {
    _mockEventChannel(l2capSocketEventsChannelName, <Object?>[
      messages.PlatformL2CapSocketEvent(
        deviceId: 'device-a',
        data: Uint8List.fromList(<int>[1, 2]),
      ),
      messages.PlatformL2CapSocketEvent(
        deviceId: 'other-device',
        error: 'ignored',
      ),
      messages.PlatformL2CapSocketEvent(
        deviceId: 'device-a',
        error: 'read-failed',
      ),
      messages.PlatformL2CapSocketEvent(deviceId: 'device-a', opened: true),
      messages.PlatformL2CapSocketEvent(deviceId: 'device-a', closed: true),
    ]);

    final sentMessages = <String, Object?>{};
    const writeL2capMessage = BasicMessageChannel<Object?>(
      writeL2capChannelName,
      messages.QuickBlueApi.pigeonChannelCodec,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(writeL2capMessage, (
          message,
        ) async {
          sentMessages[writeL2capChannelName] = message;
          return <Object?>[null];
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          const BasicMessageChannel<Object?>(
            openL2capChannelName,
            messages.QuickBlueApi.pigeonChannelCodec,
          ),
          (_) async => <Object?>[null],
        );

    final platform = QuickBlueDarwin();
    final socket = await platform.openL2cap('device-a', 25);

    await expectLater(
      socket.stream.take(4),
      emitsInAnyOrder(<Matcher>[
        isA<BleL2CapSocketEventData>()
            .having((event) => event.deviceId, 'deviceId', 'device-a')
            .having(
              (event) => event.data,
              'data',
              Uint8List.fromList(<int>[1, 2]),
            ),
        isA<BleL2CapSocketEventError>()
            .having((event) => event.deviceId, 'deviceId', 'device-a')
            .having((event) => event.error, 'error', 'read-failed'),
        isA<BleL2CapSocketEventOpened>().having(
          (event) => event.deviceId,
          'deviceId',
          'device-a',
        ),
        isA<BleL2CapSocketEventClosed>().having(
          (event) => event.deviceId,
          'deviceId',
          'device-a',
        ),
      ]),
    );

    socket.sink.add(Uint8List.fromList(<int>[3, 4]));
    socket.sink.addError(Exception('ignored'));
    socket.sink.close();
    await pumpEventQueue();

    expect(sentMessages[writeL2capChannelName], <Object?>[
      'device-a',
      Uint8List.fromList(<int>[3, 4]),
    ]);
  });

  test('emits stream error for malformed L2CAP events', () async {
    _mockEventChannel(l2capSocketEventsChannelName, <Object?>[
      messages.PlatformL2CapSocketEvent(deviceId: 'device-a', opened: true),
      messages.PlatformL2CapSocketEvent(deviceId: 'device-a'),
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          const BasicMessageChannel<Object?>(
            openL2capChannelName,
            messages.QuickBlueApi.pigeonChannelCodec,
          ),
          (_) async => <Object?>[null],
        );

    final platform = QuickBlueDarwin();
    final socket = await platform.openL2cap('device-a', 25);

    await expectLater(
      socket.stream.skip(1),
      emitsError(
        isA<QuickBlueException>()
            .having(
              (error) => error.code,
              'code',
              QuickBlueErrorCode.invalidState,
            )
            .having(
              (error) => error.message,
              'message',
              'Unknown L2CAP event.',
            ),
      ),
    );
  });

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
    await QuickBlueDarwin().writeValue(
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

  test('writeValue throws when the host replies with an error', () async {
    const channel = BasicMessageChannel<Object?>(
      writeValueChannelName,
      messages.QuickBlueApi.pigeonChannelCodec,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (message) async {
          return <Object?>['WriteFailed', 'boom', null];
        });

    expect(
      QuickBlueDarwin().writeValue(
        'device-a',
        '180d',
        '2a37',
        Uint8List.fromList(<int>[0x01]),
        BleOutputProperty.withResponse,
      ),
      throwsA(isA<PlatformException>()),
    );
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

    final platform = QuickBlueDarwin();
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
        'dev.flutter.pigeon.quick_blue_darwin.QuickBlueFlutterApi.$method',
        data,
        (_) {},
      );
  await pumpEventQueue();
}

void _mockEventChannel(String channelName, List<Object?> events) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(channelName, (ByteData? message) async {
        if (message == null) {
          return null;
        }

        final methodCall = messages.pigeonMethodCodec.decodeMethodCall(message);
        if (methodCall.method == 'listen') {
          for (final event in events) {
            await TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .handlePlatformMessage(
                  channelName,
                  messages.pigeonMethodCodec.encodeSuccessEnvelope(event),
                  (_) {},
                );
          }
          return messages.pigeonMethodCodec.encodeSuccessEnvelope(null);
        }

        if (methodCall.method == 'cancel') {
          return messages.pigeonMethodCodec.encodeSuccessEnvelope(null);
        }

        fail('Unexpected method call for $channelName: ${methodCall.method}');
      });
}
