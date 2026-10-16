import 'package:test/test.dart';
import 'package:quick_blue_core/quick_blue_core.dart';

void main() {
  test('failure reasons are available from the public package entrypoint', () {
    const error = QuickBlueException(
      code: QuickBlueErrorCode.operationFailed,
      message: 'The remote device disconnected.',
      failureReason: QuickBlueFailureReason.remoteDisconnected,
    );

    expect(error.failureReason, QuickBlueFailureReason.remoteDisconnected);
  });
}
