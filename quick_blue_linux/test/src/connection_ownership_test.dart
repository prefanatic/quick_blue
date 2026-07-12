import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_linux/src/connection_ownership.dart';

void main() {
  test(
    'successful attachments are tracked and repeated calls are coalesced',
    () async {
      final lease = _FakeConnectionLease();
      final ownership = ConnectionOwnership(lease);

      await ownership.attach('device-a');
      await ownership.attach('device-a');

      expect(ownership.owns('device-a'), isTrue);
      expect(lease.attachments, <String>['device-a']);
    },
  );

  test('failed attachments are not tracked', () async {
    final lease = _FakeConnectionLease(attachError: StateError('failed'));
    final ownership = ConnectionOwnership(lease);

    await expectLater(ownership.attach('device-a'), throwsStateError);
    expect(ownership.owns('device-a'), isFalse);
  });

  test('detach is idempotent and forwards final-client cleanup', () async {
    final lease = _FakeConnectionLease();
    final ownership = ConnectionOwnership(lease);
    await ownership.attach('device-a');
    var cleanups = 0;

    await ownership.detach('device-a', onLastClient: () async => cleanups++);
    await ownership.detach('device-a', onLastClient: () async => cleanups++);

    expect(ownership.owns('device-a'), isFalse);
    expect(lease.detachments, <String>['device-a']);
    expect(cleanups, 1);
  });

  test('failed detach preserves ownership for a retry', () async {
    final lease = _FakeConnectionLease(detachError: StateError('failed'));
    final ownership = ConnectionOwnership(lease);
    await ownership.attach('device-a');

    await expectLater(
      ownership.detach('device-a', onLastClient: () async {}),
      throwsStateError,
    );

    expect(ownership.owns('device-a'), isTrue);
  });
}

class _FakeConnectionLease implements QuickBlueLinuxConnectionLease {
  _FakeConnectionLease({this.attachError, this.detachError});

  final Object? attachError;
  final Object? detachError;
  final List<String> attachments = <String>[];
  final List<String> detachments = <String>[];

  @override
  Future<void> attach(String deviceId) async {
    attachments.add(deviceId);
    if (attachError case final error?) {
      throw error;
    }
  }

  @override
  Future<void> detach(
    String deviceId,
    Future<void> Function() onLastClient,
  ) async {
    detachments.add(deviceId);
    if (detachError case final error?) {
      throw error;
    }
    await onLastClient();
  }
}
