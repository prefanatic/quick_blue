import 'dart:ffi' as ffi;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:quick_blue_linux/generated_bindings.dart';
import 'package:quick_blue_linux/src/l2cap_framing.dart';
import 'package:quick_blue_linux/src/native_libraries.dart';

/// Real zeroed allocations, with exact ownership accounting; no fake pointers.
class CountingAllocator implements ffi.Allocator {
  int allocations = 0;
  int frees = 0;
  final Set<int> live = {};
  @override
  ffi.Pointer<T> allocate<T extends ffi.NativeType>(
    int byteCount, {
    int? alignment,
  }) {
    final pointer = calloc.allocate<T>(byteCount, alignment: alignment);
    allocations++;
    if (!live.add(pointer.address)) throw StateError('Allocation already live');
    return pointer;
  }

  @override
  void free(ffi.Pointer pointer) {
    if (!live.remove(pointer.address)) throw StateError('Unknown/double free');
    frees++;
    calloc.free(pointer);
  }

  Map<String, Object> get ledger => {
    'allocations': allocations,
    'frees': frees,
    'liveAllocations': live.length,
  };
}

class ScriptedBluetooth implements LibBluetooth {
  @override
  int str2ba(ffi.Pointer<ffi.Char> string, ffi.Pointer<bdaddr_t> address) => 0;
}

/// Scripts only the syscall boundary; the channel's loops and timers are real.
class ScriptedLibc implements Libc {
  List<(int, int)> connectResults = [];
  List<(int, int)> sendResults = [];
  List<(int, int)> recvResults = [];
  (int, int)? persistentSend;
  (int, int)? persistentRecv;
  (int, int)? persistentConnect;
  int socketResult = 42;
  int mtu = 64;
  int mtuResult = 0;
  int errnoValue = 0;
  int socketCalls = 0,
      closeCalls = 0,
      connectCalls = 0,
      sendCalls = 0,
      recvCalls = 0;
  final Set<int> liveFds = {};
  final List<int> sent = [];
  void Function()? observe;
  int result((int, int) value) {
    errnoValue = value.$2;
    return value.$1;
  }

  @override
  int get errno => errnoValue;
  @override
  int socket(int domain, int type, int protocol) {
    socketCalls++;
    if (socketResult >= 0) liveFds.add(socketResult);
    return socketResult;
  }

  @override
  int connect(int fd, ffi.Pointer<sockaddr> address, int length) {
    connectCalls++;
    return result(
      connectResults.isNotEmpty
          ? connectResults.removeAt(0)
          : persistentConnect ?? (0, 0),
    );
  }

  @override
  int send(int fd, ffi.Pointer<ffi.Void> buffer, int count, int flags) {
    sendCalls++;
    final value = sendResults.isNotEmpty
        ? sendResults.removeAt(0)
        : persistentSend ?? (count, 0);
    final written = result(value);
    if (written > 0) {
      sent.addAll(
        buffer.cast<ffi.Uint8>().asTypedList(math.min(written, count)),
      );
    }
    if (sendCalls == 1 || sendCalls % 100000 == 0) observe?.call();
    return written;
  }

  @override
  int recv(int fd, ffi.Pointer<ffi.Void> buffer, int count, int flags) {
    recvCalls++;
    final received = result(
      recvResults.isNotEmpty
          ? recvResults.removeAt(0)
          : persistentRecv ?? (-1, L2capErrno.eagain),
    );
    if (received > 0) {
      buffer.cast<ffi.Uint8>().asTypedList(received).fillRange(0, received, 7);
    }
    if (recvCalls == 1 || recvCalls % 100000 == 0) observe?.call();
    return received;
  }

  @override
  int getsockopt(
    int fd,
    int level,
    int optionName,
    ffi.Pointer<ffi.Void> optionValue,
    ffi.Pointer<ffi.UnsignedInt> optionLength,
  ) {
    optionValue.cast<l2cap_options>().ref
      ..imtu = mtu
      ..omtu = mtu;
    return mtuResult;
  }

  @override
  int setsockopt(
    int fd,
    int level,
    int optionName,
    ffi.Pointer<ffi.Void> optionValue,
    int optionLength,
  ) => 0;
  @override
  int fcntl(int fd, int cmd, int arg) => 0;
  @override
  int close(int fd) {
    if (!liveFds.remove(fd)) throw StateError('Unknown/double close');
    closeCalls++;
    return 0;
  }

  Map<String, Object> get ledger => {
    'socketCalls': socketCalls,
    'connectCalls': connectCalls,
    'sendCalls': sendCalls,
    'recvCalls': recvCalls,
    'sentBytes': sent.length,
    'closeCalls': closeCalls,
    'liveFds': liveFds.length,
  };
}
