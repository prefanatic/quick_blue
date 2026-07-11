import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_linux/src/scan_filter.dart';

void main() {
  group('meetsRssiThreshold', () {
    test('accepts values equal to the configured minimum', () {
      expect(meetsRssiThreshold(-70, -70), isTrue);
    });

    test('rejects values below the configured minimum', () {
      expect(meetsRssiThreshold(-71, -70), isFalse);
    });

    test('accepts every value when no minimum is configured', () {
      expect(meetsRssiThreshold(-100, null), isTrue);
    });
  });
}
