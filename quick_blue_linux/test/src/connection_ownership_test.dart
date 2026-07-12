import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_linux/src/connection_ownership.dart';

void main() {
  test(
    'successful claims are tracked and repeated claims are coalesced',
    () async {
      final lease = _FakeConnectionLease();
      final ownership = ConnectionOwnership(lease);

      expect(await ownership.claim('device-a'), isTrue);
      expect(await ownership.claim('device-a'), isTrue);

      expect(ownership.owns('device-a'), isTrue);
      expect(lease.claims, <String>['device-a']);
    },
  );

  test('rejected claims are not tracked', () async {
    final lease = _FakeConnectionLease(claimResult: false);
    final ownership = ConnectionOwnership(lease);

    expect(await ownership.claim('device-a'), isFalse);
    expect(ownership.owns('device-a'), isFalse);
  });

  test('release is idempotent', () async {
    final lease = _FakeConnectionLease();
    final ownership = ConnectionOwnership(lease);
    await ownership.claim('device-a');

    await ownership.release('device-a');
    await ownership.release('device-a');

    expect(ownership.owns('device-a'), isFalse);
    expect(lease.releases, <String>['device-a']);
  });

  test('failed release preserves ownership for a retry', () async {
    final lease = _FakeConnectionLease(releaseError: StateError('failed'));
    final ownership = ConnectionOwnership(lease);
    await ownership.claim('device-a');

    await expectLater(ownership.release('device-a'), throwsStateError);

    expect(ownership.owns('device-a'), isTrue);
  });
}

class _FakeConnectionLease implements QuickBlueLinuxConnectionLease {
  _FakeConnectionLease({this.claimResult = true, this.releaseError});

  final bool claimResult;
  final Object? releaseError;
  final List<String> claims = <String>[];
  final List<String> releases = <String>[];

  @override
  Future<bool> claim(String deviceId) async {
    claims.add(deviceId);
    return claimResult;
  }

  @override
  Future<void> release(String deviceId) async {
    releases.add(deviceId);
    if (releaseError case final error?) {
      throw error;
    }
  }
}
