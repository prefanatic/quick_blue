import 'dart:async';

// Executed by quick_blue_windows's test runner, whose dev dependencies own this.
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';

import '../../../quick_blue/test/test_support/adapter_contract_harness.dart';
import '../../../quick_blue_windows/test/test_support/adapter_contract_binding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AdapterContractHarness h;
  setUp(() => h = AdapterContractHarness(binding()));
  tearDown(() => h.close());

  test(
    'wrong-service event cannot settle read after void host success',
    () async {
      await h.initialize();
      h.readReply = Completer<Object?>();
      var completed = false;
      final result = h.platform
          .readCharacteristicValue('device-a', '180f', '2a19')
          .then((value) {
            completed = true;
            return value;
          });
      try {
        await pumpEventQueue();
        await h.inject('180a', [7]);
        h.readReply!.complete([null]);
        await pumpEventQueue();
        expect(completed, isFalse);
        expect(h.calls['readValue']!.single, ['device-a', '180f', '2a19']);
      } finally {
        // Also release the inherited StreamQueue if an assertion fails.
        if (!h.readReply!.isCompleted) h.readReply!.complete([null]);
        await h.inject('180f', [1, 2]);
        expect(await result.timeout(const Duration(seconds: 2)), [1, 2]);
      }
    },
  );
}
