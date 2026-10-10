import 'package:quick_blue_windows/quick_blue_windows.dart';
import 'package:quick_blue_windows/src/messages.g.dart' as messages;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import '../../../quick_blue/test/test_support/adapter_contract_harness.dart';

AdapterContractBinding binding() => AdapterContractBinding(
  name: 'quick_blue_windows',
  create: QuickBlueWindows.new,
  codec: messages.QuickBlueApi.pigeonChannelCodec,
  unregister: () => messages.QuickBlueFlutterApi.setUp(null),
  valueEvent: (device, service, characteristic, value) =>
      messages.PlatformCharacteristicValueChanged(
        deviceId: device,
        serviceUuid: service,
        characteristicId: characteristic,
        value: value,
      ),
  directRead: false,
  securityDetails: 3,
  securityDomain:
      'Windows.Devices.Bluetooth.GenericAttributeProfile.GattCommunicationStatus',
  securityCode: 3,
  securityReason: QuickBlueSecurityErrorReason.insufficientAuthorization,
  expectedCapabilities: (enabled) => QuickBlueCapabilities(
    bonding: BluetoothBondingCapability.unsupported,
    mtu: BluetoothMtuCapability.readNegotiated,
    gattServiceChanges: BluetoothGattServiceChangeCapability.databaseOnly,
    connectedDeviceLookup:
        BluetoothConnectedDeviceLookupCapability.unrestricted,
    supportsL2capSockets: false,
    supportsCompanionAssociation: false,
    supportsAppleAccessorySetup: false,
  ),
);
