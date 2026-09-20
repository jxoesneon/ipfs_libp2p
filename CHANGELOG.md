# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
