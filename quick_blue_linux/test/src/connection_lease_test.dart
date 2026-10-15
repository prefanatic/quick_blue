import 'dart:async';
import 'dart:io' show pid;

import 'package:dbus/dbus.dart';
import 'package:test/test.dart';
import 'package:quick_blue_linux/quick_blue_linux.dart';
import 'package:quick_blue_linux/src/connection_lease.dart';

/// Ownership state of a fake system bus, shared by the [ConnectionLeaseBus]
/// views that model separate D-Bus connections (i.e. separate Flutter engines).
final class _FakeBusState {
  /// Well-known name -> unique name of the connection that owns it, mirroring
  /// the bus's own ownership table.
  final Map<String, String> owners = <String, String>{};

  /// Every name this fake bus has granted, in grant order.
  final List<String> ownershipHistory = <String>[];
}

/// One connection's in-memory view of [_FakeBusState], recording every call so
/// the lease's locking, naming and last-client rules run without a system bus.
final class _FakeBus implements ConnectionLeaseBus {
  _FakeBus({_FakeBusState? state, this.uniqueName = ':1.42'})
    : state = state ?? _FakeBusState();

  final _FakeBusState state;

  @override
  final String uniqueName;

  final List<String> requestCalls = [];
  final List<String> releaseCalls = [];

  /// Client names (i.e. requests made inside a lock's critical section) this
  /// connection has requested, in order. The lock requests themselves are
  /// excluded so a test can tell entry from lock polling.
  final List<String> clientRequests = [];

  int listNamesCalls = 0;

  /// Awaited before a `requestName`/`listNames` call is served, so a test can
  /// hold an operation inside its critical section and observe who else enters.
  Future<void> Function(String name)? beforeRequestName;
  Future<void> Function()? beforeListNames;

  /// When non-null, every requestName for a matching name returns this reply
  /// instead of the normal ownership simulation.
  DBusRequestNameReply Function(String name)? forcedReply;

  static bool isLockName(String name) => name.endsWith('.Lock');

  /// Whether this connection currently owns [name].
  bool owns(String name) => state.owners[name] == uniqueName;

  /// Simulates a holder owned by another connection (a stale process, or a
  /// second engine that already holds the name).
  void holdByOtherConnection(String name) {
    state.owners[name] = ':1.99';
  }

  /// Simulates the other holder going away.
  void releaseOtherConnection(String name) {
    state.owners.remove(name);
  }

  void _recordOwnership(String name) {
    state.owners[name] = uniqueName;
    state.ownershipHistory.add(name);
  }

  @override
  Future<DBusRequestNameReply> requestName(
    String name, {
    Set<DBusRequestNameFlag> flags = const {},
  }) async {
    requestCalls.add(name);
    if (!isLockName(name)) {
      clientRequests.add(name);
    }
    await beforeRequestName?.call(name);

    final forced = forcedReply;
    if (forced != null) {
      final reply = forced(name);
      if (reply == DBusRequestNameReply.primaryOwner ||
          reply == DBusRequestNameReply.alreadyOwner) {
        _recordOwnership(name);
      }
      return reply;
    }

    final owner = state.owners[name];
    if (owner == uniqueName) {
      // Real D-Bus reports alreadyOwner when the same connection re-requests a
      // name it holds; the lease treats that as acquisition success.
      return DBusRequestNameReply.alreadyOwner;
    }
    if (owner != null) {
      return DBusRequestNameReply.exists;
    }
    _recordOwnership(name);
    return DBusRequestNameReply.primaryOwner;
  }

  @override
  Future<void> releaseName(String name) async {
    releaseCalls.add(name);
    if (owns(name)) {
      state.owners.remove(name);
    }
  }

  @override
  Future<List<String>> listNames() async {
    listNamesCalls += 1;
    await beforeListNames?.call();
    return {'org.freedesktop.DBus', 'org.bluez', ...state.owners.keys}.toList();
  }
}

