import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_darwin/quick_blue_darwin.dart';
import 'package:quick_blue_darwin/src/messages.g.dart' as messages;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final operation in ['readValue', 'writeValue', 'setNotifiable']) {
    final channel =
        'dev.flutter.pigeon.quick_blue_darwin.QuickBlueApi.$operation';
    Future<void> invoke() {
      final platform = QuickBlueDarwin();
      return switch (operation) {
        'readValue' => platform.readValue('device-a', '180d', '2a37'),
        'writeValue' => platform.writeValue(
          'device-a',
          '180d',
          '2a37',
          Uint8List.fromList([1]),
          BleOutputProperty.withResponse,
        ),
        _ => platform.setNotifiable(
          'device-a',
          '180d',
          '2a37',
          BleInputProperty.notification,
        ),
      };
    }

    tearDown(() => messenger.setMockMessageHandler(channel, null));

    test(
      '$operation decodes native disconnect cleanup with nil details',
      () async {
        messenger.setMockMessageHandler(channel, (_) async {
          return messages.QuickBlueApi.pigeonChannelCodec.encodeMessage([
            'Disconnected',
            'Peripheral connection ended.',
            null,
          ]);
        });
        await expectLater(
          invoke(),
          throwsA(
            isA<QuickBlueException>()
                .having(
                  (e) => e.failureReason,
                  'failureReason',
                  QuickBlueFailureReason.remoteDisconnected,
                )
                .having((e) => e.details, 'details', {
                  'platformCode': 'Disconnected',
                }),
          ),
        );
      },
    );

    for (final code in ['Disconnected', 'InvalidState', 'ReadFailed']) {
      test(
        '$operation classifies only structured Disconnected ($code)',
        () async {
          final native = PlatformException(
            code: code,
            message: 'The device disconnected.',
            details: {'domain': 'CBATTErrorDomain', 'code': 2},
          );
          final stack = StackTrace.fromString('native GATT origin: $operation');
          messenger.setMockMessageHandler(
            channel,
            (_) => Future<ByteData?>.error(native, stack),
          );
          try {
            await invoke();
            fail('Expected a native failure');
          } on QuickBlueException catch (error, actualStack) {
            expect(
              error.failureReason,
              code == 'Disconnected'
                  ? QuickBlueFailureReason.remoteDisconnected
                  : null,
            );
            expect(
              error.code,
              code == 'ReadFailed'
                  ? QuickBlueErrorCode.operationFailed
                  : QuickBlueErrorCode.invalidState,
            );
            expect(error.operation, operation);
            expect(error.deviceId, 'device-a');
            expect(error.serviceId, '180d');
            expect(error.characteristicId, '2a37');
            expect(error.message, native.message);
            expect(error.details, {
              'platformCode': code,
              'native': native.details,
            });
            expect(actualStack.toString(), stack.toString());
          }
        },
      );
    }

    test(
      '$operation preserves security classification before disconnect mapping',
      () async {
        messenger.setMockMessageHandler(
          channel,
          (_) => Future<ByteData?>.error(
            PlatformException(
              code: 'Disconnected',
              details: {'domain': 'CBATTErrorDomain', 'code': 5},
            ),
          ),
        );
        await expectLater(
          invoke(),
          throwsA(
            isA<QuickBlueSecurityException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  QuickBlueSecurityErrorReason.insufficientAuthentication,
                )
                .having((e) => e.failureReason, 'failureReason', null),
          ),
        );
      },
    );

    test('$operation does not relabel caller cancellation', () async {
      const cancelled = QuickBlueException(
        code: QuickBlueErrorCode.cancelled,
        message: 'Caller stopped observing',
        failureReason: QuickBlueFailureReason.callerCancelled,
      );
      final stack = StackTrace.fromString('caller cancellation origin');
      messenger.setMockMessageHandler(
        channel,
        (_) => Future<ByteData?>.error(cancelled, stack),
      );
      try {
        await invoke();
        fail('Expected cancellation');
      } on QuickBlueException catch (error, actualStack) {
        expect(error, same(cancelled));
        expect(actualStack.toString(), stack.toString());
      }
    });
  }
}
