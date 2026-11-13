import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'availability.g.dart';

/// Resolve lazily: Dart plugin registration can precede JNI registration.
QuickBlueAvailabilityApi? createNativeAvailabilityApi() {
  if (!Platform.isAndroid) return null;
  final engineId = PlatformDispatcher.instance.engineId;
  if (engineId == null) {
    throw UnsupportedError(
      'Quick Blue native availability requires a Flutter engine root isolate.',
    );
  }
  // Never use the preview resolver's default/latest-engine fallback.
  return QuickBlueAvailabilityApi.createWithNativeInteropApi(
    messageChannelSuffix: 'quick_blue.availability.$engineId',
  );
}
