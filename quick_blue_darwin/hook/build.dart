// Copyright (c) 2026, the quick_blue authors.
// Use of this source code is governed by the BSD-3-Clause license.

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final target = input.config.code.targetOS;
    if (target != OS.iOS && target != OS.macOS) return;

    await CBuilder.library(
      name: 'quick_blue_darwin_bindings',
      assetName: 'quick_blue_darwin_bindings.dylib',
      sources: [
        'src/quick_blue_dispatch.m',
        'src/generated/core_bluetooth.g.m',
        if (target == OS.iOS) 'src/generated/accessory_setup_kit.g.m',
      ],
      includes: ['tool'],
      frameworks: [
        'Foundation',
        'CoreBluetooth',
        if (target == OS.iOS) 'UIKit',
      ],
      language: Language.objectiveC,
      flags: [
        '-fobjc-arc',
        if (target == OS.iOS) ...['-weak_framework', 'AccessorySetupKit'],
      ],
    ).run(input: input, output: output);
  });
}
