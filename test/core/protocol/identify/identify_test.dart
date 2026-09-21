import 'package:ipfs_libp2p/p2p/protocol/identify/identify.dart';
import 'package:ipfs_libp2p/p2p/protocol/identify/pb/identify.pb.dart';
import 'package:ipfs_libp2p/core/host/host.dart';
import 'package:ipfs_libp2p/core/event/bus.dart';
import 'package:ipfs_libp2p/core/network/conn.dart';
import 'package:ipfs_libp2p/core/peer/peer_id.dart';
import 'package:ipfs_libp2p/core/record/envelope.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'identify_test.mocks.dart';

class FakeSubscription implements Subscription {
  @override
  Stream get stream => const Stream.empty();
  @override
  String get name => 'fake';
  @override
  Future<void> close() async {}
}

class FakeEmitter implements Emitter {
  @override
  Future<void> emit(Object event) async {}
  @override
  Future<void> close() async {}
}

@GenerateMocks([Host, EventBus, Conn])
void main() {
  group('IdentifyService', () {
    late MockHost mockHost;
    late MockEventBus mockEventBus;
    late FakeSubscription fakeSubscription;
    late FakeEmitter fakeEmitter;

    setUp(() {
      mockHost = MockHost();
      mockEventBus = MockEventBus();
      fakeSubscription = FakeSubscription();
      fakeEmitter = FakeEmitter();
      when(mockHost.eventBus).thenReturn(mockEventBus);
      when(mockEventBus.subscribe(any, opts: anyNamed('opts'))).thenReturn(fakeSubscription);
      when(mockEventBus.emitter(any, opts: anyNamed('opts'))).thenAnswer((_) async => fakeEmitter);
    });

    group('signedPeerRecordFromMessage', () {
      test('returns null when message has no signed peer record', () async {
        final msg = Identify();
        final service = IdentifyService(mockHost);
        final result = await service.signedPeerRecordFromMessage(msg);
        expect(result, isNull);
      });

      test('returns null when signed peer record is empty', () async {
        final msg = Identify(signedPeerRecord: []);
        final service = IdentifyService(mockHost);
        final result = await service.signedPeerRecordFromMessage(msg);
        expect(result, isNull);
      });

      test('returns null when signed peer record is invalid', () async {
        // Create an invalid signed peer record
        final msg = Identify(
          signedPeerRecord: [1, 2, 3, 4, 5], // Invalid protobuf data
        );
        
        final service = IdentifyService(mockHost);
        final result = await service.signedPeerRecordFromMessage(msg);
        
        expect(result, isNull);
      });
    });

    group('identifyWait', () {
      test('returns immediately for an already-closed connection', () async {
        // A conn closed before identify starts must not spawn _identifyConn
        // and must resolve as "known no-op" rather than tripping the
        // NO-COMPLETER warning path.
        final conn = MockConn();
        when(conn.isClosed).thenReturn(true);
        when(conn.id).thenReturn('closed-conn');
        when(conn.remotePeer).thenReturn(
          PeerId.decode('12D3KooWP4hU4GEAqu6Pi7v7XEKLLD6u3Ui2rTLv1x3UoEtv62SM'),
        );

        final service = IdentifyService(mockHost);
        await expectLater(service.identifyWait(conn), completes);
      });
    });
  });
}