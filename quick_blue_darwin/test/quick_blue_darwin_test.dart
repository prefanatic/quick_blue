import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_darwin/quick_blue_darwin.dart';
import 'package:quick_blue_darwin/src/messages.g.dart' as messages;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const startScanChannelName =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.startScan';

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          const BasicMessageChannel<Object?>(
            startScanChannelName,
            messages.QuickBlueApi.pigeonChannelCodec,
          ),
          null,
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
}
