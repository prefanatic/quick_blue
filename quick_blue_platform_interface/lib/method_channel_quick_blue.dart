import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'quick_blue_platform_interface.dart';

class MethodChannelQuickBlue extends QuickBluePlatform {
  static const MethodChannel _method = const MethodChannel('quick_blue/method');
  static const _event_scanResult = const EventChannel(
    'quick_blue/event.scanResult',
  );
  static const _message_connector = const BasicMessageChannel(
    'quick_blue/message.connector',
    StandardMessageCodec(),
  );

  static final _l2CapEventController =
      StreamController<BleL2CapSocketEvent>.broadcast();

  MethodChannelQuickBlue() {
    _message_connector.setMessageHandler(_handleConnectorMessage);
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    bool result = await _method.invokeMethod('isBluetoothAvailable');
    return result;
  }

  @override
  Future<void> startScan({ScanFilter scanFilter = ScanFilter.empty}) {
    return _method.invokeMethod('startScan', {
      'serviceUuids': scanFilter.serviceUuids,
      'manufacturerData': scanFilter.manufacturerData,
    });
  }

  @override
  Future<void> stopScan() {
    return _method.invokeMethod('stopScan');
  }

  Stream<BlueScanResult> _scanResultStream = _event_scanResult
      .receiveBroadcastStream({'name': 'scanResult'})
      .map((item) => BlueScanResult.fromMap(item));

  @override
  Stream<BlueScanResult> get scanResultStream => _scanResultStream;

  @override
  Future<void> connect(String deviceId) {
    return _method.invokeMethod('connect', {'deviceId': deviceId});
  }

  @override
  Future<void> disconnect(String deviceId) {
    return _method.invokeMethod('disconnect', {'deviceId': deviceId});
  }

