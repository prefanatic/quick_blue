import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  group('matchesServiceDataFilter', () {
    test('accepts all advertisements when no filter is configured', () {
      expect(
        matchesServiceDataFilter(null, const <String, Uint8List>{}),
        isTrue,
      );
    });

    test('matches UUIDs and payload prefixes', () {
      expect(
        matchesServiceDataFilter(
          <String, Uint8List>{
            '180a': Uint8List.fromList(<int>[1, 2]),
          },
          <String, Uint8List>{
            '0000180a-0000-1000-8000-00805f9b34fb': Uint8List.fromList(<int>[
              1,
              2,
              3,
            ]),
          },
        ),
        isTrue,
      );
    });

    test('matches any configured entry', () {
      expect(
        matchesServiceDataFilter(
          <String, Uint8List>{
            '180a': Uint8List.fromList(<int>[1]),
            '180f': Uint8List.fromList(<int>[2]),
          },
          <String, Uint8List>{
            '180f': Uint8List.fromList(<int>[2, 3]),
          },
        ),
        isTrue,
      );
    });

    test('uses an empty prefix to match any payload for a UUID', () {
      expect(
        matchesServiceDataFilter(
          <String, Uint8List>{'180a': Uint8List(0)},
          <String, Uint8List>{
            '{0000180A-0000-1000-8000-00805F9B34FB}': Uint8List.fromList(<int>[
              9,
              8,
            ]),
          },
        ),
        isTrue,
      );
    });

    test('rejects missing UUIDs and mismatched prefixes', () {
      final advertised = <String, Uint8List>{
        '180a': Uint8List.fromList(<int>[1, 2]),
      };

      expect(
        matchesServiceDataFilter(<String, Uint8List>{
          '180f': Uint8List(0),
        }, advertised),
        isFalse,
      );
      expect(
        matchesServiceDataFilter(<String, Uint8List>{
          '180a': Uint8List.fromList(<int>[1, 3]),
        }, advertised),
        isFalse,
      );
    });
  });
}
