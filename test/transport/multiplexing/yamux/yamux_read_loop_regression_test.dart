import 'dart:async';
import 'dart:typed_data';

import 'package:ipfs_libp2p/core/network/conn.dart' as core_conn show ConnState;
import 'package:ipfs_libp2p/core/network/transport_conn.dart';
import 'package:ipfs_libp2p/core/multiaddr.dart';
import 'package:ipfs_libp2p/core/peer/peer_id.dart';
import 'package:ipfs_libp2p/p2p/transport/multiplexing/multiplexer.dart';
import 'package:ipfs_libp2p/p2p/transport/multiplexing/yamux/frame.dart';
import 'package:ipfs_libp2p/p2p/transport/multiplexing/yamux/session.dart';
import 'package:ipfs_libp2p/p2p/transport/multiplexing/yamux/stream.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'yamux_session_test.mocks.dart';

PeerId _peerId(int seed) => PeerId.fromBytes(Uint8List.fromList(
    List.generate(34, (i) => (i % 250) + seed)..[0] = 0x12..[1] = 0x20));

/// Builds a [MockTransportConn] whose [MockTransportConn.read] is fed from
/// [feeder]. [feeder.feed] delivers raw frame bytes to the session read loop.
class _ConnHarness {
  _ConnHarness({Future<void> Function(Uint8List data)? onWrite}) {
    conn = MockTransportConn();
    when(conn.localPeer).thenReturn(_peerId(1));
    when(conn.remotePeer).thenReturn(_peerId(2));
    when(conn.localMultiaddr).thenReturn(MultiAddr('/ip4/127.0.0.1/tcp/1'));
    when(conn.remoteMultiaddr).thenReturn(MultiAddr('/ip4/127.0.0.1/tcp/2'));
    when(conn.isClosed).thenReturn(false);
    when(conn.id).thenReturn('regression-conn');
    when(conn.state).thenReturn(core_conn.ConnState(
      transport: 'mock-tcp',
      security: 'mock-noise',
      streamMultiplexer: '',
      usedEarlyMuxerNegotiation: false,
    ));
    when(conn.close()).thenAnswer((_) async {});
    when(conn.write(any)).thenAnswer((inv) =>
        onWrite?.call(inv.positionalArguments[0] as Uint8List) ??
        Future.value());
    when(conn.read(any)).thenAnswer((_) {
      if (_pending.isNotEmpty) return Future.value(_pending.removeAt(0));
      final c = Completer<Uint8List>();
      _waiters.add(c);
      return c.future;
    });
  }

  late final MockTransportConn conn;
  final _pending = <Uint8List>[];
  final _waiters = <Completer<Uint8List>>[];

  void feed(Uint8List data) {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(data);
    } else {
      _pending.add(data);
    }
  }
}

MultiplexerConfig _config() => MultiplexerConfig(
      keepAliveInterval: const Duration(seconds: 30),
      maxStreamWindowSize: 1024 * 1024,
      initialStreamWindowSize: 256 * 1024,
      streamWriteTimeout: const Duration(seconds: 10),
      maxStreams: 256,
    );

