import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_example/src/ble_value_codec.dart';

void main() {
  group('parseBleValue', () {
    test('parses compact hex', () {
      expect(parseBleValue('0102ff'), Uint8List.fromList(<int>[1, 2, 255]));
    });

    test('parses separated hex', () {
      expect(parseBleValue('0x01 02:ff'), Uint8List.fromList(<int>[1, 2, 255]));
    });

    test('falls back to UTF-8 text', () {
      expect(parseBleValue('hello'), Uint8List.fromList(utf8.encode('hello')));
    });
  });

  group('formatBleValue', () {
    test('formats bytes as lowercase hex', () {
      expect(formatBleValue(Uint8List.fromList(<int>[1, 2, 255])), '01 02 ff');
    });

    test('formats empty values clearly', () {
      expect(formatBleValue(Uint8List(0)), '<empty>');
    });
  });

  group('formatUtf8Preview', () {
    test('formats printable UTF-8', () {
      expect(
        formatUtf8Preview(Uint8List.fromList(utf8.encode('hello'))),
        'hello',
      );
    });

    test('ignores binary data', () {
      expect(formatUtf8Preview(Uint8List.fromList(<int>[0xff, 0x00])), isNull);
    });
  });
}
