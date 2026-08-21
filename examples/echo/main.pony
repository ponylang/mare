use lori = "lori"
use ws = "../../mare"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let config =
      ws.WebSocketConfig(where
        host' = "localhost",
        port' = "8080")
    EchoListener(auth, config, env.out)

actor EchoListener is lori.TCPListenerActor
  """
  Listens for TCP connections and spawns an EchoHandler for each one.
  """
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
  """
  Handles a single client connection, echoing messages back.
  """
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
    _out.print("Text: " + data)
    _ws.send_text(data)

  fun ref on_binary_message(data: Array[U8] val) =>
    _out.print("Binary: " + data.size().string() + " bytes")
    _ws.send_binary(data)

  fun ref on_closed(
    close_status: ws.CloseStatus,
    close_reason: String val)
  =>
    _out.print("Client disconnected: " + close_status.string() +
      if close_reason.size() > 0 then " (" + close_reason + ")" else "" end)
