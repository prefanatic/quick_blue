## 0.5.0 - 2026-07-10

- Report MTU requests as unsupported instead of returning an unverified value.
- Make initialization single-flight and route asynchronous cleanup failures to
  logging handlers.
- Accept advertisements whose RSSI equals the configured minimum threshold.
- Bring the BlueZ implementation up to the current QuickBlue API.
- Add Bluetooth state, scan filters, service data, connected devices, pairing,
  service discovery, and characteristic operations.
- Improve repeated scanning, characteristic lookup, and notification
  throughput.
