import 'package:ipfs_libp2p/core/network/common.dart' show Direction;
import 'package:ipfs_libp2p/core/network/mux.dart';
import 'package:ipfs_libp2p/core/network/rcmgr.dart' show StreamManagementScope;
import 'package:ipfs_libp2p/p2p/transport/p2p_stream_adapter.dart';
import 'package:ipfs_libp2p/p2p/transport/tcp_connection.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

@GenerateMocks([TCPConnection, StreamManagementScope, MuxedStream])
import 'p2p_stream_adapter_test.mocks.dart';

void main() {
  group('P2PStreamAdapter deadlines', () {
    late P2PStreamAdapter adapter;
    late MockMuxedStream muxedStream;

    setUp(() {
      muxedStream = MockMuxedStream();
      adapter = P2PStreamAdapter(
        muxedStream,
        MockTCPConnection(),
        MockStreamManagementScope(),
        Direction.inbound,
        '/test/1.0.0',
      );
    });

    test('setDeadline forwards the deadline to the muxed stream', () async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      await adapter.setDeadline(deadline);
      verify(muxedStream.setDeadline(deadline)).called(1);
    });

    test('setDeadline(null) clears the deadline on the muxed stream', () async {
      // A dropped null leaves the negotiation deadline armed: every later
      // read inherits it and dies ~10s after stream creation. Clearing must
      // reach the underlying stream so idle reads wait indefinitely.
      await adapter.setDeadline(null);
      verify(muxedStream.setDeadline(null)).called(1);
    });
  });
}
