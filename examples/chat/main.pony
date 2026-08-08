use collections = "collections"
use lori = "lori"
use ws = "../../mare"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let config =
      ws.WebSocketConfig(where
        host' = "localhost",
        port' = "8083")
    ChatListener(auth, config, env.out)

actor ChatListener is lori.TCPListenerActor
  """
  Listens for TCP connections and spawns a ChatHandler for each one.
  """
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: ws.WebSocketConfig val
  let _out: OutStream
  let _handlers: collections.SetIs[ChatHandler tag] =
    collections.SetIs[ChatHandler tag]

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

  fun ref _on_accept(fd: U32): ChatHandler =>
    ChatHandler(_server_auth, fd, _config, _out, this)

  fun ref _on_listening() =>
    _out.print("Listening on " + _config.host + ":" + _config.port)

  fun ref _on_listen_failure() =>
    _out.print("Failed to listen on " + _config.host + ":" + _config.port)

  be register(handler: ChatHandler tag) =>
    _handlers.set(handler)
    _out.print("Client joined (" + _handlers.size().string() + " connected)")

  be deregister(handler: ChatHandler tag) =>
    _handlers.unset(handler)
    _out.print("Client left (" + _handlers.size().string() + " connected)")

  be broadcast(sender: ChatHandler tag, data: String val) =>
    for handler in _handlers.values() do
      if handler isnt sender then
        handler.deliver(data)
      end
    end

actor ChatHandler is ws.WebSocketServerActor
  """
  Handles a single chat client's WebSocket connection.
  """
  var _ws: ws.WebSocketServer = ws.WebSocketServer.none()
  let _out: OutStream
  let _listener_tag: ChatListener tag

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ws.WebSocketConfig val,
    out: OutStream,
    listener: ChatListener tag)
  =>
    _out = out
    _listener_tag = listener
    _ws = ws.WebSocketServer(auth, fd, this, config)

  fun ref _websocket(): ws.WebSocketServer => _ws

  fun ref on_open(request: ws.UpgradeRequest val) =>
    _listener_tag.register(this)

  fun ref on_text_message(data: String val) =>
    _listener_tag.broadcast(this, data)

  fun ref on_closed(
    close_status: ws.CloseStatus,
    close_reason: String val)
  =>
    _listener_tag.deregister(this)

  be deliver(data: String val) =>
    _ws.send_text(data)
