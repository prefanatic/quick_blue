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
}
