import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_example/src/ble_gatt_session.dart';

void main() {
  test(
    'notification teardown releases every claim despite cancellation error',
    () async {
      final session = BleGattSession();
      final canceled = <String>[];
      final failure = StateError('first teardown failed');
      final first = StreamController<Uint8List>(
        onCancel: () {
          canceled.add('first');
          throw failure;
        },
      );
      final second = StreamController<Uint8List>(
        onCancel: () {
          canceled.add('second');
        },
      );
      session.setNotification('first', first.stream.listen((_) {}));
      session.setNotification('second', second.stream.listen((_) {}));
      final cleanup = session.cancelNotifications();
      expect(session.notificationKeys, isEmpty);
      await expectLater(cleanup, throwsA(same(failure)));
      expect(canceled, ['first', 'second']);
      await Future.wait([first.close(), second.close()]);
    },
  );
}
