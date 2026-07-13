import 'dart:typed_data';

import 'bluetooth_uuid.dart';

/// Returns whether advertised service data matches a scan filter.
///
/// Filter entries use OR semantics. Each value is a payload prefix, and an
/// empty value matches any payload advertised for the corresponding UUID.
bool matchesServiceDataFilter(
  Map<String, Uint8List>? filter,
  Map<String, Uint8List> advertisedServiceData,
) {
  if (filter == null || filter.isEmpty) {
    return true;
  }

  return filter.entries.any(
    (filterEntry) => advertisedServiceData.entries.any(
      (advertisedEntry) =>
          matchesBluetoothUuid(filterEntry.key, advertisedEntry.key) &&
          _startsWithBytes(advertisedEntry.value, filterEntry.value),
    ),
  );
}

bool _startsWithBytes(Uint8List data, Uint8List prefix) {
  if (data.length < prefix.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index++) {
    if (data[index] != prefix[index]) {
      return false;
    }
  }
  return true;
}
