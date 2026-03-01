"""
A WebSocket server that demonstrates server-initiated close and close
status handling.

Send "goodbye" to trigger a normal close (1000), "kick" to trigger a
policy violation close (1008), or any other message to echo it back.
The `on_closed` callback matches on `CloseStatus` variants to log how
the connection closed.

Connect with: `websocat ws://localhost:8082`
"""
use lori = "lori"
use ws = "../../mare"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let config = ws.WebSocketConfig(where
      host' = "localhost",
      port' = "8082")
    CloseListener(auth, config, env.out)

actor CloseListener is lori.TCPListenerActor
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

  fun ref _on_accept(fd: U32): CloseHandler =>
    CloseHandler(_server_auth, fd, _config, _out)

  fun ref _on_listening() =>
    _out.print("Listening on " + _config.host + ":" + _config.port)

  fun ref _on_listen_failure() =>
    _out.print("Failed to listen on " + _config.host + ":" + _config.port)

actor CloseHandler is ws.WebSocketServerActor
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
    _out.print("Client connected")

  fun ref on_text_message(data: String val) =>
    if data == "goodbye" then
      _out.print("Client said goodbye, closing normally")
      _ws.close(ws.CloseNormal, "client said goodbye")
    elseif data == "kick" then
      _out.print("Kicking client")
      _ws.close(ws.ClosePolicyViolation, "kicked")
    else
      _out.print("Echo: " + data)
      _ws.send_text(data)
    end

  fun ref on_closed(
    close_status: ws.CloseStatus,
    close_reason: String val)
  =>
    let reason_suffix =
      if close_reason.size() > 0 then " (" + close_reason + ")"
      else ""
      end

    match \exhaustive\ close_status
    | let c: ws.CloseCode =>
      _out.print("Closed with code: " + c.string() + reason_suffix)
    | let _: ws.CloseNoStatusReceived =>
      _out.print("Closed without status code")
    | let _: ws.CloseAbnormalClosure =>
      _out.print("Connection dropped abnormally")
    | let c: ws.OtherCloseCode =>
      _out.print("Closed with other code: " + c.code().string()
        + reason_suffix)
    end
