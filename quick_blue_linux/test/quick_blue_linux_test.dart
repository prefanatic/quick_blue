import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_linux/quick_blue_linux.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registers as platform implementation', () {
    final previous = QuickBluePlatform.instance;
    try {
      QuickBlueLinux.registerWith();
      expect(QuickBluePlatform.instance, isA<QuickBlueLinux>());
    } finally {
      QuickBluePlatform.instance = previous;
    }
  });

  test('companion APIs throw QuickBlueException', () async {
    final platform = QuickBlueLinux();

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

  test('requestMtu reports unsupported instead of returning an estimate', () {
    final platform = QuickBlueLinux();

    expect(
      platform.requestMtu('device-a', 247),
      throwsA(
        isA<QuickBlueException>()
            .having(
              (error) => error.code,
              'code',
              QuickBlueErrorCode.unsupported,
            )
            .having((error) => error.operation, 'operation', 'requestMtu'),
      ),
    );
  });

  test('concurrent first calls share one BlueZ initialization', () async {
    final client = _FakeBlueZClient();
    final platform = QuickBlueLinux.withClient(client);

    final firstAvailability = platform.isBluetoothAvailable();
    final secondAvailability = platform.isBluetoothAvailable();
    await pumpEventQueue();

    expect(client.connectCount, 1);

    client.connection.complete();
    expect(
      await Future.wait(<Future<bool>>[firstAvailability, secondAvailability]),
      <bool>[false, false],
    );
    expect(await platform.isBluetoothAvailable(), isFalse);
    expect(client.connectCount, 1);
  });

  test('security recovery pairs an unpaired BlueZ device', () async {
    final device = _FakeBlueZDevice('AA:BB:CC:DD:EE:FF');
    final client = _FakeBlueZClient(devices: <BlueZDevice>[device]);
    client.connection.complete();
    final platform = QuickBlueLinux.withClient(client);

    final result = await platform.recoverSecurity(
      device.address,
      QuickBlueSecurityException(
        reason: QuickBlueSecurityErrorReason.insufficientAuthorization,
        nativeDomain: 'org.bluez.Error.NotAuthorized',
        nativeCode: null,
        operation: 'readValue',
        deviceId: device.address,
        message: 'Not authorized',
      ),
    );

    expect(result, QuickBlueSecurityRecoveryResult.recovered);
    expect(device.pairCount, 1);
    expect(device.paired, isTrue);
  });
}

class _FakeBlueZClient implements BlueZClient {
  _FakeBlueZClient({this.devices = const <BlueZDevice>[]});

  final connection = Completer<void>();
  var connectCount = 0;

  @override
  Future<void> connect() {
    connectCount++;
    return connection.future;
  }

  @override
  List<BlueZAdapter> get adapters => const <BlueZAdapter>[];

  @override
  final List<BlueZDevice> devices;

  @override
  Stream<BlueZAdapter> get adapterAdded => const Stream<BlueZAdapter>.empty();

  @override
  Stream<BlueZAdapter> get adapterRemoved => const Stream<BlueZAdapter>.empty();

  @override
  Stream<BlueZDevice> get deviceAdded => const Stream<BlueZDevice>.empty();

  @override
  Stream<BlueZDevice> get deviceRemoved => const Stream<BlueZDevice>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBlueZDevice implements BlueZDevice {
  _FakeBlueZDevice(this.address);

  @override
  final String address;

  @override
  var paired = false;

  var pairCount = 0;

  @override
  Future<void> pair() async {
    pairCount++;
    paired = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
