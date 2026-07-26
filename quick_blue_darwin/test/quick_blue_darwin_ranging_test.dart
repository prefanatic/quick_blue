import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_darwin/quick_blue_darwin.dart';
import 'package:quick_blue_darwin/src/messages.g.dart' as messages;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const capabilitiesChannel =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.'
      'getRangingCapabilities';
  const startChannel =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.startRanging';
  const stopChannel =
      'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.stopRanging';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    for (final name in const <String>[
      capabilitiesChannel,
      startChannel,
      stopChannel,
    ]) {
      messenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(
          name,
          messages.QuickBlueApi.pigeonChannelCodec,
        ),
        null,
      );
    }
    messages.QuickBlueFlutterApi.setUp(null);
  });

  test('maps directional capabilities, options, and measurements', () async {
    Object? startMessage;
    messenger.setMockDecodedMessageHandler<Object?>(
      const BasicMessageChannel<Object?>(
        capabilitiesChannel,
        messages.QuickBlueApi.pigeonChannelCodec,
      ),
      (_) async => <Object?>[
        messages.PlatformRangingCapabilities(
          availability: messages.PlatformRangingAvailability.available,
          supportsDirection: true,
        ),
      ],
    );
    messenger.setMockDecodedMessageHandler<Object?>(
      const BasicMessageChannel<Object?>(
        startChannel,
        messages.QuickBlueApi.pigeonChannelCodec,
      ),
      (message) async {
        startMessage = message;
        return <Object?>[null];
      },
    );
    messenger.setMockDecodedMessageHandler<Object?>(
      const BasicMessageChannel<Object?>(
        stopChannel,
        messages.QuickBlueApi.pigeonChannelCodec,
      ),
      (_) async => <Object?>[null],
    );

    final platform = QuickBlueDarwin();
    final device = platform.device('device-a');
    final capabilities = await device.rangingCapabilities();
    expect(capabilities.isAvailable, isTrue);
    expect(capabilities.supportsDirection, isTrue);

    final session = await device.startRanging(
      options: const BleRangingOptions(requestDirection: true),
    );
    final measurementFuture = session.measurements.first;
    await _sendFlutterApiMessage(
      'onRangingMeasurement',
      messages.PlatformRangingMeasurement(
        deviceId: device.id,
        distanceMeters: 1.75,
        azimuthDegrees: 30,
        elevationDegrees: null,
        rssi: null,
        distanceConfidence: messages.PlatformRangingConfidence.unknown,
        azimuthConfidence: messages.PlatformRangingConfidence.unknown,
        elevationConfidence: messages.PlatformRangingConfidence.unknown,
      ),
    );

    final measurement = await measurementFuture;
    expect(measurement.distanceMeters, 1.75);
    expect(measurement.azimuthDegrees, 30);
    final message = startMessage as List<Object?>;
    expect(message[0], device.id);
    final options = message[1] as messages.PlatformRangingOptions;
    expect(options.requestDirection, isTrue);

    await session.stop();
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
