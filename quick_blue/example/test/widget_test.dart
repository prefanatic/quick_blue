import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:quick_blue_example/main.dart';
import 'package:quick_blue_example/src/ble_explorer_page.dart';
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

    expect(find.byKey(const ValueKey('ble_scan_header')), findsOneWidget);
    expect(find.text('Scan 10s'), findsOneWidget);
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

  testWidgets('shows only current platform-specific scan options', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: const BleExplorerPage(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ble_scan_options_panel')));
    await tester.pumpAndSettle();

    expect(find.text('Allow duplicates'), findsOneWidget);
    expect(find.text('RSSI'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Android mode'), findsNothing);
    expect(find.text('Solicited services'), findsNothing);
    expect(find.text('In range dBm'), findsNothing);
  });

  testWidgets('cancels report delay input without errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: const BleExplorerPage(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ble_scan_options_panel')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Report delay ms'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows concrete default scan option values', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: const BleExplorerPage(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ble_scan_options_panel')));
    await tester.pumpAndSettle();

    expect(find.text('Default (Low latency)'), findsOneWidget);
    expect(find.text('Default (0 ms)'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
  });

  testWidgets('uses one scan mode tile for Android', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: const BleExplorerPage(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ble_scan_options_panel')));
    await tester.pumpAndSettle();

    expect(find.text('Android mode'), findsOneWidget);
    expect(find.text('Scan mode'), findsNothing);
  });

  testWidgets('starts with events collapsed and toggles from its header', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final panel = find.byKey(const ValueKey('ble_events_panel'));
    final collapsedHeight = tester.getSize(panel).height;
    expect(collapsedHeight, lessThan(60));
    expect(
      find.byKey(const ValueKey('ble_events_resize_handle')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('ble_events_header')));
    await tester.pump();

    expect(tester.getSize(panel).height, greaterThan(collapsedHeight));
    expect(
      find.byKey(const ValueKey('ble_events_resize_handle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('ble_events_header')));
    await tester.pump();

    expect(tester.getSize(panel).height, collapsedHeight);
    expect(
      find.byKey(const ValueKey('ble_events_resize_handle')),
      findsNothing,
    );
  });

  testWidgets('resizes the expanded events panel by dragging its handle', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ble_events_header')));
    await tester.pump();

    final panel = find.byKey(const ValueKey('ble_events_panel'));
    final before = tester.getSize(panel).height;
    await tester.drag(
      find.byKey(const ValueKey('ble_events_resize_handle')),
      const Offset(0, -48),
    );
    await tester.pump();

    expect(tester.getSize(panel).height, greaterThan(before));
  });

  testWidgets('resizes the wide scan pane by dragging its handle', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final panel = find.byKey(const ValueKey('ble_scan_pane'));
    final before = tester.getSize(panel).width;
    await tester.drag(
      find.byKey(const ValueKey('ble_scan_resize_handle')),
      const Offset(80, 0),
    );
    await tester.pump();

    expect(tester.getSize(panel).width, greaterThan(before));
  });
}
