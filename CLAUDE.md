# Mare — WebSocket Server

## Building

This project requires an SSL version flag because it depends on the `ssl` package for SHA-1 (handshake accept key computation).

```
make test ssl=3.0.x          # Build + run tests + build examples
make unit-tests ssl=3.0.x    # Just tests
make examples ssl=3.0.x # Just examples
```

## Dependencies

- **lori** (0.10.0) — TCP networking. Provides `TCPListener`, `TCPConnection`, and the actor/lifecycle-receiver pattern.
- **ssl** (2.0.0) — SHA-1 digest for computing the WebSocket handshake accept key (`ssl/crypto`). Also provides `ssl/net` for WSS (TLS) support.
- **stdlib encode/base64** — Base64 encoding/decoding for the handshake accept key.

Import aliases used consistently across the codebase:
- `use lori = "lori"`
- `use crypto = "ssl/crypto"`
- `use ssl_net = "ssl/net"` (only in `web_socket_server.pony`)
- `use "encode/base64"` (unqualified)

## Architecture

Follows lori/stallion's "your actor IS the connection" pattern. Users implement two actors:

1. **Listener actor** — implements `lori.TCPListenerActor`, accepts connections, creates handler actors.
2. **Handler actor** — implements `WebSocketServerActor` (which combines `lori.TCPConnectionActor` + `WebSocketLifecycleEventReceiver`). Each handler owns a `WebSocketServer` protocol handler instance.

`WebSocketServer` is a class (not an actor) that implements `lori.ServerLifecycleEventReceiver`. It owns the state machine, parsers, and frame encoder. All protocol logic runs synchronously within the handler actor's context.

## State Machine

Four states, implemented as a trait (`_ConnectionState`) with concrete state classes. Every state handles every event — the state machine is the single place to understand behavior.

```
_Handshaking → _Open → _Closing → _Closed
                 ↓                    ↑
                 └────────────────────┘
                 (error / abnormal close)
```

- **`_Handshaking`**: Buffers HTTP upgrade request via `_HandshakeParser`. On success, sends 101 response, transitions to `_Open`. On error, sends HTTP error, closes TCP.
- **`_Open`**: Parses WebSocket frames via `_FrameParser`, reassembles fragments via `_FragmentReassembler`. Handles ping/pong automatically. Delivers text/binary messages to user callbacks.
- **`_Closing`**: Server initiated close, waiting for client's close response. Only processes close and control frames; data frames are discarded.
- **`_Closed`**: Terminal state, all operations are no-ops.

## Internal Components

| File | Type | Purpose |
|------|------|---------|
| `_handshake_parser.pony` | `_HandshakeParser` | Buffers and parses HTTP upgrade request, validates WebSocket headers, computes accept key |
| `_frame_parser.pony` | `_FrameParser` | Incremental WebSocket frame parser with masking, length decoding, validation |
| `_frame_encoder.pony` | `_FrameEncoder` | Builds outgoing server frames (never masked) |
| `_fragment_reassembler.pony` | `_FragmentReassembler` | Reassembles fragmented messages, enforces size limits, validates UTF-8 for text |
| `_close_status_extractor.pony` | `_CloseStatusExtractor` | Extracts `(CloseStatus, String val)` from raw close frame payload |
| `_utf8_validator.pony` | `_Utf8Validator` | UTF-8 byte sequence validation |
| `_connection_state.pony` | `_ConnectionState` | State machine trait + four state classes |
| `_unreachable.pony` | `_Unreachable` | Crash-on-bug helper for impossible code paths |

## Naming Conventions

- `_` prefix on type names = package-private (visible within `mare/` package, not to consumers)
- `_` prefix on members = type-private (only accessible within the defining type)
- File names match the primary type they contain (e.g., `web_socket_server.pony` contains `WebSocketServer`)

## Test Patterns

Tests are in `mare/_test*.pony` files, registered in `_test.pony`. Mix of:
- **Example-based unit tests** for specific scenarios (valid input, each error case, boundary conditions)
- **PonyCheck property tests** for invariants over generated inputs (roundtrip encoding, valid input acceptance, fragment reassembly)

Tests run sequentially with `--exclude=integration` (no integration tests in v1).

## Design Decisions

- **Close timeout deferred**: The design specifies a close handshake timeout, but it's omitted from v1. Lori's idle timeout resets on any TCP receive, making it unreliable for close timeouts. OS TCP timeout handles the degenerate case.
- **Send errors silently dropped**: `_tcp_connection.send()` errors (`SendErrorNotConnected`, `SendErrorNotWriteable`) are ignored — mare can't do anything useful in either case.
- **No integration tests in v1**: Unit tests cover parsing, encoding, and reassembly. Integration tests requiring TCP connections are deferred.
