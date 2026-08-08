use "files"
use ssl_net = "ssl/net"
use lori = "lori"
use ws = "../../mare"

actor Main
  new create(env: Env) =>
    let file_auth = FileAuth(env.root)
    let sslctx =
      try
        recover val
          ssl_net.SSLContext
            .> set_authority(
              FilePath(file_auth, "assets/cert.pem"))?
            .> set_cert(
              FilePath(file_auth, "assets/cert.pem"),
              FilePath(file_auth, "assets/key.pem"))?
            .> set_client_verify(false)
            .> set_server_verify(false)
        end
      else
        env.out.print("Unable to set up SSL context")
        return
      end

    let auth = lori.TCPListenAuth(env.root)
    let config =
      ws.WebSocketConfig(where
        host' = "localhost",
        port' = "8443")
    WssListener(auth, config, env.out, sslctx)

actor WssListener is lori.TCPListenerActor
  """
  Listens for TLS connections and spawns a WssHandler for each one.
  """
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: ws.WebSocketConfig val
  let _out: OutStream
  let _ssl_ctx: ssl_net.SSLContext val

  new create(
    auth: lori.TCPListenAuth,
    config: ws.WebSocketConfig val,
    out: OutStream,
    ssl_ctx: ssl_net.SSLContext val)
  =>
    _server_auth = lori.TCPServerAuth(auth)
    _config = config
    _out = out
    _ssl_ctx = ssl_ctx
    _tcp_listener = lori.TCPListener(auth, config.host, config.port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): WssHandler =>
    WssHandler(_server_auth, fd, _config, _out, _ssl_ctx)

  fun ref _on_listening() =>
    _out.print("Listening on " + _config.host + ":" + _config.port)

  fun ref _on_listen_failure() =>
    _out.print("Failed to listen on " + _config.host + ":" + _config.port)

actor WssHandler is ws.WebSocketServerActor
  """
  Handles a single TLS client connection, echoing messages back.
  """
  var _ws: ws.WebSocketServer = ws.WebSocketServer.none()
  let _out: OutStream

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: ws.WebSocketConfig val,
    out: OutStream,
    ssl_ctx: ssl_net.SSLContext val)
  =>
    _out = out
    _ws = ws.WebSocketServer.ssl(auth, ssl_ctx, fd, this, config)

  fun ref _websocket(): ws.WebSocketServer => _ws

  fun ref on_open(request: ws.UpgradeRequest val) =>
    _out.print("Client connected (TLS)")

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
    _out.print("Client disconnected: " + close_status.string())
