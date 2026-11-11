import 'package:bluez/bluez.dart';
import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import '../generated_bindings.dart';
import 'l2cap_channel.dart';
import 'native_libraries.dart';

typedef L2capChannelFactory =
    L2capChannel Function({
      required String deviceId,
      required int psm,
      required int addressType,
      required Logger logger,
    });

/// Resolves BlueZ endpoints and opens native LE L2CAP channels.
///
/// Native libraries are loaded only when a known device is opened. Socket
/// ownership, framing and cleanup remain the responsibility of [L2capChannel].
class LinuxL2capEndpoint {
  LinuxL2capEndpoint({
    required BlueZClient client,
    required Map<String, BlueZDevice> devices,
    required Logger logger,
    L2capChannelFactory? channelFactory,
  }) : _client = client,
       _devices = devices,
       _logger = logger {
    _channelFactory = channelFactory ?? _createChannel;
  }

  final BlueZClient _client;
  final Map<String, BlueZDevice> _devices;
  final Logger _logger;
  late final L2capChannelFactory _channelFactory;
  late final Libc _libc = Libc();
  LibBluetooth? _libBluetooth;

  Future<BleL2capSocket> open(String deviceId, int psm) async {
    final device =
        _devices[deviceId] ??
        _client.devices.firstWhereOrNull((d) => d.address == deviceId);
    if (device == null) {
      throw QuickBlueException(
        code: QuickBlueErrorCode.notFound,
        operation: 'openL2cap',
        deviceId: deviceId,
        message: 'Bluetooth device $deviceId is not known.',
      );
    }

    _devices[deviceId] = device;
    final channel = _channelFactory(
      deviceId: deviceId,
      psm: psm,
      addressType: device.addressType == BlueZAddressType.random
          ? BDADDR_LE_RANDOM
          : BDADDR_LE_PUBLIC,
      logger: _logger,
    );
    try {
      return await channel.open();
    } on Object catch (error, stackTrace) {
      _logger.severe(
        'Unable to open L2CAP channel to $deviceId',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  L2capChannel _createChannel({
    required String deviceId,
    required int psm,
    required int addressType,
    required Logger logger,
  }) {
    final bluetooth = _libBluetooth ??= LibBluetooth();
    return L2capChannel(
      deviceId: deviceId,
      psm: psm,
      addressType: addressType,
      libc: _libc,
      bluetooth: bluetooth,
      logger: logger,
    );
  }
}