void main() {
  const testPid = 42;

  group('connectionLeaseNamePrefix', () {
    test('names are process-scoped and device-scoped', () {
      final prefix = connectionLeaseNamePrefix(
        'AA:BB:CC:DD:EE:FF',
        pid: testPid,
      );
      expect(prefix, startsWith('dev.quick_blue.Connection.p42.d'));
      expect(prefix.split('.p42.d').last.length, 16);
    });

    test('different devices hash differently within one process', () {
      final a = connectionLeaseNamePrefix('AA:BB:CC:DD:EE:01', pid: testPid);
      final b = connectionLeaseNamePrefix('AA:BB:CC:DD:EE:02', pid: testPid);
      expect(a, isNot(equals(b)));
    });

    test('the same device hashes identically across processes', () {
      final a = connectionLeaseNamePrefix(
        'AA:BB:CC:DD:EE:FF',
        pid: testPid - 1,
      );
      final b = connectionLeaseNamePrefix('AA:BB:CC:DD:EE:FF', pid: testPid);
      expect(
        a.split('.d').last,
        equals(b.split('.d').last),
        reason:
            'the per-device lock only works if both engines derive the '
            'same name for the same device',
      );
    });
  });

  group('connectionLeaseClientName', () {
    test('appends the sanitized unique name', () {
      final name = connectionLeaseClientName(
        'AA:BB:CC:DD:EE:FF',
        pid: 42,
        uniqueName: ':1.23',
      );
      expect(name, endsWith('.Client1_23'));
      expect(name, contains('.d'));
    });

    test('rejects a bus connection without a unique name', () {
      expect(
        () => connectionLeaseClientName(
          'AA:BB:CC:DD:EE:FF',
          pid: 42,
          uniqueName: '',
        ),
        throwsStateError,
      );
    });
  });

  group('hasOtherConnectionClients', () {
    const testPid = 42;
    final prefix = connectionLeaseNamePrefix('AA:BB:CC:DD:EE:FF', pid: testPid);

    test('ignores the name being released', () {
      expect(
        hasOtherConnectionClients(
          deviceId: 'AA:BB:CC:DD:EE:FF',
          pid: testPid,
          ownedName: '$prefix.Client1',
          busNames: ['$prefix.Client1'],
        ),
        isFalse,
      );
    });

    test('detects another engine still holding the device', () {
      expect(
        hasOtherConnectionClients(
          deviceId: 'AA:BB:CC:DD:EE:FF',
          pid: testPid,
          ownedName: '$prefix.Client1',
          busNames: ['$prefix.Client1', '$prefix.Client2'],
        ),
        isTrue,
      );
    });

    test(
      'does not confuse this device with another device of the same process',
      () {
        final otherDevicePrefix = connectionLeaseNamePrefix(
          'AA:BB:CC:DD:EE:02',
          pid: testPid,
        );
        expect(
          hasOtherConnectionClients(
            deviceId: 'AA:BB:CC:DD:EE:FF',
            pid: testPid,
            ownedName: '$prefix.Client1',
            busNames: ['$prefix.Client1', '$otherDevicePrefix.Client2'],
          ),
          isFalse,
          reason: 'the last-client check must be per device, not per process',
        );
      },
    );
  });

  group('DbusConnectionLease (with a fake bus)', () {
    const deviceId = 'AA:BB:CC:DD:EE:FF';

    /// The lock name the lease derives for [deviceId] in *this* process. The
    /// lease reads its pid from dart:io, so a fixture that hard-codes another
    /// pid would never contend.
    final lockName = '${connectionLeaseNamePrefix(deviceId, pid: pid)}.Lock';

    test(
      'attach takes the lock, registers the client and releases the lock',
      () async {
        final bus = _FakeBus();
        final lease = DbusConnectionLease.withBus(bus);

        await lease.attach(deviceId);

        final lockCalls = bus.requestCalls.where(_FakeBus.isLockName).length;
        expect(lockCalls, 1);
        expect(
          bus.state.owners.keys.single.endsWith('.Client1_42'),
          isTrue,
          reason:
              'the client name is registered while the lock is held, and the '
              'lock is released afterwards',
        );
        expect(bus.releaseCalls.single, lockName);
      },
    );

    test('a failed client registration still releases the lock', () async {
      final bus = _FakeBus()
        ..forcedReply = (name) => _FakeBus.isLockName(name)
            ? DBusRequestNameReply.primaryOwner
            : DBusRequestNameReply.exists;
      final lease = DbusConnectionLease.withBus(bus);

      await expectLater(lease.attach(deviceId), throwsStateError);

      expect(
        bus.state.ownershipHistory,
        contains(lockName),
        reason:
            'the client name was refused, so the lease can only be clean if it '
            'really took the lock first',
      );
      expect(
        bus.state.owners.containsKey(lockName),
        isFalse,
        reason: 'the lock must not leak when the client name is refused',
      );
      expect(bus.releaseCalls, contains(lockName));
    });

    test('a stale lock is retried until it is released', () async {
      final bus = _FakeBus()..holdByOtherConnection(lockName);
      final lease = DbusConnectionLease.withBus(bus);

      final attach = lease.attach(deviceId);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        bus.requestCalls.where(_FakeBus.isLockName).length,
        greaterThan(1),
        reason:
            'attach must contend with the stale holder in its own pid '
            'namespace instead of walking straight past it',
      );
      expect(
        bus.clientRequests,
        isEmpty,
        reason:
            'the client must not register while another holder has the lock',
      );

      // Simulate the stale holder going away.
      bus.releaseOtherConnection(lockName);

      await attach;
      expect(
        bus.state.owners.keys.single.endsWith('.Client1_42'),
        isTrue,
        reason: 'once the stale lock clears, attach completes',
      );
      expect(bus.state.owners.containsKey(lockName), isFalse);
    });

    test('a permanently stale lock times out instead of hanging', () async {
      final bus = _FakeBus()
        ..forcedReply = (name) => _FakeBus.isLockName(name)
            ? DBusRequestNameReply.exists
            : DBusRequestNameReply.primaryOwner;
      final lease = DbusConnectionLease.withBus(bus);

      await expectLater(lease.attach(deviceId), throwsStateError);
      expect(
        bus.clientRequests,
        isEmpty,
        reason: 'a lock that never clears must never register a client',
      );
    });

    test(
      'detach releases the client name and detects the last client',
      () async {
        final bus = _FakeBus();
        final lease = DbusConnectionLease.withBus(bus);
        await lease.attach(deviceId);
        bus.requestCalls.clear();

        var onLastClientCalls = 0;
        await lease.detach(deviceId, () async => onLastClientCalls += 1);

        expect(onLastClientCalls, 1);
        expect(bus.state.owners, isEmpty);
      },
    );

    test(
      'detach keeps the shared connection while another engine holds it',
      () async {
        final bus = _FakeBus();
        final lease = DbusConnectionLease.withBus(bus);
        await lease.attach(deviceId);

        // A second engine holds another client name for the same device. Its
        // device hash is identical across processes, so model it by suffixing the
        // same prefix with a different client id.
        final ourPrefix = bus.state.owners.keys.single.split('.Client').first;
        final otherClientName = '$ourPrefix.Client2';
        bus.holdByOtherConnection(otherClientName);

        var onLastClientCalls = 0;
        await lease.detach(deviceId, () async => onLastClientCalls += 1);

        expect(
          onLastClientCalls,
          0,
          reason:
              'the shared BlueZ connection must survive while another client '
              'is still registered',
        );
        expect(bus.state.owners.containsKey(otherClientName), isTrue);
        expect(bus.state.owners.containsKey(lockName), isFalse);
      },
    );

    test('attach and detach serialize per device through the lock', () async {
      // Two D-Bus connections, as two Flutter engines in one process have: the
      // lock only excludes work while the *other* connection holds the name.
      final state = _FakeBusState();
      final busA = _FakeBus(state: state, uniqueName: ':1.42');
      final busB = _FakeBus(state: state, uniqueName: ':1.43');
      final leaseA = DbusConnectionLease.withBus(busA);
      final leaseB = DbusConnectionLease.withBus(busB);

      // Hold engine A inside the critical section of its attach: A holds the
      // lock, so engine B must not be able to register its client name.
      final attachEntered = Completer<void>();
      final releaseAttach = Completer<void>();
      busA.beforeRequestName = (name) async {
        if (_FakeBus.isLockName(name)) {
          return;
        }
        if (!attachEntered.isCompleted) {
          attachEntered.complete();
        }
        await releaseAttach.future;
      };

      final attachA = leaseA.attach(deviceId);
      await attachEntered.future;
      expect(
        state.owners[lockName],
        ':1.42',
        reason:
            'engine A must hold the device lock inside its critical section',
      );

      var attachBCompleted = false;
      final attachB = leaseB.attach(deviceId).then((_) {
        attachBCompleted = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        attachBCompleted,
        isFalse,
        reason: 'engine B must wait for engine A to release the device lock',
      );
      expect(
        busB.clientRequests,
        isEmpty,
        reason:
            'engine B must not enter its critical section before engine A '
            'leaves its own',
      );
      expect(
        busB.requestCalls.where(_FakeBus.isLockName).length,
        greaterThan(1),
        reason: 'engine B must retry the contended lock until it is free',
      );

      releaseAttach.complete();
      await attachA;
      await attachB;
      expect(attachBCompleted, isTrue);

      // Attach/detach contention on the same device: hold A inside detach (its
      // critical section runs after the lock is taken) and check B still waits.
      busA.beforeRequestName = null;
      final detachEntered = Completer<void>();
      final releaseDetach = Completer<void>();
      busA.beforeListNames = () async {
        if (!detachEntered.isCompleted) {
          detachEntered.complete();
        }
        await releaseDetach.future;
      };

      final detachA = leaseA.detach(deviceId, () async {});
      await detachEntered.future;
      expect(
        state.owners[lockName],
        ':1.42',
        reason: 'detach must hold the device lock inside its critical section',
      );

      busB.clientRequests.clear();
      var attachB2Completed = false;
      final attachB2 = leaseB.attach(deviceId).then((_) {
        attachB2Completed = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        attachB2Completed,
        isFalse,
        reason: 'an attach must not overtake a detach holding the device lock',
      );
      expect(
        busB.clientRequests,
        isEmpty,
        reason:
            'engine B must not register a client while detach holds the lock',
      );

      releaseDetach.complete();
      await detachA;
      await attachB2;
      expect(
        state.owners.keys.where(_FakeBus.isLockName),
        isEmpty,
        reason: 'no device lock may be left behind',
      );
    });
  });
}
