use "pony_test"
use lori = "lori"

class \nodoc\ iso _TestIntegrationEcho is UnitTest
  """
  A real client and a real server complete a full exchange over loopback.

  This is the only test that covers the two directions against each other:
  the client's masking is checked by the server's parser rather than by a
  test fixture, the handshake runs against a live peer, and the close
  handshake completes in both directions.

  Named `integration/` so `--exclude=integration` keeps it out of the unit
  test run, since it binds a socket.
  """
  fun name(): String => "integration/echo"

  fun exclusion_group(): String => "network"

  fun apply(h: TestHelper) =>
    h.long_test(20_000_000_000)
    _TestEchoListener(lori.TCPAuth(h.env.root), h)

actor \nodoc\ _TestEchoListener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _tcp_auth: lori.TCPAuth
  let _h: TestHelper

  new create(tcp_auth: lori.TCPAuth, h: TestHelper) =>
    _tcp_auth = tcp_auth
    _h = h
    _tcp_listener = lori.TCPListener(
      lori.TCPListenAuth(tcp_auth), "127.0.0.1", "0", this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_listening() =>
    // Port 0 binds an ephemeral port, so the client is not started until
    // the real port is known. This keeps the test from colliding with
    // anything else on the machine.
    try
      (_, let port) = _tcp_listener.local_address().name()?
      _TestEchoClient(lori.TCPConnectAuth(_tcp_auth), port, _h, this)
    else
      _h.fail("could not read the listener's address")
      _h.complete(false)
    end

  fun ref _on_listen_failure() =>
    _h.fail("could not listen on 127.0.0.1")
    _h.complete(false)

  fun ref _on_accept(fd: U32): _TestEchoServer =>
    _TestEchoServer(lori.TCPServerAuth(_tcp_auth), fd)

actor \nodoc\ _TestEchoServer is WebSocketServerActor
  var _ws: WebSocketServer = WebSocketServer.none()

  new create(auth: lori.TCPServerAuth, fd: U32) =>
    _ws = WebSocketServer(auth, fd, this, WebSocketServerConfig)

  fun ref _websocket(): WebSocketServer => _ws

  fun ref on_text_message(data: String val) =>
    _ws.send_text(data)

  fun ref on_binary_message(data: Array[U8] val) =>
    _ws.send_binary(data)

actor \nodoc\ _TestEchoClient is WebSocketClientActor
  var _ws: WebSocketClient = WebSocketClient.none()
  let _h: TestHelper
  let _listener: _TestEchoListener
  var _got_text: Bool = false
  var _got_binary: Bool = false

  new create(
    auth: lori.TCPConnectAuth,
    port: String,
    h: TestHelper,
    listener: _TestEchoListener)
  =>
    _h = h
    _listener = listener
    _ws = WebSocketClient(
      auth, "127.0.0.1", port, "", this, WebSocketClientConfig)

  fun ref _websocket(): WebSocketClient => _ws

  fun ref on_open(response: UpgradeResponse val) =>
    _h.assert_eq[U16](101, response.status)
    match response.header("upgrade")
    | let v: String val => _h.assert_eq[String]("websocket", v)
    | None => _h.fail("no Upgrade header in the response")
    end
    _ws.send_text("round trip")

  fun ref on_text_message(data: String val) =>
    _h.assert_eq[String]("round trip", data)
    _got_text = true
    // A binary message exercises the other opcode and a second mask key.
    _ws.send_binary(recover val [as U8: 0xDE; 0xAD; 0xBE; 0xEF] end)

  fun ref on_binary_message(data: Array[U8] val) =>
    try
      _h.assert_eq[USize](4, data.size())
      _h.assert_eq[U8](0xDE, data(0)?)
      _h.assert_eq[U8](0xEF, data(3)?)
    else
      _h.fail("binary payload was truncated")
    end
    _got_binary = true
    _ws.close()

  fun ref on_handshake_failure(err: ClientHandshakeError) =>
    _h.fail("handshake failed: " + err.string())
    _finish()

  fun ref on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _h.fail("could not connect to the test server")
    _finish()

  fun ref on_closed(
    close_status: CloseStatus,
    close_reason: String val)
  =>
    _h.assert_true(_got_text, "closed before the text echo arrived")
    _h.assert_true(_got_binary, "closed before the binary echo arrived")
    _h.assert_is[CloseStatus](CloseNormal, close_status)
    _finish()

  fun ref _finish() =>
    _listener.dispose()
    _h.complete(_got_text and _got_binary)
