import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'test_support/fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'raw native connect exception is retained, not parsed by wording',
    () async {
      final native = PlatformException(
        code: 'VendorConnectionError',
        message: 'cancelled remotely: misleading words',
        details: <String, Object>{'status': 999},
        stacktrace: 'native stack trace',
      );
      final platform = _FailingConnectPlatform(native);
      addTearDown(platform.dispose);
      await expectLater(
        platform.device('device-a').connect(),
        throwsA(
          isA<QuickBlueException>()
              .having(
                (e) => e.failureReason,
                'reason',
                QuickBlueFailureReason.connectionFailed,
              )
              .having((e) => e.details, 'diagnostics', same(native)),
        ),
      );
    },
  );
}

class _FailingConnectPlatform extends FakeQuickBluePlatform {
  _FailingConnectPlatform(this.error);
  final Object error;

  @override
  Future<void> connect(String deviceId) async => throw error;
}
