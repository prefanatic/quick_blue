import 'dart:io' show pid;

import 'package:dbus/dbus.dart';
import 'package:meta/meta.dart';
import 'package:logging/logging.dart';

import 'connection_lease.dart';
import 'connection_ownership.dart';

/// Connection lease over the system D-Bus: a per-device well-known name per
/// engine plus a device-scoped lock, so multiple Flutter engines (or processes)
/// share one BlueZ connection with a defined last-client handoff.
@visibleForTesting
class DbusConnectionLease
    implements
        QuickBlueLinuxConnectionLease,
        QuickBlueLinuxDisposableConnectionLease {
  DbusConnectionLease() : _bus = SystemConnectionLeaseBus();

  /// Test seam; referenced from the package's unit tests only.
  @visibleForTesting
  DbusConnectionLease.withBus(this._bus);

  final ConnectionLeaseBus _bus;
  final _logger = Logger('DbusConnectionLease');

  @override
  Future<void> close() async {
    if (_bus case final SystemConnectionLeaseBus bus) await bus.close();
  }

  /// How long to wait for the per-device connection lock before giving up.
  static const Duration _lockTimeout = Duration(seconds: 10);
  static const Duration _lockPollInterval = Duration(milliseconds: 10);

  @override
  Future<void> attach(String deviceId) async {
    String? acquiredName;
    try {
      await _withDeviceLock(deviceId, () async {
        final name = _clientNameFor(deviceId);
        final reply = await _bus.requestName(name);
        if (reply != DBusRequestNameReply.primaryOwner &&
            reply != DBusRequestNameReply.alreadyOwner) {
          throw StateError(
            'Unable to register a connection client for $deviceId',
          );
        }
        acquiredName = name;
      });
    } catch (error, stack) {
      if (acquiredName case final name?) {
        try {
          await _bus.releaseName(name);
        } catch (cleanupError, cleanupStack) {
          _logger.warning(
            'Failed to roll back connection client',
            cleanupError,
            cleanupStack,
          );
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
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
    Object? primaryError;
    try {
      await action();
    } catch (error) {
      primaryError = error;
      rethrow;
    } finally {
      try {
        await _bus.releaseName(lockName);
      } catch (error, stack) {
        if (primaryError == null) rethrow;
        _logger.warning(
          'Failed to release connection lock after primary failure',
          error,
          stack,
        );
      }
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
