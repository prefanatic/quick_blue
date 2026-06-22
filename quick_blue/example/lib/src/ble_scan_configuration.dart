import 'package:flutter/widgets.dart';
import 'package:quick_blue/quick_blue.dart';

class BleScanOptionParseException implements Exception {
  const BleScanOptionParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BleScanConfiguration {
  final serviceFilterController = TextEditingController();
  final androidReportDelayMillisController = TextEditingController();
  final darwinSolicitedServiceUuidsController = TextEditingController();
  final linuxRssiController = TextEditingController();
  final linuxPathlossController = TextEditingController();
  final linuxPatternController = TextEditingController();
  final windowsInRangeThresholdController = TextEditingController();
  final windowsOutOfRangeThresholdController = TextEditingController();
  final windowsOutOfRangeTimeoutMillisController = TextEditingController();
  final windowsSamplingIntervalMillisController = TextEditingController();

  bool? scanAllowDuplicates;
  ScanMode? scanMode;
  AndroidScanMode? androidScanMode;
  AndroidScanCallbackType androidCallbackType =
      AndroidScanCallbackType.allMatches;
  AndroidScanMatchMode androidMatchMode = AndroidScanMatchMode.sticky;
  AndroidScanNumOfMatches? androidNumOfMatches;
  bool? androidLegacy;
  AndroidScanPhy? androidPhy;
  bool? darwinAllowDuplicates;
  LinuxScanTransport linuxTransport = LinuxScanTransport.le;
  bool? linuxDuplicateData;
  bool? linuxDiscoverable;
  WindowsScanMode? windowsScanMode;

  ScanFilter scanFilter() {
    final serviceUuids = _splitUuidText(serviceFilterController.text);
    return serviceUuids.isEmpty
        ? ScanFilter.empty
        : ScanFilter(serviceUuids: serviceUuids);
  }

  ScanOptions scanOptions() {
    final androidReportDelayMillis = _optionalInt(
      androidReportDelayMillisController.text,
      'Android report delay',
    );
    final linuxRssi = _optionalInt(linuxRssiController.text, 'Linux RSSI');
    final linuxPathloss = _optionalInt(
      linuxPathlossController.text,
      'Linux pathloss',
    );
    final windowsInRangeThreshold = _optionalInt(
      windowsInRangeThresholdController.text,
      'Windows in-range threshold',
    );
    final windowsOutOfRangeThreshold = _optionalInt(
      windowsOutOfRangeThresholdController.text,
      'Windows out-of-range threshold',
    );
    final windowsOutOfRangeTimeoutMillis = _optionalInt(
      windowsOutOfRangeTimeoutMillisController.text,
      'Windows out-of-range timeout',
    );
    final windowsSamplingIntervalMillis = _optionalInt(
      windowsSamplingIntervalMillisController.text,
      'Windows sampling interval',
    );

    return ScanOptions(
      allowDuplicates: scanAllowDuplicates,
      scanMode: scanMode,
      android: AndroidScanOptions(
        scanMode: androidScanMode,
        callbackType: androidCallbackType,
        matchMode: androidMatchMode,
        numOfMatches: androidNumOfMatches,
        reportDelay: Duration(milliseconds: androidReportDelayMillis ?? 0),
        legacy: androidLegacy,
        phy: androidPhy,
      ),
      darwin: DarwinScanOptions(
        allowDuplicates: darwinAllowDuplicates,
        solicitedServiceUuids: _splitUuidText(
          darwinSolicitedServiceUuidsController.text,
        ),
      ),
      linux: LinuxScanOptions(
        rssi: linuxRssi,
        pathloss: linuxPathloss,
        transport: linuxTransport,
        duplicateData: linuxDuplicateData,
        discoverable: linuxDiscoverable,
        pattern: _optionalText(linuxPatternController.text),
      ),
      windows: WindowsScanOptions(
        scanningMode: windowsScanMode,
        signalStrengthFilter: _windowsSignalStrengthFilter(
          inRangeThresholdInDBm: windowsInRangeThreshold,
          outOfRangeThresholdInDBm: windowsOutOfRangeThreshold,
          outOfRangeTimeoutMillis: windowsOutOfRangeTimeoutMillis,
          samplingIntervalMillis: windowsSamplingIntervalMillis,
        ),
      ),
    );
  }

  int? _optionalInt(String text, String label) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final value = int.tryParse(trimmed);
    if (value == null) {
      throw BleScanOptionParseException('$label must be an integer.');
    }
    return value;
  }

  String? _optionalText(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> _splitUuidText(String text) {
    return text
        .split(RegExp(r'[\s,]+'))
        .map((uuid) => uuid.trim())
        .where((uuid) => uuid.isNotEmpty)
        .toList();
  }

  WindowsSignalStrengthFilter? _windowsSignalStrengthFilter({
    required int? inRangeThresholdInDBm,
    required int? outOfRangeThresholdInDBm,
    required int? outOfRangeTimeoutMillis,
    required int? samplingIntervalMillis,
  }) {
    if (inRangeThresholdInDBm == null &&
        outOfRangeThresholdInDBm == null &&
        outOfRangeTimeoutMillis == null &&
        samplingIntervalMillis == null) {
      return null;
    }
    return WindowsSignalStrengthFilter(
      inRangeThresholdInDBm: inRangeThresholdInDBm,
      outOfRangeThresholdInDBm: outOfRangeThresholdInDBm,
      outOfRangeTimeout: outOfRangeTimeoutMillis == null
          ? null
          : Duration(milliseconds: outOfRangeTimeoutMillis),
      samplingInterval: samplingIntervalMillis == null
          ? null
          : Duration(milliseconds: samplingIntervalMillis),
    );
  }

  void dispose() {
    serviceFilterController.dispose();
    androidReportDelayMillisController.dispose();
    darwinSolicitedServiceUuidsController.dispose();
    linuxRssiController.dispose();
    linuxPathlossController.dispose();
    linuxPatternController.dispose();
    windowsInRangeThresholdController.dispose();
    windowsOutOfRangeThresholdController.dispose();
    windowsOutOfRangeTimeoutMillisController.dispose();
    windowsSamplingIntervalMillisController.dispose();
  }
}
