import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _permissionChannel = MethodChannel(
  'com.example.quick_blue_example/permissions',
);

Future<bool> requestBleRangingPermission() async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return true;
  }

  return await _permissionChannel.invokeMethod<bool>(
        'requestRangingPermission',
      ) ??
      false;
}
