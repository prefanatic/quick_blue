import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show PlatformException;

import 'availability.g.dart';

/// Resolve lazily: Dart plugin registration can precede JNI registration.
QuickBlueAvailabilityApi? createNativeAvailabilityApi() {
  if (!Platform.isAndroid) return null;
  final engineId = PlatformDispatcher.instance.engineId;
  // BackgroundIsolateBinaryMessenger routes to its registering root engine.
  // A worker has no native engine ID; never invoke JNI's latest-engine fallback.
  if (engineId == null) return null;
  final name = 'quick_blue.availability.$engineId';
  try {
    // Never use the preview resolver's default/latest-engine fallback.
    return QuickBlueAvailabilityApi.createWithNativeInteropApi(
      messageChannelSuffix: name,
    );
  } on ArgumentError catch (error) {
    // Pigeon 30.0.2 reports ONLY resolution-time absence as ArgumentError.
    // Match that precise generated diagnostic; do not mask codec/JNI defects
    // or retry any operation. Retained handles already use this native code.
    if (error.message != 'No instance named $name has been registered.') {
      rethrow;
    }
    throw PlatformException(
      code: 'unregistered-instance',
      message: 'QuickBlueAvailabilityApi has not been registered.',
      details: name,
    );
  }
}
