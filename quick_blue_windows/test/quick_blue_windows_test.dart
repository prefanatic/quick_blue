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

  tearDown(() {
    for (final name in const [
      isBluetoothAvailableChannelName,
      startScanChannelName,
      stopScanChannelName,
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
    messages.QuickBlueFlutterApi.setUp(null);
  });

  test('forwards core host API calls', () async {
    final sentMessages = <String, Object?>{};
    for (final name in const [
      isBluetoothAvailableChannelName,
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
              return <Object?>[null];
            },
          );
    }

    final platform = QuickBlueWindows();

    expect(await platform.isBluetoothAvailable(), isTrue);
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

  test('unsupported APIs throw UnsupportedError', () {
    final platform = QuickBlueWindows();

    expect(platform.companionAssociate(), throwsA(isA<UnsupportedError>()));
    expect(
      () => platform.companionDisassociate(42),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      platform.getCompanionAssociations(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => platform.openL2cap('device-a', 25),
      throwsA(isA<UnsupportedError>()),
    );
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

      await QuickBlueWindows().startScan(
        scanFilter: ScanFilter(
          serviceUuids: const <String>['180d'],
          manufacturerData: manufacturerData,
        ),
      );

      expect(sentMessage, <Object?>[
        <String>['180d'],
        manufacturerData,
      ]);
    },
  );

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
