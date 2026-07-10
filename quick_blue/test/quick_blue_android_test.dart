import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:quick_blue/src/messages.g.dart' as messages;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channels = <String>[
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.isBluetoothAvailable',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.startScan',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.stopScan',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.connectedDeviceIds',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.connect',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.disconnect',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.bondState',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.pair',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.isCompanionAssociationSupported',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.companionAssociate',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.companionDisassociate',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.getCompanionAssociations',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.discoverServices',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.setNotifiable',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.readValue',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.writeValue',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.requestMtu',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.openL2cap',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.closeL2cap',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.writeL2cap',
  ];

  const eventChannels = <String>[
    'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.bluetoothState',
    'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.bondStateChanges',
    'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.scanResults',
    'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.mtuChanged',
    'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.l2CapSocketEvents',
  ];
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    for (final name in channels) {
      binaryMessenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(
          name,
          messages.QuickBlueApi.pigeonChannelCodec,
        ),
        null,
      );
    }
    for (final name in eventChannels) {
      binaryMessenger.setMockMessageHandler(name, null);
    }
    messages.QuickBlueFlutterApi.setUp(null);
  });

  group(QuickBlueAndroid, () {
    test('registers as platform implementation', () {
      final previous = QuickBluePlatform.instance;
      try {
        QuickBlueAndroid.registerWith();
        expect(QuickBluePlatform.instance, isA<QuickBlueAndroid>());
      } finally {
        QuickBluePlatform.instance = previous;
      }
    });

    test('forwards core host API calls', () async {
      final sentMessages = <String, Object?>{};
      for (final name in channels) {
        binaryMessenger.setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>(
            name,
            messages.QuickBlueApi.pigeonChannelCodec,
          ),
          (message) async {
            sentMessages[name] = message;
            return _replyFor(name);
          },
        );
      }

      final platform = QuickBlueAndroid();
      final value = Uint8List.fromList(<int>[1, 2, 3]);
      final manufacturerData = <int, Uint8List>{76: value};

      expect(await platform.isBluetoothAvailable(), isTrue);
      await platform.startScan(
        scanFilter: ScanFilter(
          serviceUuids: const <String>['180d'],
          manufacturerData: manufacturerData,
        ),
      );
      await platform.stopScan();
      final connectedDevices = await platform.connectedDevices(
        serviceUuids: const <String>['180d'],
      );
      await platform.connect('device-a');
      await platform.disconnect('device-a');
      expect(await platform.bondState('device-a'), BluetoothBondState.bonded);
      await platform.pair('device-a');
      await platform.discoverServices('device-a');
      await platform.setNotifiable(
        'device-a',
        'service-a',
        'characteristic-a',
        BleInputProperty.indication,
      );
      final readValue = await platform.readCharacteristicValue(
        'device-a',
        'service-a',
        'characteristic-a',
      );
      await platform.writeValue(
        'device-a',
        'service-a',
        'characteristic-a',
        value,
        BleOutputProperty.withoutResponse,
      );
      expect(await platform.requestMtu('device-a', 512), 247);
      expect(readValue, Uint8List.fromList(<int>[4, 5, 6]));

      final startScanMessage =
          sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.startScan']
              as List<Object?>;
      expect(startScanMessage[0], <String>['180d']);
      expect(startScanMessage[1], manufacturerData);
      expect(startScanMessage[2], isNull);
      final scanOptions =
          startScanMessage[3] as messages.PlatformAndroidScanOptions;
      expect(scanOptions.scanMode, messages.PlatformAndroidScanMode.lowLatency);
      expect(
        scanOptions.callbackType,
        messages.PlatformAndroidScanCallbackType.allMatches,
      );
      expect(
        scanOptions.matchMode,
        messages.PlatformAndroidScanMatchMode.sticky,
      );
      expect(scanOptions.reportDelayMillis, 0);
      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.connectedDeviceIds'],
        <Object?>[
          <String>['180d'],
        ],
      );
      expect(connectedDevices.map((device) => device.id), <String>['device-a']);
      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.connect'],
        <Object?>['device-a'],
      );
      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.bondState'],
        <Object?>['device-a'],
      );
      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.pair'],
        <Object?>['device-a'],
      );
      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.setNotifiable'],
        <Object?>[
          'device-a',
          'service-a',
          'characteristic-a',
          messages.PlatformBleInputProperty.indication,
        ],
      );
      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.writeValue'],
        <Object?>[
          'device-a',
          'service-a',
          'characteristic-a',
          value,
          messages.PlatformBleOutputProperty.withoutResponse,
        ],
      );
      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.readValue'],
        <Object?>['device-a', 'service-a', 'characteristic-a'],
      );
      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.requestMtu'],
        <Object?>['device-a', 512],
      );
    });

    test('read surfaces structured numeric GATT failures', () async {
      binaryMessenger.setMockDecodedMessageHandler<Object?>(
        const BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.quick_blue.QuickBlueApi.readValue',
          messages.QuickBlueApi.pigeonChannelCodec,
        ),
        (_) async => <Object?>[
          'GattError',
          'Characteristic read failed with GATT status 5',
          5,
        ],
      );

      final platform = QuickBlueAndroid();

      await expectLater(
        platform.readCharacteristicValue(
          'device-a',
          'service-a',
          'characteristic-a',
        ),
        throwsA(
          isA<QuickBlueGattException>()
              .having((error) => error.status, 'status', 5)
              .having((error) => error.operation, 'operation', 'readValue')
              .having((error) => error.deviceId, 'deviceId', 'device-a')
              .having((error) => error.serviceId, 'serviceId', 'service-a')
              .having(
                (error) => error.characteristicId,
                'characteristicId',
                'characteristic-a',
              ),
        ),
      );
    });

    test('read returns native bytes and publishes the value event', () async {
      final expected = Uint8List.fromList(<int>[7, 8, 9]);
      binaryMessenger.setMockDecodedMessageHandler<Object?>(
        const BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.quick_blue.QuickBlueApi.readValue',
          messages.QuickBlueApi.pigeonChannelCodec,
        ),
        (_) async => <Object?>[expected],
      );

      final platform = QuickBlueAndroid();
      final valueEvent = platform.characteristicValueStream.first;

      final value = await platform.readCharacteristicValue(
        'device-a',
        'service-a',
        'characteristic-a',
      );

      expect(value, expected);
      expect(
        await valueEvent,
        BluetoothCharacteristicValue(
          deviceId: 'device-a',
          serviceId: 'service-a',
          characteristicId: 'characteristic-a',
          value: expected,
        ),
      );
    });

    test('write surfaces structured numeric GATT failures', () async {
      binaryMessenger.setMockDecodedMessageHandler<Object?>(
        const BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.quick_blue.QuickBlueApi.writeValue',
          messages.QuickBlueApi.pigeonChannelCodec,
        ),
        (_) async => <Object?>[
          'GattError',
          'Characteristic write failed with GATT status 133',
          133,
        ],
      );

      await expectLater(
        QuickBlueAndroid().writeValue(
          'device-a',
          'service-a',
          'characteristic-a',
          Uint8List.fromList(<int>[1]),
          BleOutputProperty.withResponse,
        ),
        throwsA(
          isA<QuickBlueGattException>()
              .having((error) => error.status, 'status', 133)
              .having((error) => error.operation, 'operation', 'writeValue'),
        ),
      );
    });

    test('startScan forwards Android scan options', () async {
      Object? sentMessage;
      binaryMessenger.setMockDecodedMessageHandler<Object?>(
        const BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.quick_blue.QuickBlueApi.startScan',
          messages.QuickBlueApi.pigeonChannelCodec,
        ),
        (message) async {
          sentMessage = message;
          return <Object?>[];
        },
      );

      await QuickBlueAndroid().startScan(
        scanFilter: ScanFilter(rssi: -70),
        scanOptions: const ScanOptions(
          scanMode: ScanMode.balanced,
          android: AndroidScanOptions(
            callbackType: AndroidScanCallbackType.firstMatchAndMatchLost,
            matchMode: AndroidScanMatchMode.aggressive,
            numOfMatches: AndroidScanNumOfMatches.few,
            reportDelay: Duration(seconds: 2),
            legacy: true,
            phy: AndroidScanPhy.leCoded,
          ),
        ),
      );

      final message = sentMessage as List<Object?>;
      expect(message[2], -70);
      final options = message[3] as messages.PlatformAndroidScanOptions;
      expect(options.scanMode, messages.PlatformAndroidScanMode.balanced);
      expect(
        options.callbackType,
        messages.PlatformAndroidScanCallbackType.firstMatchAndMatchLost,
      );
      expect(
        options.matchMode,
        messages.PlatformAndroidScanMatchMode.aggressive,
      );
      expect(
        options.numOfMatches,
        messages.PlatformAndroidScanNumOfMatches.few,
      );
      expect(options.reportDelayMillis, 2000);
      expect(options.legacy, isTrue);
      expect(options.phy, messages.PlatformAndroidScanPhy.leCoded);
    });

    test('maps bluetooth state events', () async {
      _mockEventChannel(
        'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.bluetoothState',
        <Object?>[
          messages.PlatformBluetoothState.unknown,
          messages.PlatformBluetoothState.unavailable,
          messages.PlatformBluetoothState.unauthorized,
          messages.PlatformBluetoothState.poweredOff,
          messages.PlatformBluetoothState.poweredOn,
        ],
      );

      final platform = QuickBlueAndroid();

      await expectLater(
        platform.bluetoothStateStream.take(5),
        emitsInOrder(const <BlueBluetoothState>[
          BlueBluetoothState.unknown,
          BlueBluetoothState.unavailable,
          BlueBluetoothState.unauthorized,
          BlueBluetoothState.poweredOff,
          BlueBluetoothState.poweredOn,
        ]),
      );
    });

    test('maps bond state events', () async {
      _mockEventChannel(
        'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.bondStateChanges',
        <Object?>[
          messages.PlatformBondStateChange(
            deviceId: 'device-a',
            state: messages.PlatformBondState.bonding,
            previousState: messages.PlatformBondState.notBonded,
          ),
          messages.PlatformBondStateChange(
            deviceId: 'device-a',
            state: messages.PlatformBondState.bonded,
            previousState: messages.PlatformBondState.bonding,
          ),
        ],
      );

      await expectLater(
        QuickBlueAndroid().bondStateStream,
        emitsInOrder(const <BluetoothBondStateChange>[
          BluetoothBondStateChange(
            deviceId: 'device-a',
            state: BluetoothBondState.bonding,
            previousState: BluetoothBondState.notBonded,
          ),
          BluetoothBondStateChange(
            deviceId: 'device-a',
            state: BluetoothBondState.bonded,
            previousState: BluetoothBondState.bonding,
          ),
        ]),
      );
    });

    test('maps scan result events', () async {
      _mockEventChannel(
        'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.scanResults',
        <Object?>[
          messages.PlatformScanResult(
            name: 'name',
            deviceId: 'device-a',
            manufacturerDataHead: Uint8List.fromList(<int>[1, 2, 3]),
            manufacturerData: Uint8List.fromList(<int>[4, 5, 6]),
            rssi: -40,
            serviceUuids: const <String>['180d'],
            serviceData: {
              '180d': Uint8List.fromList(<int>[7, 8]),
            },
          ),
        ],
      );

      final platform = QuickBlueAndroid();

      await expectLater(
        platform.scanResultStream.take(1),
        emits(
          isA<BlueScanResult>()
              .having((result) => result.name, 'name', 'name')
              .having((result) => result.deviceId, 'deviceId', 'device-a')
              .having((result) => result.rssi, 'rssi', -40)
              .having(
                (result) => result.serviceData['180d'],
                'serviceData',
                Uint8List.fromList(<int>[7, 8]),
              )
              .having(
                (result) => result.serviceUuids,
                'serviceUuids',
                contains('180d'),
              ),
        ),
      );
    });

    test('reuses the scan result event stream', () {
      final platform = QuickBlueAndroid();

      expect(platform.scanResultStream, same(platform.scanResultStream));
    });

    test('maps companion host API results', () async {
      final sentMessages = <String, Object?>{};
      for (final name in const <String>[
        'dev.flutter.pigeon.quick_blue.QuickBlueApi.isCompanionAssociationSupported',
        'dev.flutter.pigeon.quick_blue.QuickBlueApi.companionAssociate',
        'dev.flutter.pigeon.quick_blue.QuickBlueApi.companionDisassociate',
        'dev.flutter.pigeon.quick_blue.QuickBlueApi.getCompanionAssociations',
      ]) {
        binaryMessenger.setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>(
            name,
            messages.QuickBlueApi.pigeonChannelCodec,
          ),
          (message) async {
            sentMessages[name] = message;
            return _replyFor(name);
          },
        );
      }

      final platform = QuickBlueAndroid();
      final filter = BleCompanionFilter(
        deviceId: 'device-a',
        serviceUuids: const <String>['180d'],
        manufacturerData: <int, Uint8List>{
          76: Uint8List.fromList(<int>[1, 2, 3]),
        },
      );

      expect(await platform.isCompanionAssociationSupported(), isTrue);
      expect(
        await platform.companionAssociate(
          CompanionAssociationRequest.ble(
            filters: <BleCompanionFilter>[filter],
          ),
        ),
        CompanionAssociation(
          id: 42,
          deviceId: 'device-a',
          displayName: 'Device A',
        ),
      );
      await platform.companionDisassociate(42);
      expect(await platform.getCompanionAssociations(), <CompanionAssociation>[
        CompanionAssociation(
          id: 42,
          deviceId: 'device-a',
          displayName: 'Device A',
        ),
      ]);

      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.isCompanionAssociationSupported'],
        isNull,
      );
      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.companionAssociate'],
        <Object?>[
          messages.PlatformCompanionAssociationRequest(
            filters: <messages.PlatformBleCompanionFilter>[
              messages.PlatformBleCompanionFilter(
                deviceId: 'device-a',
                namePattern: null,
                serviceUuids: <String>['180d'],
                manufacturerData: <int, Uint8List>{
                  76: Uint8List.fromList(<int>[1, 2, 3]),
                },
              ),
            ],
            singleDevice: true,
          ),
        ],
      );
      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.companionDisassociate'],
        <Object?>[42],
      );
    });

    test('flutter API callbacks surface shared event streams', () async {
      final platform = QuickBlueAndroid();
      binaryMessenger.setMockDecodedMessageHandler<Object?>(
        const BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.quick_blue.QuickBlueApi.isBluetoothAvailable',
          messages.QuickBlueApi.pigeonChannelCodec,
        ),
        (_) async => <Object?>[true],
      );

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

    test(
      'forwards known connection states and ignores unknown connection states',
      () async {
        final platform = QuickBlueAndroid();
        binaryMessenger.setMockDecodedMessageHandler<Object?>(
          const BasicMessageChannel<Object?>(
            'dev.flutter.pigeon.quick_blue.QuickBlueApi.isBluetoothAvailable',
            messages.QuickBlueApi.pigeonChannelCodec,
          ),
          (_) async => <Object?>[true],
        );

        final connectionEvents = <BluetoothConnectionStateChange>[];
        final subscription = platform.connectionStateStream.listen(
          connectionEvents.add,
        );

        await platform.isBluetoothAvailable();

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
      _mockEventChannel(
        'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.l2CapSocketEvents',
        <Object?>[
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
        ],
      );

      final sentMessages = <String, Object?>{};
      final writeChannel =
          'dev.flutter.pigeon.quick_blue.QuickBlueApi.writeL2cap';
      binaryMessenger.setMockDecodedMessageHandler<Object?>(
        const BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.quick_blue.QuickBlueApi.openL2cap',
          messages.QuickBlueApi.pigeonChannelCodec,
        ),
        (message) async =>
            _replyFor('dev.flutter.pigeon.quick_blue.QuickBlueApi.openL2cap'),
      );
      binaryMessenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(
          writeChannel,
          messages.QuickBlueApi.pigeonChannelCodec,
        ),
        (message) async {
          sentMessages[writeChannel] = message;
          return _replyFor(writeChannel);
        },
      );

      final platform = QuickBlueAndroid();
      final socket = await platform.openL2cap('device-a', 25);

      await expectLater(
        socket.stream.take(4),
        emitsInOrder(<Matcher>[
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

      expect(sentMessages[writeChannel], <Object?>[
        'device-a',
        Uint8List.fromList(<int>[3, 4]),
      ]);
    });

    test('emits stream error for malformed L2CAP events', () async {
      _mockEventChannel(
        'dev.flutter.pigeon.quick_blue.QuickBlueEventApi.l2CapSocketEvents',
        <Object?>[messages.PlatformL2CapSocketEvent(deviceId: 'device-a')],
      );
      binaryMessenger.setMockDecodedMessageHandler<Object?>(
        const BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.quick_blue.QuickBlueApi.openL2cap',
          messages.QuickBlueApi.pigeonChannelCodec,
        ),
        (message) async =>
            _replyFor('dev.flutter.pigeon.quick_blue.QuickBlueApi.openL2cap'),
      );

      final platform = QuickBlueAndroid();
      final socket = await platform.openL2cap('device-a', 25);

      await expectLater(
        socket.stream,
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
  });
}

Object _replyFor(String channelName) {
  if (channelName.endsWith('.isBluetoothAvailable')) {
    return <Object?>[true];
  }
  if (channelName.endsWith('.isCompanionAssociationSupported')) {
    return <Object?>[true];
  }
  if (channelName.endsWith('.companionAssociate')) {
    return <Object?>[
      messages.PlatformCompanionAssociation(
        id: 42,
        deviceId: 'device-a',
        displayName: 'Device A',
        deviceProfile: null,
      ),
    ];
  }
  if (channelName.endsWith('.getCompanionAssociations')) {
    return <Object?>[
      <messages.PlatformCompanionAssociation>[
        messages.PlatformCompanionAssociation(
          id: 42,
          deviceId: 'device-a',
          displayName: 'Device A',
          deviceProfile: null,
        ),
      ],
    ];
  }
  if (channelName.endsWith('.connectedDeviceIds')) {
    return <Object?>[
      <String>['device-a'],
    ];
  }
  if (channelName.endsWith('.bondState')) {
    return <Object?>[messages.PlatformBondState.bonded];
  }
  if (channelName.endsWith('.readValue')) {
    return <Object?>[
      Uint8List.fromList(<int>[4, 5, 6]),
    ];
  }
  if (channelName.endsWith('.requestMtu')) {
    return <Object?>[247];
  }
  if (channelName.endsWith('.openL2cap') ||
      channelName.endsWith('.closeL2cap') ||
      channelName.endsWith('.writeL2cap')) {
    return <Object?>[null];
  }
  return <Object?>[null];
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

Future<void> _sendFlutterApiMessage(String method, Object argument) async {
  final data = messages.QuickBlueFlutterApi.pigeonChannelCodec.encodeMessage(
    <Object?>[argument],
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'dev.flutter.pigeon.quick_blue.QuickBlueFlutterApi.$method',
        data,
        (_) {},
      );
  await pumpEventQueue();
}
