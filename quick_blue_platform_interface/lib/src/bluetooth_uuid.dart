bool matchesBluetoothUuid(String left, String right) {
  if (left == right) {
    return true;
  }

  final normalizedLeft = _normalizeBluetoothUuid(left);
  final normalizedRight = _normalizeBluetoothUuid(right);
  return normalizedLeft != null &&
      normalizedRight != null &&
      normalizedLeft == normalizedRight;
}

String? _normalizeBluetoothUuid(String uuid) {
  final cleaned = uuid.replaceAll('-', '').toLowerCase();
  if (cleaned.length == 4) {
    return '0000$cleaned'
        '00001000800000805f9b34fb';
  }
  if (cleaned.length == 8) {
    return '$cleaned'
        '00001000800000805f9b34fb';
  }
  if (cleaned.length == 32) {
    return cleaned;
  }
  return null;
}
