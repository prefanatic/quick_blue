import 'package:test/test.dart';
import 'package:quick_blue_core/quick_blue_core.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'test_support/fake_quick_blue_platform.dart';

class ChooserPlatform extends FakeQuickBluePlatform {
  bool invoked = false;
  List<String>? filters;
  List<String>? optional;
  String? prefix;
  @override
  Future<BluetoothDevice> requestDevice({
    List<String> serviceUuids = const [],
    List<String> optionalServices = const [],
    String? namePrefix,
  }) {
    invoked = true;
    filters = serviceUuids;
    optional = optionalServices;
    prefix = namePrefix;
    return Future.value(device('selected'));
  }
}

void main() {
  test(
    'chooser facade delegates synchronously without availability preflight',
    () async {
      final platform = ChooserPlatform();
      QuickBluePlatform.instance = platform;
      final pending = QuickBlue.requestDevice(
        serviceUuids: ['180f'],
        optionalServices: ['180a'],
        namePrefix: 'Known',
      );
      expect(platform.invoked, true);
      expect(platform.calls, isEmpty);
      expect(platform.filters, ['180f']);
      expect(platform.optional, ['180a']);
      expect(platform.prefix, 'Known');
      expect((await pending).deviceId, 'selected');
    },
  );
  test('native implementations inherit explicit unsupported chooser', () async {
    QuickBluePlatform.instance = FakeQuickBluePlatform();
    await expectLater(
      QuickBlue.requestDevice(),
      throwsA(
        isA<QuickBlueException>().having(
          (e) => e.code,
          'code',
          QuickBlueErrorCode.unsupported,
        ),
      ),
    );
  });
}
