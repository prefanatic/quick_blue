// Copyright (c) 2026, the quick_blue authors.
// Use of this source code is governed by the BSD-3-Clause license.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:objective_c/objective_c.dart' as objc;
import 'package:quick_blue_darwin/src/third_party/core_bluetooth.g.dart' as cb;

void main() {
  test('CoreBluetooth FFI resolves Apple and generated symbols', () {
    if (!Platform.isMacOS && !Platform.isIOS) return;

    final uuid = cb.CBUUID.UUIDWithString(objc.NSString('180D'));
    expect(uuid.UUIDString.toDartString(), '180D');

    final delegate = cb.CBCentralManagerDelegate$Builder.implement(
      centralManagerDidUpdateState_: (_) {},
    );
    expect(cb.CBCentralManagerDelegate.conformsTo(delegate), isTrue);
  });
}
