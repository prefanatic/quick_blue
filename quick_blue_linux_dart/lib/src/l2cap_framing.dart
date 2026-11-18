/// Pure helpers shared by the Linux L2CAP channel: errno classification, chunk
/// sizing and address-field encoding. They carry no FFI state, so the channel's
/// branching rules are unit-testable without a Bluetooth adapter.
library;

/// Linux errno values used by the L2CAP channel (x86_64 numbering, which is what
/// the FFI layer reports).
abstract final class L2capErrno {
  /// EAGAIN; equal to EWOULDBLOCK on Linux.
  static const int eagain = 11;

  /// EINTR, a signal interrupted the call.
  static const int eintr = 4;

  /// EACCES, typically a security-level rejection on connect.
  static const int eacces = 13;

  /// EINVAL, an invalid argument (also used for an unbound/dynamic PSM).
  static const int einval = 22;

  /// EPIPE, the peer closed the socket.
  static const int epipe = 32;

  /// ECONNRESET, the peer reset the connection.
  static const int econnreset = 104;

  /// ESHUTDOWN, the socket was shut down and cannot be written to.
  static const int eshutdown = 108;
}

/// What a `send` loop should do after a failed write.
enum L2capSendOutcome {
  /// Retry the same chunk immediately (EINTR).
  retrySameChunk,

  /// The socket buffer is full; resume the chunk later (EAGAIN).
  retryLater,

  /// The peer is gone; close the socket (EPIPE, ECONNRESET, ESHUTDOWN).
  closed,

  /// EINVAL: retrying only helps before any byte of the chunk was written, so
  /// the caller must decide based on its offset.
  firstChunkRetry,

  /// Anything else is a hard failure.
  fatal,
}

/// What a `recv` loop should do after a failed read.
enum L2capRecvOutcome {
  /// No more data right now; stop polling until the next tick (EAGAIN).
  again,

  /// The read was interrupted; keep reading (EINTR).
  retrySameChunk,

  /// Anything else is a hard failure.
  fatal,
}

L2capSendOutcome classifySendErrno(int errno) {
  switch (errno) {
    case L2capErrno.eintr:
      return L2capSendOutcome.retrySameChunk;
    case L2capErrno.eagain:
      return L2capSendOutcome.retryLater;
    case L2capErrno.epipe:
    case L2capErrno.econnreset:
    case L2capErrno.eshutdown:
      return L2capSendOutcome.closed;
    case L2capErrno.einval:
      return L2capSendOutcome.firstChunkRetry;
    default:
      return L2capSendOutcome.fatal;
  }
}

L2capRecvOutcome classifyRecvErrno(int errno) {
  switch (errno) {
    case L2capErrno.eagain:
      return L2capRecvOutcome.again;
    case L2capErrno.eintr:
      return L2capRecvOutcome.retrySameChunk;
    default:
      return L2capRecvOutcome.fatal;
  }
}

/// Length of the next write chunk for [remaining] bytes of a frame.
///
/// A null or non-positive [chunkLimit] means the peer MTU is not known yet, so
/// the whole remainder is handed to `send` in one call.
int nextChunkLength({required int remaining, int? chunkLimit}) {
  if (chunkLimit == null || chunkLimit <= 0 || remaining <= chunkLimit) {
    return remaining;
  }
  return chunkLimit;
}

/// Encodes [psm] for `sockaddr_l2.l2_psm`, which the kernel reads in host byte
/// order on little-endian hosts.
///
/// The value is validated so an out-of-range PSM fails here rather than
/// silently truncating into the address structure.
int encodeL2capPsm(int psm) {
  if (psm < 0 || psm > 0xFFFF) {
    throw RangeError.range(psm, 0, 0xFFFF, 'psm');
  }
  return psm & 0xFFFF;
}
