import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

/// Test-only seams. Generated codecs and event objects stay package-local.
class AdapterContractBinding {
  AdapterContractBinding({
    required this.name,
    required this.create,
    required this.codec,
    required this.valueEvent,
    required this.unregister,
    required this.directRead,
    required this.securityDetails,
    required this.securityDomain,
    required this.securityCode,
    required this.securityReason,
    required this.expectedCapabilities,
    this.capabilityReply,
    this.eventCodec,
    this.mtuEvent,
    this.connectedMethod = 'connectedDeviceIds',
  });

  final String name;
  final QuickBluePlatform Function() create;
  final MessageCodec<Object?> codec;
  final Object Function(String, String, String, Uint8List) valueEvent;
  final void Function() unregister;
  final bool directRead;
  final Object securityDetails;
  final String securityDomain;
  final int securityCode;
  final QuickBlueSecurityErrorReason securityReason;
  final QuickBlueCapabilities Function(bool) expectedCapabilities;
  final Object Function(bool)? capabilityReply;
  final MethodCodec? eventCodec;
  final Object Function()? mtuEvent;
  final String connectedMethod;

  String get prefix => 'dev.flutter.pigeon.$name';
}

class AdapterContractHarness {
  AdapterContractHarness(this.binding) : platform = binding.create() {
    for (final method in [
      'isBluetoothAvailable',
      'readValue',
      'writeValue',
      'setNotifiable',
      'capabilities',
      'isAppleAccessorySetupSupported',
      binding.connectedMethod,
      'requestMtu',
    ]) {
      mock(method, (args) async {
        calls.putIfAbsent(method, () => []).add(args);
        if (errors.containsKey(method)) return errors[method];
        if (method == binding.connectedMethod) {
          return [
            binding.name == 'quick_blue_darwin'
                ? <Object?>[]
                : <String>['device-a'],
          ];
        }
        if (method == 'readValue' && readReply != null) {
          return readReply!.future;
        }
        if (method == 'setNotifiable' &&
            setupReply != null &&
            (args as List<Object?>)[3].toString().split('.').last !=
                'disabled') {
          return setupReply!.future;
        }
        return switch (method) {
          'isBluetoothAvailable' => [true],
          'isAppleAccessorySetupSupported' => [capabilityEnabled],
          'capabilities' => [binding.capabilityReply!(capabilityEnabled)],
          'readValue' => [
            binding.directRead ? Uint8List.fromList([1, 2]) : null,
          ],
          'connectedDeviceIds' => [
            <String>['device-a'],
          ],
          'requestMtu' => [247],
          _ => [null],
        };
      });
    }
    if (binding.name == 'quick_blue_darwin') {
      messenger.setMockMessageHandler(restorationChannel, (data) async {
        final call = binding.eventCodec!.decodeMethodCall(data!);
        if (call.method == 'listen') restorationListens++;
        return binding.eventCodec!.encodeSuccessEnvelope(null);
      });
    }
    if (binding.mtuEvent != null) {
      messenger.setMockMessageHandler(
        mtuChannel,
        (_) async => binding.eventCodec!.encodeSuccessEnvelope(null),
      );
    }
  }

  final AdapterContractBinding binding;
  final QuickBluePlatform platform;
  final calls = <String, List<Object?>>{};
  final errors = <String, Object?>{};
  final channels = <String>[];
  final subscriptions = <StreamSubscription<Uint8List>>[];
  Completer<Object?>? readReply;
  Completer<Object?>? setupReply;
  bool capabilityEnabled = false;
  int restorationListens = 0;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String get restorationChannel =>
      '${binding.prefix}.QuickBlueEventApi.restorationEvents';
  String get mtuChannel => '${binding.prefix}.QuickBlueEventApi.mtuChanged';

  void mock(String method, Future<Object?> Function(Object?) handler) {
    final name = '${binding.prefix}.QuickBlueApi.$method';
    channels.add(name);
    messenger.setMockDecodedMessageHandler<Object?>(
      BasicMessageChannel<Object?>(name, binding.codec),
      handler,
    );
  }

  Future<void> initialize() async {
    expect(await platform.isBluetoothAvailable(), isTrue);
    await pumpEventQueue();
  }

