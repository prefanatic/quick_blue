import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue/src/messages.g.dart' as messages;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const capabilitiesChannel =
      'dev.flutter.pigeon.quick_blue.QuickBlueApi.getRangingCapabilities';
  const startChannel =
      'dev.flutter.pigeon.quick_blue.QuickBlueApi.startRanging';
  const stopChannel = 'dev.flutter.pigeon.quick_blue.QuickBlueApi.stopRanging';
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

  test('maps capabilities, options, and measurements', () async {
    Object? startMessage;
    messenger.setMockDecodedMessageHandler<Object?>(
      const BasicMessageChannel<Object?>(
        capabilitiesChannel,
        messages.QuickBlueApi.pigeonChannelCodec,
      ),
      (_) async => <Object?>[
        messages.PlatformRangingCapabilities(
          availability: messages.PlatformRangingAvailability.available,
          supportsDirection: false,
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

    final platform = QuickBlueAndroid();
    final device = platform.device('AA:BB:CC:DD:EE:FF');
    final capabilities = await device.rangingCapabilities();
    expect(capabilities.isAvailable, isTrue);
    expect(capabilities.supportsDirection, isFalse);

    final session = await device.startRanging(
      options: const BleRangingOptions(
        updateRate: BleRangingUpdateRate.frequent,
      ),
    );
    final measurementFuture = session.measurements.first;
    await _sendFlutterApiMessage(
      'onRangingMeasurement',
      messages.PlatformRangingMeasurement(
        deviceId: device.id,
        distanceMeters: 2.5,
        azimuthDegrees: null,
        elevationDegrees: null,
        rssi: -45,
        distanceConfidence: messages.PlatformRangingConfidence.high,
        azimuthConfidence: messages.PlatformRangingConfidence.unknown,
        elevationConfidence: messages.PlatformRangingConfidence.unknown,
      ),
    );

    final measurement = await measurementFuture;
    expect(measurement.distanceMeters, 2.5);
    expect(measurement.rssi, -45);
    expect(measurement.distanceConfidence, BleRangingConfidence.high);
    final message = startMessage as List<Object?>;
    expect(message[0], device.id);
    final options = message[1] as messages.PlatformRangingOptions;
    expect(options.requestDirection, isFalse);
    expect(options.updateRate, messages.PlatformRangingUpdateRate.frequent);

    await session.stop();
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
