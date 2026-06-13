import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_darwin/quick_blue_darwin.dart';
import 'package:quick_blue_darwin/src/messages.g.dart' as messages;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const startScanChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.startScan';
  const requestMtuChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.requestMtu';
  const writeValueChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.writeValue';

  tearDown(() {
    for (final name in const [
      startScanChannelName,
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

    expect(sentMessage, <Object?>[null, null]);
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

      expect(sentMessage, <Object?>[
        <String>['180d'],
        manufacturerData,
      ]);
    },
  );

  test('requestMtu forwards the device and returns the negotiated MTU', () async {
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
}
