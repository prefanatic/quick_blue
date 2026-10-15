import 'dart:io' show pid;

import 'package:dbus/dbus.dart';
import 'package:meta/meta.dart';

import 'connection_lease.dart';
import 'connection_ownership.dart';

/// Connection lease over the system D-Bus: a per-device well-known name per
/// engine plus a device-scoped lock, so multiple Flutter engines (or processes)
/// share one BlueZ connection with a defined last-client handoff.
@visibleForTesting
class DbusConnectionLease implements QuickBlueLinuxConnectionLease {
  DbusConnectionLease() : _bus = SystemConnectionLeaseBus();

  /// Test seam; referenced from the package's unit tests only.
  @visibleForTesting
  DbusConnectionLease.withBus(this._bus);

  final ConnectionLeaseBus _bus;

  /// How long to wait for the per-device connection lock before giving up.
  static const Duration _lockTimeout = Duration(seconds: 10);
  static const Duration _lockPollInterval = Duration(milliseconds: 10);

  @override
  Future<void> attach(String deviceId) async {
    await _withDeviceLock(deviceId, () async {
      final reply = await _bus.requestName(_clientNameFor(deviceId));
      if (reply != DBusRequestNameReply.primaryOwner &&
          reply != DBusRequestNameReply.alreadyOwner) {
        throw StateError(
          'Unable to register a connection client for $deviceId',
        );
      }
    });
  }

  @override
  Future<void> detach(
    String deviceId,
    Future<void> Function() onLastClient,
  ) async {
    await _withDeviceLock(deviceId, () async {
      final ownedName = _clientNameFor(deviceId);
      await _bus.releaseName(ownedName);
      if (!hasOtherConnectionClients(
        deviceId: deviceId,
        pid: pid,
        ownedName: ownedName,
        busNames: await _bus.listNames(),
      )) {
        await onLastClient();
      }
    });
  }

  Future<void> _withDeviceLock(
    String deviceId,
    Future<void> Function() action,
  ) async {
    final lockName = '${_clientNamePrefix(deviceId)}.Lock';
    final deadline = DateTime.now().add(_lockTimeout);
    while (true) {
      final reply = await _bus.requestName(
        lockName,
        flags: const {DBusRequestNameFlag.doNotQueue},
      );
      if (reply == DBusRequestNameReply.primaryOwner ||
          reply == DBusRequestNameReply.alreadyOwner) {
        break;
      }
      if (DateTime.now().isAfter(deadline)) {
        // A stale lock name would otherwise block attach/detach forever.
        throw StateError(
          'Timed out after ${_lockTimeout.inSeconds}s acquiring the quick_blue '
          'connection lock $lockName',
        );
      }
      await Future<void>.delayed(_lockPollInterval);
    }
    try {
      await action();
    } finally {
      await _bus.releaseName(lockName);
    }
  }

  String _clientNameFor(String deviceId) {
    return connectionLeaseClientName(
      deviceId,
      pid: pid,
      uniqueName: _bus.uniqueName,
    );
  }

  static String _clientNamePrefix(String deviceId) {
    return connectionLeaseNamePrefix(deviceId, pid: pid);
  }
}
