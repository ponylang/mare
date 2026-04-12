# mare

A WebSocket server for Pony, implementing [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455).

## Status

mare is beta quality software that will change frequently. Expect breaking changes. That said, you should feel comfortable using it in your projects.

## Installation

* Requires ponyc 0.63.1 or later
* Install [corral](https://github.com/ponylang/corral)
* `corral add github.com/ponylang/mare.git --version 0.2.4`
* `corral fetch` to fetch your dependencies
* `use "mare"` to include this package
* `corral run -- ponyc` to compile your application

Mare has a transitive dependency on [ponylang/ssl](https://github.com/ponylang/ssl). It requires a C SSL library to be installed. Please see the [ssl installation instructions](https://github.com/ponylang/ssl?tab=readme-ov-file#installation) for more information.

## Usage

Here's a complete echo server that sends back every message it receives:

```pony
use lori = "lori"
use ws = "mare"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let config = ws.WebSocketConfig(where
      host' = "localhost",
      port' = "8080")
    EchoListener(auth, config, env.out)

actor EchoListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: ws.WebSocketConfig val
  let _out: OutStream

  new create(
    auth: lori.TCPListenAuth,
    config: ws.WebSocketConfig val,
    out: OutStream)
  =>
    _server_auth = lori.TCPServerAuth(auth)
    _config = config
    _out = out
    _tcp_listener = lori.TCPListener(auth, config.host, config.port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): EchoHandler =>
    EchoHandler(_server_auth, fd, _config, _out)

  fun ref _on_listening() =>
    _out.print("Listening on " + _config.host + ":" + _config.port)

  fun ref _on_listen_failure() =>
    _out.print("Failed to listen on " + _config.host + ":" + _config.port)

actor EchoHandler is ws.WebSocketServerActor
  var _ws: ws.WebSocketServer = ws.WebSocketServer.none()
  let _out: OutStream

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ws.WebSocketConfig val,
    out: OutStream)
  =>
    _out = out
    _ws = ws.WebSocketServer(auth, fd, this, config)

  fun ref _websocket(): ws.WebSocketServer => _ws

  fun ref on_open(request: ws.UpgradeRequest val) =>
    _out.print("Client connected: " + request.uri)

  fun ref on_text_message(data: String val) =>
    _ws.send_text(data)

  fun ref on_binary_message(data: Array[U8] val) =>
    _ws.send_binary(data)

  fun ref on_closed(
    close_status: ws.CloseStatus,
    close_reason: String val)
  =>
    _out.print("Client disconnected: " + close_status.string())
```

More examples are in the [examples](examples/) directory.

## API Documentation

[https://ponylang.github.io/mare](https://ponylang.github.io/mare)
