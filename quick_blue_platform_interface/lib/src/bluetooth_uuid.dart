final _bluetoothUuidKeys = <String, String>{};

bool matchesBluetoothUuid(String left, String right) {
  if (left == right) {
    return true;
  }

  final normalizedLeft = canonicalBluetoothUuid(left);
  final normalizedRight = canonicalBluetoothUuid(right);
  return normalizedLeft != null &&
      normalizedRight != null &&
      normalizedLeft == normalizedRight;
}

String? canonicalBluetoothUuid(String uuid) {
  var cleaned = uuid.trim().toLowerCase();
  if (cleaned.startsWith('{') && cleaned.endsWith('}')) {
    cleaned = cleaned.substring(1, cleaned.length - 1);
  }
  cleaned = cleaned.replaceAll('-', '');
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

String bluetoothUuidKey(String uuid) {
  return _bluetoothUuidKeys.putIfAbsent(
    uuid,
    () => canonicalBluetoothUuid(uuid) ?? uuid,
  );
}
