import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:quick_blue/quick_blue.dart';

class BleGattSession {
  final services = <BluetoothService>[];
  final latestValues = <String, Uint8List>{};

  final _writeControllers = <String, TextEditingController>{};
  final _writeWithoutResponseKeys = <String>{};
  final _notificationSubscriptions = <String, StreamSubscription<Uint8List>>{};

  Set<String> get notificationKeys => _notificationSubscriptions.keys.toSet();

  TextEditingController writeControllerFor(String key) {
    return _writeControllers.putIfAbsent(key, TextEditingController.new);
  }

  String writeTextFor(String key) {
    return _writeControllers[key]?.text ?? '';
  }

  bool writeWithoutResponseFor(String key) {
    return _writeWithoutResponseKeys.contains(key);
  }

  void setWriteWithoutResponse(String key, bool enabled) {
    if (enabled) {
      _writeWithoutResponseKeys.add(key);
    } else {
      _writeWithoutResponseKeys.remove(key);
    }
  }

  StreamSubscription<Uint8List>? takeNotification(String key) {
    return _notificationSubscriptions.remove(key);
  }

  void setNotification(String key, StreamSubscription<Uint8List> subscription) {
    _notificationSubscriptions[key] = subscription;
  }

  void removeNotification(String key) {
    _notificationSubscriptions.remove(key);
  }

  void setLatestValue(String key, Uint8List value) {
    latestValues[key] = value;
  }

  Future<void> cancelNotifications() async {
    final subscriptions = _notificationSubscriptions.values.toList();
    _notificationSubscriptions.clear();
    // Release every claim even when one cancellation fails. Future.wait also
    // observes every error, rather than abandoning later subscriptions.
    await Future.wait(
      subscriptions.map((subscription) => Future.sync(subscription.cancel)),
    );
  }

  void replaceServices(Iterable<BluetoothService> discoveredServices) {
    services
      ..clear()
      ..addAll(discoveredServices);
  }

  void clear({required bool disposeControllers}) {
    services.clear();
    latestValues.clear();
    _writeWithoutResponseKeys.clear();
    if (disposeControllers) {
      disposeWriteControllers();
    }
  }

  void disposeWriteControllers() {
    for (final controller in _writeControllers.values) {
      controller.dispose();
    }
    _writeControllers.clear();
  }
}
