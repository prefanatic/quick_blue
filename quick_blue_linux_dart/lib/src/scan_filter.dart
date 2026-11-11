bool meetsRssiThreshold(int rssi, int? minimumRssi) {
  return minimumRssi == null || rssi >= minimumRssi;
}
