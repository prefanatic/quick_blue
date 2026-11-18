/// Pure rules of the Linux connection lease, separated from the bus I/O so they
/// can be exercised by unit tests: name hashing, client naming and the
/// last-client check.
library;

import 'dart:async';

import 'package:dbus/dbus.dart';

/// Abstracts the D-Bus operations the Linux connection lease performs, so the
/// lease's locking, naming and last-client rules are unit-testable without a
/// system bus.
abstract interface class ConnectionLeaseBus {
  /// The unique bus name assigned to this connection; empty until the bus
  /// connection has completed its handshake.
  String get uniqueName;

  Future<DBusRequestNameReply> requestName(
    String name, {
    Set<DBusRequestNameFlag> flags,
  });

  Future<void> releaseName(String name);

  Future<List<String>> listNames();
}

/// The real system-bus implementation used by the connection lease.
final class SystemConnectionLeaseBus implements ConnectionLeaseBus {
  SystemConnectionLeaseBus({bool introspectable = false})
    : _client = DBusClient.system(introspectable: introspectable);

  final DBusClient _client;

  Future<void> close() => _client.close();

  @override
  String get uniqueName => _client.uniqueName;

  @override
  Future<DBusRequestNameReply> requestName(
    String name, {
    Set<DBusRequestNameFlag> flags = const {},
  }) {
    return _client.requestName(name, flags: flags);
  }

  @override
  Future<void> releaseName(String name) {
    return _client.releaseName(name);
  }

  @override
  Future<List<String>> listNames() {
    return _client.listNames();
  }
}

/// FNV-1a 64-bit hash of [deviceId], the stable per-device portion of every
/// lease name. Two processes agree on it, which is what makes the lock a real
/// cross-engine mutex.
String connectionLeaseNamePrefix(String deviceId, {required int pid}) {
  var hash = 0xcbf29ce484222325;
  for (final byte in deviceId.codeUnits) {
    hash ^= byte & 0xff;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return 'dev.quick_blue.Connection.p$pid.d${hash.toRadixString(16).padLeft(16, '0')}';
}

/// Well-known name this process owns while it holds a connection to [deviceId].
String connectionLeaseClientName(
  String deviceId, {
  required int pid,
  required String uniqueName,
}) {
  if (uniqueName.isEmpty) {
    throw StateError('The D-Bus connection has no unique name');
  }
  final clientSuffix = uniqueName.replaceAll(':', '').replaceAll('.', '_');
  return '${connectionLeaseNamePrefix(deviceId, pid: pid)}.Client$clientSuffix';
}

/// Whether any bus name other than [ownedName] still holds a client membership
/// for the same device, i.e. whether [ownedName]'s owner is the last client.
///
/// [ownedName] itself is excluded: its owner is releasing right now, and its own
/// name is still visible in [busNames] at that point.
bool hasOtherConnectionClients({
  required String deviceId,
  required int pid,
  required String ownedName,
  required Iterable<String> busNames,
}) {
  final prefix = '${connectionLeaseNamePrefix(deviceId, pid: pid)}.Client';
  return busNames.any((name) => name != ownedName && name.startsWith(prefix));
}
