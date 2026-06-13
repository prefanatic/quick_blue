import 'dart:convert';
import 'dart:typed_data';

String characteristicKey(String serviceUuid, String characteristicId) {
  return '$serviceUuid::$characteristicId';
}

Uint8List parseBleValue(String text) {
  final trimmed = text.trim();
  final normalized = trimmed
      .replaceAll(RegExp(r'0x', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s,;:-]+'), '');
  final looksHex =
      normalized.isNotEmpty &&
      normalized.length.isEven &&
      RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized);

  if (!looksHex) {
    return Uint8List.fromList(utf8.encode(text));
  }

  final bytes = <int>[];
  for (var i = 0; i < normalized.length; i += 2) {
    bytes.add(int.parse(normalized.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}

String formatBleValue(Uint8List value) {
  if (value.isEmpty) {
    return '<empty>';
  }
  return value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
}

String? formatUtf8Preview(Uint8List value) {
  if (value.isEmpty) {
    return null;
  }

  final String decoded;
  try {
    decoded = utf8.decode(value, allowMalformed: false);
  } on FormatException {
    return null;
  }
  if (decoded.trim().isEmpty) {
    return null;
  }

  final printable = decoded.runes.every((rune) {
    return rune == 0x09 || rune == 0x0a || rune == 0x0d || rune >= 0x20;
  });
  return printable ? decoded : null;
}