void main() {
  group('YamuxSession read-loop non-blocking regression', () {
    test('inbound stream is accepted even when the write path is blocked',
        () async {
      final writeBlocker = Completer<void>();
      final harness = _ConnHarness(onWrite: (_) => writeBlocker.future);

      // Server session: accepts odd (client-initiated) stream IDs.
      final session = YamuxSession(harness.conn, _config(), false);
      addTearDown(() async {
        writeBlocker.complete();
        await session.close();
      });

      // Remote opens stream 1. With the old implementation the SYN-ACK send
      // was awaited inside the read loop, so a stalled write starved all
      // inbound stream creation.
      harness.feed(YamuxFrame.synStream(1).toBytes());

      final stream = await session
          .acceptStream()
          .timeout(const Duration(seconds: 2));
      expect(stream.id(), equals('1'));
    });

    test('eager DATA immediately following SYN is delivered to the stream',
        () async {
      final harness = _ConnHarness();
      final session = YamuxSession(harness.conn, _config(), false);
      addTearDown(() => session.close());

      // go-yamux pipelines the first DATA frame right after SYN.
      final payload = Uint8List.fromList(List.generate(64, (i) => i));
      harness.feed(YamuxFrame.synStream(1).toBytes());
      harness.feed(YamuxFrame.createData(1, payload).toBytes());

      final stream = await session
          .acceptStream()
          .timeout(const Duration(seconds: 2));
      final received =
          await stream.read(64).timeout(const Duration(seconds: 2));
      expect(received, equals(payload));
    });

    test('acceptStream returns a stream that arrived before any waiter',
        () async {
      final harness = _ConnHarness();
      final session = YamuxSession(harness.conn, _config(), false);
      addTearDown(() => session.close());

      harness.feed(YamuxFrame.synStream(3).toBytes());
      // Give the read loop a moment to process the SYN with nobody waiting.
      await Future.delayed(const Duration(milliseconds: 50));

      final stream = await session
          .acceptStream()
          .timeout(const Duration(seconds: 2));
      expect(stream.id(), equals('3'));
    });

    test('rejected inbound stream sends a fire-and-forget RST', () async {
      final sent = <YamuxFrame>[];
      final harness = _ConnHarness(onWrite: (data) async {
        sent.add(YamuxFrame.fromBytes(data));
      });
      // maxStreams: 0 -> canCreateStream is false for every inbound SYN.
      final cfg = MultiplexerConfig(
        keepAliveInterval: const Duration(seconds: 30),
        maxStreamWindowSize: 1024 * 1024,
        initialStreamWindowSize: 256 * 1024,
        streamWriteTimeout: const Duration(seconds: 10),
        maxStreams: 0,
      );
      final session = YamuxSession(harness.conn, cfg, false);
      addTearDown(() => session.close());

      harness.feed(YamuxFrame.synStream(1).toBytes());
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(
        sent.any((f) =>
            f.type == YamuxFrameType.windowUpdate &&
            f.flags & YamuxFlags.rst != 0),
        isTrue,
        reason: 'a RST frame should be sent for the rejected stream',
      );
    });

    test('SYN-ACK send failure does not break inbound stream creation',
        () async {
      var calls = 0;
      final harness = _ConnHarness(onWrite: (_) async {
        calls++;
        throw StateError('simulated write failure');
      });
      final session = YamuxSession(harness.conn, _config(), false);
      addTearDown(() => session.close());

      harness.feed(YamuxFrame.synStream(1).toBytes());

      final stream = await session
          .acceptStream()
          .timeout(const Duration(seconds: 2));
      expect(stream.id(), equals('1'));
      expect(calls, greaterThan(0));
    });

    test('session ping gets a PONG even when writes fail', () async {
      final harness = _ConnHarness(onWrite: (_) async {
        throw StateError('simulated write failure');
      });
      final session = YamuxSession(harness.conn, _config(), false);
      addTearDown(() => session.close());

      // Ping request (opaque value 42); the failed PONG send must be caught.
      harness.feed(YamuxFrame.ping(false, 42).toBytes());
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(session.isClosed, isFalse,
          reason: 'a failed PONG send must not kill the session');
    });

    test('acceptStream throws when the session closes while waiting',
        () async {
      final harness = _ConnHarness();
      final session = YamuxSession(harness.conn, _config(), false);

      final pending = session.acceptStream();
      final assertion = expectLater(pending, throwsStateError);
      await pumpEventQueue();
      await session.close();
      await assertion;
    });
  });

  group('YamuxStream window-update failure recovery', () {
    test('failed window update restores consumed bytes for the next attempt',
        () async {
      final sentFrames = <YamuxFrame>[];
      var failNextSend = true;

      Future<void> sendFrame(YamuxFrame frame) async {
        if (failNextSend) {
          failNextSend = false;
          throw StateError('simulated send failure');
        }
        sentFrames.add(frame);
      }

      final session = YamuxSession(_ConnHarness().conn, _config(), false);
      final stream = YamuxStream(
        id: 1,
        protocol: '',
        metadata: {},
        initialWindowSize: 256 * 1024,
        sendFrame: sendFrame,
        parentConn: session,
        remotePeer: _peerId(2),
        maxFrameSize: 1024 * 1024,
      );

      // Feed 40KB of data: crosses the 32KB window-update threshold. The
      // first update send fails and must restore the accounting so the
      // credit is retried on the next batch.
      await stream.handleFrame(
          YamuxFrame.createData(1, Uint8List(40 * 1024)));

      // Not enough new bytes yet to re-trigger; feed another 32KB.
      await stream.handleFrame(
          YamuxFrame.createData(1, Uint8List(32 * 1024)));

      // Allow the fire-and-forget send to run.
      await pumpEventQueue();

      final updates = sentFrames
          .where((f) => f.type == YamuxFrameType.windowUpdate)
          .toList();
      expect(updates, isNotEmpty,
          reason: 'a retry window update should be sent after the failure');
      // The retried update must carry the bytes lost by the failed send
      // plus the newly consumed bytes (40KB + 32KB = 72KB total).
      expect(updates.last.length, equals(72 * 1024));
    });
  });

  group('YamuxStream openIncoming and control frames', () {
    YamuxStream _stream(Future<void> Function(YamuxFrame) sendFrame) {
      final session = YamuxSession(_ConnHarness().conn, _config(), false);
      return YamuxStream(
        id: 1,
        protocol: '',
        metadata: {},
        initialWindowSize: 256 * 1024,
        sendFrame: sendFrame,
        parentConn: session,
        remotePeer: _peerId(2),
        maxFrameSize: 1024 * 1024,
      );
    }

    test('openIncoming throws when the stream is not in init state', () async {
      final stream = _stream((_) async {});
      await stream.openIncoming();
      await expectLater(stream.openIncoming(), throwsStateError);
    });

    test('failed initial window update does not propagate or block',
        () async {
      final stream = _stream((_) async {
        throw StateError('simulated send failure');
      });
      await stream.openIncoming();
      await pumpEventQueue();
      // The failure is logged via catchError; nothing throws and the
      // stream is still usable.
      expect(stream.isClosed, isFalse);
    });

    test('stream-level ping gets a fire-and-forget PONG', () async {
      final sent = <YamuxFrame>[];
      final stream = _stream((f) async {
        sent.add(f);
      });
      await stream.handleFrame(YamuxFrame(
        type: YamuxFrameType.ping,
        flags: 0,
        streamId: 1,
        length: 7,
        data: Uint8List(0),
      ));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(
        sent.any(
            (f) => f.type == YamuxFrameType.ping && f.flags & YamuxFlags.ack != 0),
        isTrue,
        reason: 'a PONG (ping with ACK flag) should be sent',
      );
    });

    test('failed stream-level PONG send is caught and logged', () async {
      final stream = _stream((_) async {
        throw StateError('simulated send failure');
      });
      await stream.handleFrame(YamuxFrame(
        type: YamuxFrameType.ping,
        flags: 0,
        streamId: 1,
        length: 7,
        data: Uint8List(0),
      ));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(stream.isClosed, isFalse,
          reason: 'a failed PONG send must not kill the stream');
    });
  });
}