  Future<void> inject(
    String service,
    List<int> bytes, {
    String device = 'device-a',
    String characteristic = '2a19',
  }) async {
    Object? reply;
    await messenger.handlePlatformMessage(
      '${binding.prefix}.QuickBlueFlutterApi.onCharacteristicValueChanged',
      binding.codec.encodeMessage([
        binding.valueEvent(
          device,
          service,
          characteristic,
          Uint8List.fromList(bytes),
        ),
      ]),
      (data) => reply = binding.codec.decodeMessage(data),
    );
    expect(reply, isEmpty);
    await pumpEventQueue();
  }

  List<Uint8List> listen(
    String service, {
    bool notifications = false,
    BleInputProperty mode = BleInputProperty.notification,
    void Function(Object)? onError,
    void Function()? onDone,
  }) {
    final values = <Uint8List>[];
    final stream = notifications
        ? platform.characteristicNotifications(
            'device-a',
            service,
            '2a19',
            bleInputProperty: mode,
          )
        : platform.characteristicValueStreamFor('device-a', service, '2a19');
    subscriptions.add(
      stream.listen(values.add, onError: onError, onDone: onDone),
    );
    return values;
  }

  Future<void> close() async {
    // Settle controlled replies before awaiting cancellation; never strand teardown.
    if (readReply != null && !readReply!.isCompleted) {
      readReply!.complete([
        binding.directRead ? Uint8List.fromList([1, 2]) : null,
      ]);
    }
    if (setupReply != null && !setupReply!.isCompleted) {
      setupReply!.complete([null]);
    }
    for (final subscription in subscriptions) {
      await subscription.cancel().timeout(const Duration(seconds: 2));
    }
    binding.unregister();
    platform.onValueChanged = null;
    for (final name in channels) {
      messenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(name, binding.codec),
        null,
      );
    }
    if (binding.name == 'quick_blue_darwin') {
      messenger.setMockMessageHandler(restorationChannel, null);
      messenger.setMessageHandler(restorationChannel, null);
    }
    if (binding.mtuEvent != null) {
      messenger.setMockMessageHandler(mtuChannel, null);
      messenger.setMessageHandler(mtuChannel, null);
    }
  }
}

