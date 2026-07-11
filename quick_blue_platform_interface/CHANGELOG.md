## 0.5.0 - 2026-07-10

- Reject overlapping connection operations for the same device while allowing
  different devices to operate concurrently.
- Cover notification and discovery failure/retry lifecycle behavior.
- Add a self-contained strict analyzer configuration.
- Share notification ownership across concurrent characteristic listeners.
- Coalesce concurrent service discovery for the same device.
- Add lifecycle-managed scanning, Bluetooth state, device, GATT,
  characteristic, pairing, and companion-association APIs.
- Add scan filters and options, service data, characteristic metadata, and
  service-scoped characteristic values.
- Add typed operation failures and value-like models.
- Remove the legacy method-channel fallback in favor of federated platform
  implementations.
