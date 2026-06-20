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
}
