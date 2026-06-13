import 'package:flutter_test/flutter_test.dart';
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
}
