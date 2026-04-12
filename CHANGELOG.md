# Change Log

All notable changes to this project will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org/) and [Keep a CHANGELOG](http://keepachangelog.com/).

## [unreleased] - unreleased

### Fixed


### Added


### Changed


## [0.3.0] - 2026-04-12

### Fixed

- Fix potential connection hang when timer event subscription fails ([PR #41](https://github.com/ponylang/mare/pull/41))

### Changed

- Require ponyc 0.63.1 or later ([PR #41](https://github.com/ponylang/mare/pull/41))

## [0.2.4] - 2026-04-07

### Fixed

- Fix connection stall after large message with backpressure ([PR #40](https://github.com/ponylang/mare/pull/40))

## [0.2.3] - 2026-03-28

### Fixed

- Fix crash when dispose() arrives before connection initialization ([PR #37](https://github.com/ponylang/mare/pull/37))

## [0.2.2] - 2026-03-22

### Fixed

- Fix idle timer issues with TLS-secured WebSocket connections ([PR #34](https://github.com/ponylang/mare/pull/34))

### Changed

- Update ponylang/ssl to 2.0.1 ([PR #33](https://github.com/ponylang/mare/pull/33))

## [0.2.1] - 2026-03-15

### Fixed

- Fix dispose() hanging when peer FIN is missed ([PR #32](https://github.com/ponylang/mare/pull/32))

## [0.2.0] - 2026-03-12

### Changed

- Update lori dependency to 0.10.0 ([PR #29](https://github.com/ponylang/mare/pull/29))

## [0.1.1] - 2026-03-11

### Added

- Forward on_idle_timeout to WebSocketLifecycleEventReceiver ([PR #26](https://github.com/ponylang/mare/pull/26))

## [0.1.0] - 2026-02-26

### Added

- Initial release

