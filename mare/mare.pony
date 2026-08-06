"""
# Mare

WebSocket servers and clients for Pony, built on
[lori](https://github.com/ponylang/lori).

## Architecture

Mare follows lori's "your actor IS the connection" pattern. A protocol
handler class lives inside your actor and handles the wire format; your
actor receives application-level events.

For a server:

- A **listener actor** (`lori.TCPListenerActor`) accepts TCP connections.
  On each accept, it creates a new connection actor.
- A **connection actor** (`WebSocketServerActor`) owns a `WebSocketServer`
  protocol handler and receives WebSocket lifecycle callbacks.

For a client there is no listener — a single actor
(`WebSocketClientActor`) owns a `WebSocketClient` and dials out.

Both handlers cover the same protocol details — the HTTP upgrade
handshake, frame parsing, masking, fragmentation, and the close
handshake — and deliver application-level events through
`WebSocketServerLifecycleEventReceiver` or
`WebSocketClientLifecycleEventReceiver`.

The two sides are not symmetric on the wire, and the API reflects that.
A client masks every frame it sends and must receive only unmasked ones; a
server is the reverse (RFC 6455 Sections 5.1 and 5.2). A client sends the
upgrade request and validates the response; a server does the opposite.

## Quick Start: Server

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

## Quick Start: Client

A client that sends one message and prints the reply:

```pony
use lori = "lori"
use "mare"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPConnectAuth(env.root)
    Client(auth, "localhost", "8080", WebSocketClientConfig, env.out)

actor Client is WebSocketClientActor
  var _ws: WebSocketClient = WebSocketClient.none()
  let _out: OutStream

  new create(auth: lori.TCPConnectAuth, host: String, port: String,
    config: WebSocketClientConfig val, out: OutStream)
  =>
    _out = out
    _ws = WebSocketClient(auth, host, port, "", this, config)

  fun ref _websocket(): WebSocketClient => _ws

  fun ref on_open(response: UpgradeResponse val) =>
    _ws.send_text("hello")

  fun ref on_text_message(data: String val) =>
    _out.print("server said: " + data)
    _ws.close()

  fun ref on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _out.print("could not connect")

  fun ref on_handshake_failure(err: ClientHandshakeError) =>
    _out.print("upgrade refused: " + err.string())
```

The connection is not usable until `on_open()` fires. lori connects
asynchronously and the upgrade handshake follows, so sends made before
then are dropped rather than queued.

## WSS (Secure WebSocket)

For TLS-encrypted connections, use `ssl()` instead of `create()` and pass
an `ssl.net.SSLContext`.

Server side:

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

Client side:

```pony
_ws = WebSocketClient.ssl(
  auth, ssl_ctx, host, port, "", this, config)
```

## Configuration

`WebSocketServerConfig` controls a server's behavior:

- `host` / `port` — bind address (defaults: `"localhost"` / `"8080"`)
- `max_message_size` — maximum reassembled message size in bytes
  (default: 1 MB)
- `max_handshake_size` — maximum HTTP upgrade request size (default: 8 KB)

`WebSocketClientConfig` controls a client's:

- `path` — request target of the upgrade request (default: `"/"`)
- `origin` — sets an `Origin` header when present
- `subprotocols` — offered in `Sec-WebSocket-Protocol`; a server that
  selects anything outside this list fails the handshake
- `headers` — sent verbatim, which is where credentials belong
- `max_message_size` / `max_handshake_size` — as above

The target host and port are arguments to `WebSocketClient` rather than
config fields: lori needs them to open the connection, and the `Host`
header derives from them.

## Lifecycle Callbacks

Override any of these on your `WebSocketServerActor`:

- `on_upgrade_request(request)` — inspect the HTTP upgrade before
  accepting; return `false` to reject with 403
- `on_open(request)` — connection established
- `on_text_message(data)` — complete text message received
- `on_binary_message(data)` — complete binary message received
- `on_pong(payload)` — a pong answering a ping you sent; incoming pings
  are answered automatically and do not surface
- `on_closed(close_status, close_reason)` — connection closed;
  `close_status` is a `CloseStatus` indicating why
  (e.g., `CloseNormal`, `CloseAbnormalClosure`), `close_reason` is
  the UTF-8 reason string from the close frame (or empty)
- `on_throttled()` / `on_unthrottled()` — backpressure signals

On your `WebSocketClientActor` the same message, close, and backpressure
callbacks apply, with these differences:

- `on_open(response)` takes an `UpgradeResponse` instead of a request
- there is no `on_upgrade_request()` — a client makes the request
- `on_connection_failure(reason)` — the connection never opened, so no
  `on_closed()` follows
- `on_handshake_failure(err)` — TCP connected but the server's upgrade
  response was unacceptable; see `ClientHandshakeError`

## Sending Messages

Call methods on your `WebSocketServer` or `WebSocketClient` instance:

- `send_text(data)` — send a text message
- `send_binary(data)` — send a binary message
- `send_ping(payload)` — send a ping; the payload defaults to empty and
  must be 125 bytes or fewer (RFC 6455 Section 5.5), otherwise it is
  dropped rather than sent
- `close(code, reason)` — initiate a close handshake

Incoming pings are answered automatically on both sides, so `send_ping()`
is only needed to initiate a keepalive of your own. The peer echoes the
payload back through `on_pong()`, so stamping the ping lets you measure the
round trip.
"""