void registerAdapterContracts(AdapterContractBinding binding) {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AdapterContractHarness h;
  setUp(() => h = AdapterContractHarness(binding));
  tearDown(() => h.close());

  test(
    'R1 notification before read reply: ${binding.directRead ? 'direct bytes' : 'legacy event fallback'}',
    () async {
      await h.initialize();
      final events = h.listen('180f');
      h.readReply = Completer<Object?>();
      var completed = false;
      final result = h.platform
          .readCharacteristicValue('device-a', '180f', '2a19')
          .then((value) {
            completed = true;
            return value;
          });
      await pumpEventQueue();
      expect(h.calls['readValue']!.single, ['device-a', '180f', '2a19']);
      await h.inject('180a', [7]);
      await h.inject('180f', [9]);
      expect(completed, isFalse);
      expect(events, [
        Uint8List.fromList([9]),
      ]);
      h.readReply!.complete([
        binding.directRead ? Uint8List.fromList([1, 2]) : null,
      ]);
      expect(
        await result.timeout(const Duration(seconds: 2)),
        binding.directRead ? [1, 2] : [9],
      );
    },
  );

  test('R2 service isolation, UUID aliases and outgoing identities', () async {
    await h.initialize();
    final a = h.listen('180f');
    final b = h.listen('180a');
    await h.inject('180F', [1]);
    await h.inject('0000180a-0000-1000-8000-00805f9b34fb', [2]);
    await h.inject('180f', [
      5,
    ], characteristic: '00002A19-0000-1000-8000-00805F9B34FB');
    await h.inject('180f', [3], device: 'device-b');
    await h.inject('180f', [4], characteristic: '2a20');
    expect(a, [
      Uint8List.fromList([1]),
      Uint8List.fromList([5]),
    ]);
    expect(b, [
      Uint8List.fromList([2]),
    ]);
    await h.platform.writeValue(
      'device-a',
      '180F',
      '2A19',
      Uint8List.fromList([5]),
      BleOutputProperty.withResponse,
    );
    await h.platform.setNotifiable(
      'device-a',
      '180A',
      '2A19',
      BleInputProperty.indication,
    );
    expect((h.calls['writeValue']!.single as List).take(3), [
      'device-a',
      '180F',
      '2A19',
    ]);
    expect((h.calls['setNotifiable']!.single as List).take(3), [
      'device-a',
      '180A',
      '2A19',
    ]);
  });

  for (final operation in ['readValue', 'writeValue', 'setNotifiable']) {
    Future<void> invoke() => switch (operation) {
      'readValue' => h.platform.readValue('device-a', '180f', '2a19'),
      'writeValue' => h.platform.writeValue(
        'device-a',
        '180f',
        '2a19',
        Uint8List.fromList([1]),
        BleOutputProperty.withResponse,
      ),
      _ => h.platform.setNotifiable(
        'device-a',
        '180f',
        '2a19',
        BleInputProperty.notification,
      ),
    };
    test('R3 $operation typed security context', () async {
      h.errors[operation] = [
        binding.name == 'quick_blue' ? 'GattError' : 'OperationFailed',
        'denied',
        binding.securityDetails,
      ];
      await expectLater(
        invoke(),
        throwsA(
          isA<QuickBlueSecurityException>()
              .having((e) => e.reason, 'reason', binding.securityReason)
              .having((e) => e.nativeDomain, 'domain', binding.securityDomain)
              .having((e) => e.nativeCode, 'nativeCode', binding.securityCode)
              .having((e) => e.operation, 'operation', operation)
              .having((e) => e.deviceId, 'device', 'device-a')
              .having((e) => e.serviceId, 'service', '180f')
              .having((e) => e.characteristicId, 'characteristic', '2a19'),
        ),
      );
    });
    for (final malformed in [false, true]) {
      test(
        'R3 $operation ${malformed ? 'malformed' : 'non-security'} details',
        () async {
          final details = malformed
              ? 'bad-status'
              : binding.name == 'quick_blue_darwin'
              ? <String, Object?>{'domain': 'CBATTErrorDomain', 'code': 1}
              : 1;
          h.errors[operation] = [
            binding.name == 'quick_blue' ? 'GattError' : 'OperationFailed',
            'failed',
            details,
          ];
          final Matcher expected = binding.name == 'quick_blue_darwin'
              ? isA<QuickBlueException>().having(
                  (e) => e.code,
                  'code',
                  QuickBlueErrorCode.operationFailed,
                )
              : binding.name == 'quick_blue' && !malformed
              ? isA<QuickBlueGattException>().having(
                  (e) => e.status,
                  'status',
                  1,
                )
              : isA<PlatformException>().having(
                  (e) => e.details,
                  'details',
                  details,
                );
          await expectLater(invoke(), throwsA(expected));
        },
      );
    }
  }

  test('R4 shared enable, mode conflict and final disable', () async {
    await h.initialize();
    final a = h.listen('180f', notifications: true);
    final b = h.listen('180f', notifications: true);
    await pumpEventQueue();
    expect(h.calls['setNotifiable'], hasLength(1));
    final errors = <Object>[];
    h.listen(
      '180f',
      notifications: true,
      mode: BleInputProperty.indication,
      onError: errors.add,
    );
    await pumpEventQueue();
    expect(errors, [
      isA<QuickBlueException>().having(
        (e) => e.code,
        'code',
        QuickBlueErrorCode.invalidState,
      ),
    ]);
    await h.inject('180f', [9]);
    expect(a, [
      Uint8List.fromList([9]),
    ]);
    expect(b, [
      Uint8List.fromList([9]),
    ]);
    await h.subscriptions[0].cancel();
    expect(h.calls['setNotifiable'], hasLength(1));
    await h.subscriptions[1].cancel();
    expect(h.calls['setNotifiable'], hasLength(2));
    expect(
      (h.calls['setNotifiable']!.last as List)[3].toString().split('.').last,
      'disabled',
    );
  });

  for (final failed in [false, true]) {
    test(
      'R4 pending setup cancellation ${failed ? 'failure' : 'success'}',
      () async {
        await h.initialize();
        h.setupReply = Completer<Object?>();
        h.listen('180f', notifications: true, onError: (_) {});
        await pumpEventQueue();
        var cancelled = false;
        final cancellation = h.subscriptions.single.cancel().then(
          (_) => cancelled = true,
        );
        await pumpEventQueue();
        expect(cancelled, isFalse);
        h.setupReply!.complete(
          failed ? ['OperationFailed', 'failed', null] : [null],
        );
        await cancellation.timeout(const Duration(seconds: 2));
        expect(h.calls['setNotifiable'], hasLength(failed ? 1 : 2));
      },
    );
  }

  test('R4 terminal setup error closes the listener', () async {
    await h.initialize();
    h.errors['setNotifiable'] = ['OperationFailed', 'failed', null];
    final errors = <Object>[];
    final done = Completer<void>();
    h.listen(
      '180f',
      notifications: true,
      onError: errors.add,
      onDone: done.complete,
    );
    await done.future.timeout(const Duration(seconds: 2));
    expect(errors, hasLength(1));
    expect(h.calls['setNotifiable'], hasLength(1));
  });

  for (final enabled in [false, true]) {
    test(
      'R5 complete capability object, dynamic host gates $enabled',
      () async {
        h.capabilityEnabled = enabled;
        expect(
          await h.platform.capabilities(),
          binding.expectedCapabilities(enabled),
        );
        if (binding.name != 'quick_blue') {
          await expectLater(
            Future.sync(() => h.platform.bondState('device-a')),
            throwsA(
              isA<QuickBlueException>()
                  .having((e) => e.code, 'code', QuickBlueErrorCode.unsupported)
                  .having((e) => e.operation, 'operation', 'bondState'),
            ),
          );
        }
        if (!binding.directRead) {
          await expectLater(
            Future.sync(() => h.platform.openL2cap('device-a', 25)),
            throwsA(
              isA<QuickBlueException>()
                  .having((e) => e.code, 'code', QuickBlueErrorCode.unsupported)
                  .having((e) => e.operation, 'operation', 'openL2cap'),
            ),
          );
        }
      },
    );
  }

  test('R5 connected lookup parameters and negotiated/requested MTU', () async {
    await h.platform.connectedDevices(serviceUuids: ['180f']);
    expect(h.calls[binding.connectedMethod]!.single, [
      ['180f'],
    ]);
    if (binding.name == 'quick_blue_darwin') {
      // The advertised UUID requirement is enforced by the host, not Dart.
      h.errors[binding.connectedMethod] = [
        'Unsupported',
        'UUIDs required',
        null,
      ];
      await expectLater(
        h.platform.connectedDevices(),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'Unsupported'),
        ),
      );
      expect(h.calls[binding.connectedMethod]!.last, [<String>[]]);
    }
    final mtu = h.platform.requestMtu('device-a', 512);
    if (binding.mtuEvent != null) {
      await pumpEventQueue();
      await h.messenger.handlePlatformMessage(
        h.mtuChannel,
        binding.eventCodec!.encodeSuccessEnvelope(binding.mtuEvent!()),
        (_) {},
      );
    }
    expect(await mtu.timeout(const Duration(seconds: 2)), 247);
    expect(h.calls['requestMtu']!.single, ['device-a', 512]);
  });

  test(
    'R6 empty-service legacy fanout is routing, not native lookup',
    () async {
      await h.initialize();
      final a = h.listen('180f');
      final b = h.listen('180a');
      final legacy = <BluetoothCharacteristicValue>[];
      final legacyCallbacks = <(String, String, Uint8List)>[];
      h.platform.onValueChanged = (device, characteristic, value) {
        legacyCallbacks.add((device, characteristic, value));
      };
      final subscription = h.platform.characteristicValueStream.listen(
        legacy.add,
      );
      try {
        await h.inject('', [9]);
        expect(a, [
          Uint8List.fromList([9]),
        ]);
        expect(b, [
          Uint8List.fromList([9]),
        ]);
        expect(legacy.single.serviceId, '');
        expect(legacyCallbacks, hasLength(1));
        expect(legacyCallbacks.single.$1, 'device-a');
        expect(legacyCallbacks.single.$2, '2a19');
        expect(legacyCallbacks.single.$3, [9]);
        await h.inject('180f', [1]);
        expect(a, hasLength(2));
        expect(b, hasLength(1));
      } finally {
        await subscription.cancel();
      }
    },
  );

  test(
    'R7 repeated initialization delivers once; cancelled listeners stay silent',
    () async {
      final values = h.listen('180f');
      await h.initialize();
      await h.initialize();
      await h.inject('180f', [9]);
      expect(values, [
        Uint8List.fromList([9]),
      ]);
      if (binding.name == 'quick_blue_darwin') expect(h.restorationListens, 1);
      await h.subscriptions.single.cancel();
      await h.inject('180f', [1]);
      expect(values, hasLength(1));
    },
  );
}
