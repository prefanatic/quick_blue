import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue/src/messages.g.dart' as messages;

import 'test_support/adapter_contract_harness.dart';

AdapterContractBinding binding() => AdapterContractBinding(
  name: 'quick_blue',
  create: QuickBlueAndroid.new,
  codec: messages.QuickBlueApi.pigeonChannelCodec,
  eventCodec: messages.pigeonMethodCodec,
  mtuEvent: () => messages.PlatformMtuChange(deviceId: 'device-a', mtu: 247),
  unregister: () => messages.QuickBlueFlutterApi.setUp(null),
  valueEvent: (device, service, characteristic, value) =>
      messages.PlatformCharacteristicValueChanged(
        deviceId: device,
        serviceUuid: service,
        characteristicId: characteristic,
        value: value,
      ),
  directRead: true,
  securityDetails: 5,
  securityDomain: 'android.bluetooth.BluetoothGatt',
  securityCode: 5,
  securityReason: QuickBlueSecurityErrorReason.insufficientAuthentication,
  expectedCapabilities: (enabled) => QuickBlueCapabilities(
    bonding: BluetoothBondingCapability.queryPairAndObserve,
    mtu: BluetoothMtuCapability.requestable,
    gattServiceChanges: enabled
        ? BluetoothGattServiceChangeCapability.databaseOnly
        : BluetoothGattServiceChangeCapability.unsupported,
    connectedDeviceLookup:
        BluetoothConnectedDeviceLookupCapability.unrestricted,
    supportsL2capSockets: enabled,
    supportsCompanionAssociation: enabled,
    supportsAppleAccessorySetup: false,
  ),
  capabilityReply: (enabled) => messages.PlatformCapabilities(
    supportsGattServiceChanges: enabled,
    supportsL2capSockets: enabled,
    supportsCompanionAssociation: enabled,
  ),
);

void main() => registerAdapterContracts(binding());
