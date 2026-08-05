"""
# Mare

A WebSocket server for Pony built on
[lori](https://github.com/ponylang/lori).

## Architecture

Mare follows lori's "your actor IS the connection" pattern:

- A **listener actor** (`lori.TCPListenerActor`) accepts TCP connections.
  On each accept, it creates a new connection actor.
- A **connection actor** (`WebSocketServerActor`) owns a `WebSocketServer`
  protocol handler and receives WebSocket lifecycle callbacks.

The `WebSocketServer` class handles all protocol details — HTTP upgrade
handshake, frame parsing, masking, fragmentation, and the close
handshake — and delivers application-level events through the
`WebSocketServerLifecycleEventReceiver` callbacks.

## Quick Start

A minimal echo server:

```pony
use lori = "lori"
use "mare"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let config = WebSocketServerConfig(where host' = "localhost", port' = "8080")
    EchoListener(auth, config)

actor EchoListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: WebSocketServerConfig val

  new create(auth: lori.TCPListenAuth, config: WebSocketServerConfig val) =>
    _server_auth = lori.TCPServerAuth(auth)
    _config = config
    _tcp_listener = lori.TCPListener(auth, config.host, config.port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): EchoHandler =>
    EchoHandler(_server_auth, fd, _config)

  fun ref _on_listen_failure() => None

actor EchoHandler is WebSocketServerActor
  var _ws: WebSocketServer = WebSocketServer.none()

  new create(auth: lori.TCPServerAuth, fd: U32,
    config: WebSocketServerConfig val)
  =>
    _ws = WebSocketServer(auth, fd, this, config)

  fun ref _websocket(): WebSocketServer => _ws

  fun ref on_text_message(data: String val) =>
    _ws.send_text(data)

  fun ref on_binary_message(data: Array[U8] val) =>
    _ws.send_binary(data)
```

## WSS (Secure WebSocket)

For TLS-encrypted connections, use `WebSocketServer.ssl()` instead of
`create()` and pass an `ssl.net.SSLContext`:

```pony
use ssl_net = "ssl/net"

// In the listener's _on_accept (store _server_auth from auth in constructor):
fun ref _on_accept(fd: U32): SecureHandler =>
  SecureHandler(_server_auth, _ssl_ctx, fd, _config)

// In the handler:
actor SecureHandler is WebSocketServerActor
  var _ws: WebSocketServer = WebSocketServer.none()

  new create(auth: lori.TCPServerAuth, ssl_ctx: ssl_net.SSLContext val,
    fd: U32, config: WebSocketServerConfig val)
  =>
    _ws = WebSocketServer.ssl(auth, ssl_ctx, fd, this, config)

  fun ref _websocket(): WebSocketServer => _ws
```

## Configuration

`WebSocketServerConfig` controls connection behavior:

- `host` / `port` — bind address (defaults: `"localhost"` / `"8080"`)
- `max_message_size` — maximum reassembled message size in bytes
  (default: 1 MB)
- `max_handshake_size` — maximum HTTP upgrade request size (default: 8 KB)

## Lifecycle Callbacks

Override any of these on your `WebSocketServerActor`:

- `on_upgrade_request(request)` — inspect the HTTP upgrade before
  accepting; return `false` to reject with 403
- `on_open(request)` — connection established
- `on_text_message(data)` — complete text message received
- `on_binary_message(data)` — complete binary message received
- `on_closed(close_status, close_reason)` — connection closed;
  `close_status` is a `CloseStatus` indicating why
  (e.g., `CloseNormal`, `CloseAbnormalClosure`), `close_reason` is
  the UTF-8 reason string from the close frame (or empty)
- `on_throttled()` / `on_unthrottled()` — backpressure signals

## Sending Messages

Call methods on your `WebSocketServer` instance:

- `send_text(data)` — send a text message
- `send_binary(data)` — send a binary message
- `close(code, reason)` — initiate a close handshake
"""