  @override
  Future<bool> isCompanionAssociationSupported() async {
    return Platform.isAndroid;
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Companion device association is only supported on Android.',
      );
    }
    final data = await _method.invokeMethod('companionAssociate', {
      'singleDevice': request.singleDevice,
      'filters': request.filters.map(_bleCompanionFilterToMap).toList(),
    });
    if (data == null) {
      return null;
    }
    return CompanionAssociation.fromMap(data as Map);
  }

  @override
  Future<void> companionDisassociate(int associationId) {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Companion device association is only supported on Android.',
      );
    }
    return _method.invokeMethod('companionDisassociate', {
      'associationId': associationId,
    });
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Companion device association is only supported on Android.',
      );
    }
    final data = await _method.invokeListMethod('companionListAssociations');
    if (data == null) {
      return const <CompanionAssociation>[];
    }
    return data
        .map((item) => CompanionAssociation.fromMap(item as Map))
        .toList();
  }

  Map<String, Object?> _bleCompanionFilterToMap(BleCompanionFilter filter) {
    return <String, Object?>{
      if (filter.deviceId != null) 'deviceId': filter.deviceId,
      if (filter.namePattern != null) 'namePattern': filter.namePattern,
      'serviceUuids': filter.serviceUuids,
      if (filter.manufacturerData != null)
        'manufacturerData': filter.manufacturerData,
    };
  }

  @override
  Future<void> discoverServices(String deviceId) {
    return _method.invokeMethod('discoverServices', {'deviceId': deviceId});
  }

  Future<void> _handleConnectorMessage(dynamic message) async {
    if (message['ConnectionState'] != null) {
      final deviceId = message['deviceId'];
      final connectionState = BlueConnectionState.parse(
        message['ConnectionState'],
      );
      final status = switch (message['status']) {
        'success' => BleStatus.success,
        _ => BleStatus.failure,
      };
      onConnectionChanged?.call(deviceId, connectionState, status);
    } else if (message['ServiceState'] != null) {
      if (message['ServiceState'] == 'discovered') {
        String deviceId = message['deviceId'];
        String service = message['service'];
        final characteristics = _parseCharacteristics(
          message['characteristics'] as List,
        );
        handleServiceDiscovered(deviceId, service, characteristics);
      } else if (message['ServiceState'] == 'complete') {
        String deviceId = message['deviceId'];
        onServiceDiscoveryComplete(deviceId);
      }
    } else if (message['characteristicValue'] != null) {
      String deviceId = message['deviceId'];
      var characteristicValue = message['characteristicValue'];
      String service = characteristicValue['service'] ?? '';
      String characteristic = characteristicValue['characteristic'];
      final value = characteristicValue['value'];
      if (value == null) {
        // TODO: should this be surfaced as an error?
        return;
      }
      final valueBytes = Uint8List.fromList(
        characteristicValue['value'],
      ); // In case of _Uint8ArrayView
      handleCharacteristicValueChanged(
        deviceId,
        service,
        characteristic,
        valueBytes,
      );
    } else if (message['mtuConfig'] != null) {
      _mtuConfigController.add(message['mtuConfig']);
    } else if (message['l2capStatus'] != null) {
      final String deviceId = message['deviceId'];
      final String l2CapStatus = message['l2capStatus'];
      final Uint8List? data = message['data'];
      final String? error = message['error'];

      final event = switch (l2CapStatus) {
        'opened' => BleL2CapSocketEventOpened(deviceId: deviceId),
        'closed' => BleL2CapSocketEventClosed(deviceId: deviceId),
        'stream' => BleL2CapSocketEventData(deviceId: deviceId, data: data!),
        'error' => BleL2CapSocketEventError(deviceId: deviceId, error: error),
        _ => throw 'Unknown L2Cap event $l2CapStatus',
      };

      _l2CapEventController.add(event);
    }
  }

  List<BluetoothCharacteristicInfo> _parseCharacteristics(List raw) {
    return raw
        .map((value) {
          if (value is String) {
            return BluetoothCharacteristicInfo(uuid: value);
          }
          final map = (value as Map).cast<String, Object?>();
          return BluetoothCharacteristicInfo(
            uuid: map['uuid'] as String,
            canRead: map['canRead'] as bool? ?? false,
            canWriteWithResponse: map['canWriteWithResponse'] as bool? ?? false,
            canWriteWithoutResponse:
                map['canWriteWithoutResponse'] as bool? ?? false,
            canNotify: map['canNotify'] as bool? ?? false,
            canIndicate: map['canIndicate'] as bool? ?? false,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    return _method.invokeMethod('setNotifiable', {
      'deviceId': deviceId,
      'service': service,
      'characteristic': characteristic,
      'bleInputProperty': bleInputProperty.value,
    });
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) {
    return _method.invokeMethod('readValue', {
      'deviceId': deviceId,
      'service': service,
      'characteristic': characteristic,
    });
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    return _method.invokeMethod('writeValue', {
      'deviceId': deviceId,
      'service': service,
      'characteristic': characteristic,
      'value': value,
      'bleOutputProperty': bleOutputProperty.value,
    });
  }

  // FIXME Close
  final _mtuConfigController = StreamController<int>.broadcast();

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    await _method.invokeMethod('requestMtu', {
      'deviceId': deviceId,
      'expectedMtu': expectedMtu,
    });
    return await _mtuConfigController.stream.first;
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) async {
    await _method.invokeMethod('openL2cap', {'deviceId': deviceId, 'psm': psm});

    // Wait for the open status.
    await _l2CapEventController.stream
        .where((event) => event.deviceId == deviceId)
        .firstWhere((event) => event is BleL2CapSocketEventOpened)
        .timeout(const Duration(seconds: 5));

    return BleL2capSocket(
      sink: _L2capSink(channel: _method, deviceId: deviceId),
      stream: _l2CapEventController.stream.where(
        (event) => event.deviceId == deviceId,
      ),
    );
  }
}

class _L2capSink implements EventSink<Uint8List> {
  _L2capSink({required this.channel, required this.deviceId});

  final MethodChannel channel;
  final String deviceId;

  @override
  void add(Uint8List event) {
    channel.invokeMethod('_l2cap_write', {'deviceId': deviceId, 'data': event});
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future close() async {}
}
