import '../../test/test_support/fake_quick_blue_platform.dart' as support;

class FakeQuickBluePlatform extends support.FakeQuickBluePlatform {
  FakeQuickBluePlatform() {
    emitInitialBluetoothState = true;
  }
}
