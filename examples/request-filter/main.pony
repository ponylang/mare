use lori = "lori"
use ws = "../../mare"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let config =
      ws.WebSocketConfig(where
        host' = "localhost",
        port' = "8081")
    FilterListener(auth, config, env.out)

actor FilterListener is lori.TCPListenerActor
  """
  Listens for TCP connections and spawns a FilterHandler for each one.
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

  fun ref _on_accept(fd: U32): FilterHandler =>
    FilterHandler(_server_auth, fd, _config, _out)

  fun ref _on_listening() =>
    _out.print("Listening on " + _config.host + ":" + _config.port)

  fun ref _on_listen_failure() =>
    _out.print("Failed to listen on " + _config.host + ":" + _config.port)

actor FilterHandler is ws.WebSocketServerActor
  """
  Handles a single client connection, filtering by URI and Origin.
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

  fun ref on_upgrade_request(request: ws.UpgradeRequest val): Bool =>
    let origin =
      match \exhaustive\ request.header("Origin")
      | let o: String val => o
      | None => ""
      end

    if (request.uri == "/ws") and (origin == "http://localhost") then
      _out.print("Accepted: uri=" + request.uri +
        " origin=" + origin)
      true
    else
      _out.print("Rejected: uri=" + request.uri +
        " origin=" + origin)
      false
    end

  fun ref on_open(request: ws.UpgradeRequest val) =>
    _out.print("Client connected")

  fun ref on_text_message(data: String val) =>
    _out.print("Echo: " + data)
    _ws.send_text(data)

  fun ref on_closed(
    close_status: ws.CloseStatus,
    close_reason: String val)
  =>
    _out.print("Client disconnected: " + close_status.string())
