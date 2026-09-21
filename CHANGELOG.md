# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.11] - 2026-09-21

- **Fixed**: `YamuxStream` read waits now enforce deadlines through a
  stream-owned, cancellable timer instead of a timeout snapshotted when the
  wait begins. A read that started while the negotiation deadline was armed
  kept that deadline even after `setDeadline(null)` cleared it, so
  long-lived inbound streams (gossipsub, identify) were killed ~10s after
  negotiation. Clearing or changing a deadline now disarms/re-arms the
  in-flight wait immediately.

## [0.5.10] - 2026-09-20

- **Fixed**: `P2PStreamAdapter.setDeadline(null)` now forwards the clear to
  the underlying `MuxedStream` instead of dropping it. The negotiation
  deadline previously stayed armed on inbound streams, so every later read
  timed out ~10s after stream creation and long-lived inbound streams
  (gossipsub, identify) entered a kill/respawn cycle with go-libp2p peers.
  `MuxedStream.setDeadline` accepts a nullable `DateTime`.
- **Fixed**: `IdentifyService.identifyWait` no longer logs a false
  `NO-COMPLETER` warning when the already-identified or already-closed
  early-return path resolved the wait.

## [0.5.9] - 2026-09-20

- **Fixed**: Yamux inbound-stream creation no longer blocks the session
  read loop. Remote-initiated streams are registered before the SYN-ACK
  is sent, and the SYN-ACK, initial window update, per-stream PONG, and
  threshold window updates are sent fire-and-forget. A stalled write
  previously froze all inbound frame processing, which starved
  multistream-select negotiation and caused interop peers (e.g. Kubo) to
  time out and reset inbound streams.
- **Fixed**: `YamuxSession.acceptStream()` drains a buffered queue so
  inbound streams are never lost when no accept call is waiting.
- **Fixed**: A failed data-path window-update send restores the consumed
  byte accounting so the remote sender's credit is retried rather than
  permanently reduced.
- **Added**: `YamuxStream.openIncoming()` for remote-initiated streams.
- **Added**: regression tests covering blocked-write inbound stream
  creation, eager post-SYN data delivery, acceptStream race prevention,
  and window-update failure recovery.

## [0.5.8] - 2026-09-20

- **Merged**: semantic fixes from upstream `dart_libp2p` 1.0.3 while
  preserving this fork's implementation lineage.
- **Fixed**: Yamux sessions now close (goAway/internalError) when the
  keepalive ping send fails, instead of remaining open as zombies.
- **Fixed**: Yamux flow-control credit is preserved when a window-update
  send fails, and the failure no longer kills the session read loop.
- **Fixed**: Identify now awaits protoBook updates before completing,
  removing a race where advertised protocols (e.g. pubsub capability)
  could lag behind the identify response.
- **Fixed**: Inbound stream negotiation now runs under the configured
  negotiation deadline.
- **Fixed**: Connection pruning respects protected-connection tags and
  classifies timeout errors correctly.
- **Changed**: AutoNAT v2 client and server use varint-delimited protobuf
  framing matching go-libp2p, with response-type validation and exact
  dial-data byte accounting.
- **Added**: `AutoNATv2.hasPeers`; ambient AutoNAT v2 applies exponential
  backoff (10s-60s) when no AutoNAT-capable peers exist and emits an
  initial UNKNOWN reachability so AutoRelay can start immediately.
- **Fixed**: AutoRelay starts RelayFinder eagerly when initial
  reachability is private/unknown; behind CGNAT an unknown->unknown
  transition never fires a change event, so RelayFinder previously
  never started.
- **Changed**: Circuit relay v2 client/relay and AutoRelay finder adopt
  upstream's reworked relayed-connection handling (STOP stream
  processing, circuit address construction, connection tracking).
- **Tests**: imported upstream coverage for identify, swarm, yamux,
  circuitv2, autorelay, autonat, tcp_connection, multistream and
  secured_connection.

## [0.5.7] - 2026-09-20

- **Fixed**: `YamuxSession.openStream` no longer blocks on the remote peer's
  stream ACK before returning the stream. Implementations such as js-yamux
  send the ACK lazily (piggybacked on the acceptor's first outgoing frame),
  which deadlocked every outbound stream against js-libp2p/Helia peers
  during multistream negotiation. The stream is now opened immediately
  after the SYN frame, matching go-yamux semantics; the ACK is consumed
  asynchronously by the session read loop.
- **Fixed**: EOF during the secured-connection read loop no longer throws
  `RangeError` — a finer-level log dereferenced the empty length-prefix
  buffer before the EOF check, which surfaced clean transport shutdown as
  a session error.

## [0.5.6] - 2026-02-03

- **Fixed**: Replaced broken ASCII architecture diagram in README.md.

## [0.5.5] - 2026-02-03

- **Fixed**: Corrected character encoding issues in README.md (Mojibake).
- **Security**: Upgraded `pointycastle` to `^4.0.0` for improved security.
- **Changed**: Major dependency upgrades for `lints` and other dev dependencies.

## [0.5.4] - 2026-02-03

### Fixed

- Fixed analysis warnings and errors for publishing.
- Improved connection health monitoring logic.
- Resolved recursive call in ECDSA key generation.

## [0.5.3] - 2025-08-16

### Changed

- Updated the Quickstart example in the README. The original example was referencing outdated APIs and would not compile.

### Added

- Initial changelog documentation

## [0.5.2] - 2025-07-29

### Added

- Comprehensive documentation in `/doc` directory
- Architecture overview and component documentation
- Configuration guide with flexible options system
- Transport layer documentation (TCP and UDX)
- Security protocol documentation (Noise)
- Multiplexing documentation (Yamux)
- Protocol documentation (Ping, Identify, etc.)
- Peerstore management documentation
- Event bus system documentation
- Resource manager documentation
- Cookbook with practical examples
- Getting started guide with step-by-step instructions
- README.md with project overview and quick start guide
- MIT LICENSE file

### Changed

- Improved project structure and organization
- Enhanced documentation coverage across all components
- Better code examples and usage patterns

### Fixed

- Documentation links and cross-references
- Code examples in documentation

---

## Contributing

When contributing to this project, please update this changelog by adding a new entry under the `[Unreleased]` section. Follow the existing format and include:

- **Added**: for new features
- **Changed**: for changes in existing functionality
- **Deprecated**: for soon-to-be removed features
- **Removed**: for now removed features
- **Fixed**: for any bug fixes
- **Security**: in case of vulnerabilities

## Release Process

1. Update version in `pubspec.yaml`
2. Add new changelog entry under `[Unreleased]`
3. Move `[Unreleased]` content to new version section
4. Update release date
5. Tag the release in git
