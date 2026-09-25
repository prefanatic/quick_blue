// Copyright (c) 2026, the quick_blue authors.
// Use of this source code is governed by the BSD-3-Clause license.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue/quick_blue.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AccessorySetupKit FFI checks the app configuration', (_) async {
    expect(await QuickBlue.appleAccessorySetup.isSupported(), isTrue);

    final item = AppleAccessoryPickerItem(
      displayName: 'Test accessory',
      productImage: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVQ'
        '42mP8/x8AAusB9Wl6N7sAAAAASUVORK5CYII=',
      ),
      discovery: AppleAccessoryDiscovery(serviceUuid: '180D'),
    );

    await expectLater(
      QuickBlue.appleAccessorySetup.showPicker([item]),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'InvalidConfiguration')
            .having(
              (error) => error.message,
              'message',
              contains('NSAccessorySetupSupports'),
            ),
      ),
    );
  });
}
