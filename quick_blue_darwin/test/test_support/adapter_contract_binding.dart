import 'package:quick_blue_darwin/quick_blue_darwin.dart';
import 'package:quick_blue_darwin/src/messages.g.dart' as messages;
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import '../../../quick_blue/test/test_support/adapter_contract_harness.dart';

AdapterContractBinding binding() => AdapterContractBinding(
  name: 'quick_blue_darwin',
  create: QuickBlueDarwin.new,
  connectedMethod: 'getConnectedPeripherals',
  codec: messages.QuickBlueApi.pigeonChannelCodec,
  unregister: () => messages.QuickBlueFlutterApi.setUp(null),
  valueEvent: (device, service, characteristic, value) =>
      messages.PlatformCharacteristicValueChanged(
        deviceId: device,
        serviceUuid: service,
        characteristicId: characteristic,
        value: value,
      ),
  directRead: true,
  securityDetails: <String, Object?>{'domain': 'CBATTErrorDomain', 'code': 5},
  securityDomain: 'CBATTErrorDomain',
  securityCode: 5,
  securityReason: QuickBlueSecurityErrorReason.insufficientAuthentication,
  expectedCapabilities: (enabled) => QuickBlueCapabilities(
    bonding: BluetoothBondingCapability.unsupported,
    mtu: BluetoothMtuCapability.readNegotiated,
    gattServiceChanges:
        BluetoothGattServiceChangeCapability.invalidatedServices,
    connectedDeviceLookup:
        BluetoothConnectedDeviceLookupCapability.requiresServiceUuids,
    supportsL2capSockets: true,
    supportsCompanionAssociation: false,
    supportsAppleAccessorySetup: enabled,
  ),
  eventCodec: messages.pigeonMethodCodec,
);
