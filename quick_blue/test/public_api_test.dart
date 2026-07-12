import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/quick_blue.dart';

void main() {
  test('exports connection conflict policy from the app-facing package', () {
    expect(ConnectionConflictPolicy.wait.name, 'wait');
  });
}
