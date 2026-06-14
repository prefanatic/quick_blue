import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/quick_blue.dart';
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
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.isCompanionAssociationSupported',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.companionAssociate',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.companionDisassociate',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.getCompanionAssociations',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.discoverServices',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.setNotifiable',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.readValue',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.writeValue',
    'dev.flutter.pigeon.quick_blue.QuickBlueApi.requestMtu',
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
    messages.QuickBlueFlutterApi.setUp(null);
  });

  group(QuickBlueAndroid, () {
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
      await platform.discoverServices('device-a');
      await platform.setNotifiable(
        'device-a',
        'service-a',
        'characteristic-a',
        BleInputProperty.indication,
      );
      await platform.readValue('device-a', 'service-a', 'characteristic-a');
      await platform.writeValue(
        'device-a',
        'service-a',
        'characteristic-a',
        value,
        BleOutputProperty.withoutResponse,
      );
      expect(await platform.requestMtu('device-a', 512), 247);

      expect(
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.startScan'],
        <Object?>[
          <String>['180d'],
          manufacturerData,
        ],
      );
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
        sentMessages['dev.flutter.pigeon.quick_blue.QuickBlueApi.requestMtu'],
        <Object?>['device-a', 512],
      );
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
  if (channelName.endsWith('.requestMtu')) {
    return <Object?>[247];
  }
  return <Object?>[null];
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
