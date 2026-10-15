import 'package:test/test.dart';
import 'package:quick_blue_linux/src/l2cap_framing.dart';

/// Covers the L2CAP branching rules that used to live inline in the FFI channel
/// and therefore had no coverage at all: errno classification, chunk sizing and
/// PSM validation.
void main() {
  group('classifySendErrno', () {
    test('retries the same chunk when interrupted', () {
      expect(
        classifySendErrno(L2capErrno.eintr),
        L2capSendOutcome.retrySameChunk,
      );
    });

    test('backs off when the send buffer is full', () {
      expect(classifySendErrno(L2capErrno.eagain), L2capSendOutcome.retryLater);
    });

    test('closes the socket when the peer is gone', () {
      for (final errno in <int>[
        L2capErrno.epipe,
        L2capErrno.econnreset,
        L2capErrno.eshutdown,
      ]) {
        expect(
          classifySendErrno(errno),
          L2capSendOutcome.closed,
          reason: 'errno $errno should close the socket',
        );
      }
    });

    test('leaves the EINVAL decision to the caller', () {
      expect(
        classifySendErrno(L2capErrno.einval),
        L2capSendOutcome.firstChunkRetry,
      );
    });

    test('treats any other errno as fatal', () {
      expect(classifySendErrno(5), L2capSendOutcome.fatal);
      expect(classifySendErrno(0), L2capSendOutcome.fatal);
    });
  });

  group('classifyRecvErrno', () {
    test('waits for the next poll tick when no data is ready', () {
      expect(classifyRecvErrno(L2capErrno.eagain), L2capRecvOutcome.again);
    });

    test('keeps reading when interrupted', () {
      expect(
        classifyRecvErrno(L2capErrno.eintr),
        L2capRecvOutcome.retrySameChunk,
      );
    });

    test('treats any other errno as fatal', () {
      expect(classifyRecvErrno(L2capErrno.econnreset), L2capRecvOutcome.fatal);
      expect(classifyRecvErrno(9), L2capRecvOutcome.fatal);
    });
  });

  group('nextChunkLength', () {
    test('sends the whole remainder while the peer MTU is unknown', () {
      expect(nextChunkLength(remaining: 500, chunkLimit: null), 500);
    });

    test('ignores a non-positive limit', () {
      expect(nextChunkLength(remaining: 500, chunkLimit: 0), 500);
      expect(nextChunkLength(remaining: 500, chunkLimit: -1), 500);
    });

    test('caps the chunk at the negotiated peer MTU', () {
      expect(nextChunkLength(remaining: 500, chunkLimit: 200), 200);
    });

    test('sends the remainder when it already fits', () {
      expect(nextChunkLength(remaining: 200, chunkLimit: 200), 200);
      expect(nextChunkLength(remaining: 50, chunkLimit: 200), 50);
    });

    test('never returns a negative length', () {
      expect(nextChunkLength(remaining: 0, chunkLimit: 200), 0);
    });
  });

  group('encodeL2capPsm', () {
    test('keeps a valid PSM unchanged', () {
      expect(encodeL2capPsm(0x1001), 0x1001);
      expect(encodeL2capPsm(0), 0);
      expect(encodeL2capPsm(0xFFFF), 0xFFFF);
    });

    test('rejects out-of-range PSMs instead of truncating them', () {
      expect(() => encodeL2capPsm(-1), throwsRangeError);
      expect(() => encodeL2capPsm(0x10000), throwsRangeError);
    });
  });
}
