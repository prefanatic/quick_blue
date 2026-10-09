import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'test_support/fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final legacy in <bool>[false, true]) {
    for (final cancelOldFirst in <bool>[false, true]) {
      test('old and fresh streams overlap: legacy=$legacy, '
          'cancelOldFirst=$cancelOldFirst', () async {
        final platform = FakeQuickBluePlatform();
        addTearDown(platform.dispose);
        final characteristic = platform
            .device('device-a')
            .characteristic('180d', '2a37');
        final oldStream = characteristic.valueStream;
        final initial = oldStream.listen((_) {});
        await initial.cancel();

        final freshStream = characteristic.valueStream;
        final freshValues = <Uint8List>[];
        final fresh = freshStream.listen(freshValues.add);
        addTearDown(fresh.cancel);
        final oldValues = <Uint8List>[];
        final old = oldStream.listen(oldValues.add);
        addTearDown(old.cancel);

        void emit(int value) {
          platform.handleCharacteristicValueChanged(
            'device-a',
            legacy ? '' : '180d',
            '2a37',
            Uint8List.fromList(<int>[value]),
          );
        }

        emit(1);
        await pumpEventQueue();
        expect(oldValues.map((value) => value.toList()), <List<int>>[
          <int>[1],
        ]);
        expect(freshValues.map((value) => value.toList()), <List<int>>[
          <int>[1],
        ]);

        await (cancelOldFirst ? old : fresh).cancel();
        emit(2);
        await pumpEventQueue();
        final remainingValues = cancelOldFirst ? freshValues : oldValues;
        expect(remainingValues.map((value) => value.toList()), <List<int>>[
          <int>[1],
          <int>[2],
        ]);
        final cancelledValues = cancelOldFirst ? oldValues : freshValues;
        expect(cancelledValues.length, 1);

        // A getter obtained during overlap still routes to a live stream.
        final getterValues = <Uint8List>[];
        final getter = characteristic.valueStream.listen(getterValues.add);
        addTearDown(getter.cancel);
        emit(3);
        await pumpEventQueue();
        expect(getterValues.single.toList(), <int>[3]);
        expect(remainingValues.last.toList(), <int>[3]);
        expect(platform.calls, isEmpty);
      });
    }
  }

  test(
    'overlapping listeners on one retained stream survive cancellation',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      final stream = platform
          .device('device-a')
          .characteristic('180d', '2a37')
          .valueStream;
      final firstValues = <Uint8List>[];
      final secondValues = <Uint8List>[];
      final first = stream.listen(firstValues.add);
      final second = stream.listen(secondValues.add);
      addTearDown(first.cancel);
      addTearDown(second.cancel);
      await first.cancel();
      platform.handleCharacteristicValueChanged(
        'device-a',
        '180d',
        '2a37',
        Uint8List.fromList(<int>[1]),
      );
      await pumpEventQueue();
      expect(firstValues, isEmpty);
      expect(secondValues.single.toList(), <int>[1]);
      await second.cancel();
      final resumedValues = <Uint8List>[];
      final resumed = stream.listen(resumedValues.add);
      addTearDown(resumed.cancel);
      platform.handleCharacteristicValueChanged(
        'device-a',
        '180d',
        '2a37',
        Uint8List.fromList(<int>[2]),
      );
      await pumpEventQueue();
      expect(resumedValues.single.toList(), <int>[2]);
      expect(platform.calls, isEmpty);
    },
  );

  test(
    'retained raw characteristic value stream delivers after re-listen',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      final stream = platform
          .device('device-a')
          .characteristic('180d', '2a37')
          .valueStream;
      final initialValues = <Uint8List>[];
      final firstSubscription = stream.listen(initialValues.add);
      addTearDown(firstSubscription.cancel);

      platform.handleCharacteristicValueChanged(
        'device-a',
        '180d',
        '2a37',
        Uint8List.fromList(<int>[1]),
      );
      await pumpEventQueue();
      expect(initialValues.map((value) => value.toList()), <List<int>>[
        <int>[1],
      ]);
      await firstSubscription.cancel();

      // Reuse the exact stream, rather than obtaining a new getter result.
      final resumedValues = <Uint8List>[];
      final secondSubscription = stream.listen(resumedValues.add);
      addTearDown(secondSubscription.cancel);
      platform.handleCharacteristicValueChanged(
        'device-a',
        '180d',
        '2a37',
        Uint8List.fromList(<int>[2]),
      );
      await pumpEventQueue();

      expect(resumedValues.map((value) => value.toList()), <List<int>>[
        <int>[2],
      ]);
      expect(
        platform.calls,
        isEmpty,
        reason: 'Raw streams do not enable notifications.',
      );
    },
  );
}
