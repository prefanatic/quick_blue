import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:quick_blue_example/main.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuickBluePlatform previousPlatform;
  late FakeQuickBluePlatform platform;

  setUp(() {
    previousPlatform = QuickBluePlatform.instance;
    platform = FakeQuickBluePlatform();
    QuickBluePlatform.instance = platform;
  });

  tearDown(() async {
    QuickBluePlatform.instance = previousPlatform;
    await platform.dispose();
  });

  testWidgets('shows the BLE explorer shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('quick_blue example'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Events (1)'), findsOneWidget);
  });

  testWidgets('follows system brightness with light and dark themes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme, isNotNull);
    expect(app.darkTheme, isNotNull);
    expect(app.theme!.brightness, Brightness.light);
    expect(app.darkTheme!.brightness, Brightness.dark);
  });
}
