@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:quick_blue_web/quick_blue_web.dart';
import 'package:quick_blue_example/web_bluetooth_hardware.dart';

@JS('eval')
external JSAny? evaluate(JSString source);

void main() {
  for (final standalone in [false, true]) {
    testWidgets(
      'explicit name-only selection preserves optional services ($standalone)',
      (tester) async {
        evaluate(
          '''globalThis.pickerOptions = null;
        Object.defineProperty(navigator, 'bluetooth', {configurable:true,
        value:{requestDevice:(options) => {globalThis.pickerOptions = options;
          return Promise.reject(new DOMException('fixture', 'NotAllowedError'));}}});'''
              .toJS,
        );
        QuickBluePlatform.instance = QuickBlueWeb();
        await tester.pumpWidget(const MaterialApp(home: HardwarePage()));
        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        final p = jsonDecode(controller.text) as Map<String, dynamic>;
        for (final key in ['adapter', 'peripheral', 'firmware']) {
          p[key] = 'fixture';
        }
        p['namePrefix'] = 'LEDnetWF0200A36292D3';
        p['filterServices'] = <String>[];
        p['optionalServices'] = ['fe00', 'ffff'];
        p['readCharacteristic'] = '';
        controller.text = jsonEncode(p);
        final button = find.text(
          standalone
              ? 'Open chooser — press Cancel'
              : 'Select device and run loops',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        final options =
            jsonDecode(
                  (evaluate('JSON.stringify(globalThis.pickerOptions)'.toJS)
                          as JSString)
                      .toDart,
                )
                as Map<String, dynamic>;
        expect((options['filters'] as List).single, {
          'namePrefix': 'LEDnetWF0200A36292D3',
        });
        expect(options['optionalServices'], [
          '0000fe00-0000-1000-8000-00805f9b34fb',
          '0000ffff-0000-1000-8000-00805f9b34fb',
        ]);
      },
    );
  }

  Map<String, dynamic> report(WidgetTester tester) =>
      jsonDecode(
            tester.widget<SelectableText>(find.byType(SelectableText)).data!,
          )
          as Map<String, dynamic>;

  Future<void> open(WidgetTester tester, String error) async {
    evaluate(
      '''Object.defineProperty(navigator, 'bluetooth', {configurable:true,
      value: {requestDevice: () => ${error == 'pending' ? 'new Promise(() => {})' : "Promise.reject(new DOMException('fixture', '$error'))"}}});'''
          .toJS,
    );
    if (error == 'unavailable') {
      evaluate(
        "Object.defineProperty(navigator, 'bluetooth', {configurable:true, value:undefined})"
            .toJS,
      );
    }
    QuickBluePlatform.instance = QuickBlueWeb(
      operationTimeout: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(const MaterialApp(home: HardwarePage()));
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    final p = jsonDecode(controller.text) as Map<String, dynamic>;
    for (final key in ['adapter', 'peripheral', 'firmware']) {
      p[key] = 'fixture';
    }
    controller.text = jsonEncode(p);
    final button = find.text('Open chooser — press Cancel');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('cancel-first cannot pass full suite and has provenance', (
    tester,
  ) async {
    await open(tester, 'NotFoundError');
    expect(find.text('Yes, I pressed Cancel'), findsOneWidget);
    await tester.tap(find.text('Yes, I pressed Cancel'));
    await tester.pumpAndSettle();
    final result = report(tester);
    expect(result['aggregate'], 'BLOCKED');
    expect(result['started'], isNotNull);
    expect(result['profile'], isNotNull);
    final stages = result['stages'] as List;
    expect(
      stages.any(
        (dynamic s) => s['stage'] == '1 connect' && s['result'] == 'BLOCKED',
      ),
      true,
    );
  });

  testWidgets('confirmation times out and releases UI', (tester) async {
    await open(tester, 'NotFoundError');
    await tester.pump(const Duration(seconds: 26));
    await tester.pumpAndSettle();
    expect(find.text('Yes, I pressed Cancel'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(report(tester)['aggregate'], 'BLOCKED');
  });

  testWidgets('denial is not eligible for cancellation confirmation', (
    tester,
  ) async {
    await open(tester, 'NotAllowedError');
    await tester.pumpAndSettle();
    expect(find.text('Yes, I pressed Cancel'), findsNothing);
    expect(report(tester)['aggregate'], 'BLOCKED');
  });

  testWidgets('loss-first and missing metadata remain BLOCKED', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HardwarePage()));
    final button = find.text('Manual loss / recovery check');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(report(tester)['aggregate'], 'BLOCKED');
    expect(report(tester)['started'], isNotNull);
    expect(report(tester)['profile'], isNull);
  });

  for (final outcome in ['pending', 'unavailable']) {
    testWidgets('$outcome cannot be confirmed as cancellation', (tester) async {
      await open(tester, outcome);
      await tester.pump(const Duration(seconds: 26));
      await tester.pumpAndSettle();
      expect(find.text('Yes, I pressed Cancel'), findsNothing);
      expect(report(tester)['aggregate'], 'BLOCKED');
    });
  }

  testWidgets(
    'missing hardware profile is BLOCKED and read-only is the default',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HardwarePage()));
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      final run = find.text('Select device and run loops');
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();
      final report = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      final decoded = jsonDecode(report) as Map<String, dynamic>;
      expect(decoded['aggregate'], 'BLOCKED');
      expect(report, contains('Provide adapter'));
    },
  );
  testWidgets(
    'unavailable real browser API blocks all hardware stages, never PASS',
    (tester) async {
      evaluate(
        "Object.defineProperty(navigator, 'bluetooth', {configurable:true, value:undefined})"
            .toJS,
      );
      QuickBluePlatform.instance = QuickBlueWeb();
      await tester.pumpWidget(const MaterialApp(home: HardwarePage()));
      final input = tester.widget<TextField>(find.byType(TextField));
      final p = jsonDecode(input.controller!.text) as Map<String, dynamic>;
      // Explicitly a UI-validation fixture, not a claim about real peripherals.
      p['adapter'] = 'fixture';
      p['peripheral'] = 'fixture';
      p['firmware'] = 'fixture';
      input.controller!.text = jsonEncode(p);
      final run = find.text('Select device and run loops');
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();
      final decoded =
          jsonDecode(
                tester
                    .widget<SelectableText>(find.byType(SelectableText))
                    .data!,
              )
              as Map<String, dynamic>;
      expect(decoded['aggregate'], 'BLOCKED');
      final stages = (decoded['stages'] as List).cast<Map<String, dynamic>>();
      expect(
        stages.where((s) => s['stage'] == 'selection').single['result'],
        'BLOCKED',
      );
      expect(stages.any((s) => s['result'] == 'PASS'), false);
      expect(decoded['selectedDeviceId'], null);
    },
  );
}
