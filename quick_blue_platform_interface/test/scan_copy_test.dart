import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

/// Pins the copy rules the managed scan coordinator relies on: a fully
/// populated filter/options round-trips through [ScanFilter.copy] and
/// [ScanOptions.copy] with equality, and a later caller mutation does not leak
/// into the copy. This is the regression test for the hand-enumerated copies
/// that used to live in the scan lifecycle, where a newly added model field
/// would have been silently dropped from managed scans.
void main() {
  final payloadA = Uint8List.fromList(const [1, 2, 3]);
  final payloadB = Uint8List.fromList(const [4, 5]);

  ScanFilter fullyPopulatedFilter() => ScanFilter(
    serviceUuids: const ['180d', '180f'],
    serviceData: {'180a': payloadA, '180b': payloadB},
    manufacturerData: {0x004c: payloadA, 0x0075: payloadB},
    rssi: -40,
  );

  test('a fully populated filter copies with equality', () {
    final original = fullyPopulatedFilter();
    final copy = original.copy();

    expect(copy, equals(original));
    expect(copy.hashCode, original.hashCode);
    expect(copy.serviceUuids, ['180d', '180f']);
    expect(copy.serviceData, original.serviceData);
    expect(copy.manufacturerData, original.manufacturerData);
    expect(copy.rssi, -40);
  });

  test('filter contents are immutable at the boundary', () {
    // ScanFilter hands out defensive copies of its maps and stores an
    // unmodifiable list, so a caller cannot mutate what an active scan matches;
    // copy() preserving that (and copying defensively on the way in) is what
    // keeps a caller-supplied filter stable for a scan's lifetime.
    final original = fullyPopulatedFilter();

    expect(() => original.serviceUuids.add('180a'), throwsUnsupportedError);
    expect(original.serviceData, isNot(same(original.serviceData)));
    expect(original.manufacturerData, isNot(same(original.manufacturerData)));
    expect(original.copy(), equals(original));
  });

  test('null filter fields stay null through a copy', () {
    final original = ScanFilter();

    expect(original.copy(), equals(original));
    expect(original.copy().serviceData, isNull);
    expect(original.copy().manufacturerData, isNull);
    expect(original.copy().rssi, isNull);
  });

  test('fully populated scan options copy with equality', () {
    final linux = LinuxScanOptions(
      rssi: -50,
      pathloss: 60,
      transport: LinuxScanTransport.le,
      duplicateData: true,
      discoverable: false,
      pattern: 'test',
    );
    final original = ScanOptions(
      allowDuplicates: true,
      scanMode: ScanMode.lowLatency,
      android: AndroidScanOptions(
        scanMode: AndroidScanMode.balanced,
        callbackType: AndroidScanCallbackType.firstMatch,
        matchMode: AndroidScanMatchMode.aggressive,
        numOfMatches: AndroidScanNumOfMatches.few,
        reportDelay: Duration(seconds: 2),
        legacy: true,
        phy: AndroidScanPhy.leCoded,
      ),
      darwin: DarwinScanOptions(
        allowDuplicates: false,
        solicitedServiceUuids: const ['180a'],
      ),
      linux: linux,
      windows: WindowsScanOptions(
        signalStrengthFilter: const WindowsSignalStrengthFilter(
          inRangeThresholdInDBm: -70,
          outOfRangeThresholdInDBm: -90,
        ),
      ),
    );

    final copy = original.copy();
    expect(copy, equals(original));
    expect(copy.hashCode, original.hashCode);
    expect(copy.android, equals(original.android));
    expect(copy.darwin.allowDuplicates, isFalse);
    expect(copy.darwin.solicitedServiceUuids, ['180a']);
    expect(copy.linux, equals(linux));
    expect(copy.windows, equals(original.windows));
  });

  test('copied darwin options keep their own uuid list', () {
    final original = ScanOptions(
      darwin: DarwinScanOptions(
        allowDuplicates: true,
        solicitedServiceUuids: const ['180a'],
      ),
    );

    final copy = original.copy();

    expect(
      copy.darwin.solicitedServiceUuids,
      same(copy.darwin.solicitedServiceUuids),
    );
    expect(
      copy.darwin.solicitedServiceUuids,
      isNot(same(original.darwin.solicitedServiceUuids)),
    );
    expect(copy.darwin, equals(original.darwin));
  });
}
