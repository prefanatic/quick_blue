import 'package:bluez/bluez.dart';

String canonicalizeUuid(String uuid) {
  final cleaned = uuid.replaceAll('-', '').toLowerCase();
  if (cleaned.length == 4) {
    return '0000${cleaned}00001000800000805f9b34fb';
  }
  if (cleaned.length == 8) {
    return '${cleaned}00001000800000805f9b34fb';
  }
  if (cleaned.length == 32) {
    return cleaned;
  }
  throw ArgumentError.value(uuid, 'uuid', 'Unsupported UUID format');
}

String bluezUuidToCanonical(BlueZUUID uuid) {
  return uuid.toString().replaceAll('-', '').toLowerCase();
}

String formatUuid(BlueZUUID uuid) {
  return canonicalToDashed(bluezUuidToCanonical(uuid));
}

String canonicalToDashed(String canonical) {
  if (canonical.length != 32) {
    return canonical;
  }
  return '${canonical.substring(0, 8)}-${canonical.substring(8, 12)}-${canonical.substring(12, 16)}-${canonical.substring(16, 20)}-${canonical.substring(20)}';
}
