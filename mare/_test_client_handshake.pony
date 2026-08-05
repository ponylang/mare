use "pony_test"

primitive \nodoc\ _TestClientHandshakeHelper
  """
  Fixtures for client handshake testing.

  The key and accept values are the worked example from RFC 6455 Section
  1.3, which is why `_ClientHandshake` takes its key as an argument rather
  than generating one: a fixed key makes the expected accept value a
  constant the RFC supplies for us.
  """

  fun key(): String val => "dGhlIHNhbXBsZSBub25jZQ=="

  fun accept(): String val => "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

  fun config(): WebSocketClientConfig val => WebSocketClientConfig

  fun bytes(s: String val): Array[U8] iso^ => s.clone().iso_array()

  fun response(extra_headers: String val = ""): String val =>
    """A well formed 101 response, optionally with extra headers."""
    "HTTP/1.1 101 Switching Protocols\r\n" +
      "Upgrade: websocket\r\n" +
      "Connection: Upgrade\r\n" +
      "Sec-WebSocket-Accept: " + accept() + "\r\n" +
      extra_headers + "\r\n"

class \nodoc\ iso _TestClientHandshakeRequest is UnitTest
  """The upgrade request carries the headers RFC 6455 Section 4.1 requires."""
  fun name(): String => "client_handshake/request"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())
    let request = hs.request("example.com", "8080", false)

    h.assert_true(request.contains("GET / HTTP/1.1\r\n"), "request line")
    h.assert_true(request.contains("Upgrade: websocket\r\n"), "upgrade")
    h.assert_true(request.contains("Connection: Upgrade\r\n"), "connection")
    h.assert_true(
      request.contains(
        "Sec-WebSocket-Key: " + _TestClientHandshakeHelper.key() + "\r\n"),
      "key")
    h.assert_true(
      request.contains("Sec-WebSocket-Version: 13\r\n"), "version")
    h.assert_eq[String]("\r\n\r\n", request.substring(-4))

class \nodoc\ iso _TestClientHandshakeRequestHostPort is UnitTest
  """
  The Host header omits the port only when it is the scheme's default.

  RFC 6455 Section 4.1 asks for this, and some servers and routing layers
  match on the exact Host value.
  """
  fun name(): String => "client_handshake/request_host_port"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())

    h.assert_true(
      hs.request("example.com", "80", false).contains(
        "Host: example.com\r\n"),
      "ws default port omitted")
    h.assert_true(
      hs.request("example.com", "443", true).contains(
        "Host: example.com\r\n"),
      "wss default port omitted")
    h.assert_true(
      hs.request("example.com", "8080", false).contains(
        "Host: example.com:8080\r\n"),
      "non-default port kept")
    h.assert_true(
      hs.request("example.com", "80", true).contains(
        "Host: example.com:80\r\n"),
      "port 80 kept for wss, where it is not the default")

class \nodoc\ iso _TestClientHandshakeRequestOptional is UnitTest
  """Origin, subprotocols, and custom headers appear when configured."""
  fun name(): String => "client_handshake/request_optional"

  fun apply(h: TestHelper) =>
    let config = WebSocketClientConfig(where
      path' = "/socket",
      origin' = "https://example.com",
      subprotocols' = recover val ["chat"; "superchat"] end,
      headers' = recover val [("Authorization", "Bearer t0ken")] end)
    let hs = _ClientHandshake(_TestClientHandshakeHelper.key(), config)
    let request = hs.request("example.com", "80", false)

    h.assert_true(request.contains("GET /socket HTTP/1.1\r\n"), "path")
    h.assert_true(
      request.contains("Origin: https://example.com\r\n"), "origin")
    h.assert_true(
      request.contains("Sec-WebSocket-Protocol: chat, superchat\r\n"),
      "subprotocols joined")
    h.assert_true(
      request.contains("Authorization: Bearer t0ken\r\n"), "custom header")

class \nodoc\ iso _TestClientHandshakeValid is UnitTest
  """A well formed 101 response completes the handshake."""
  fun name(): String => "client_handshake/valid"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())
    match \exhaustive\ hs(
      _TestClientHandshakeHelper.bytes(_TestClientHandshakeHelper.response()))
    | let result: _ClientHandshakeResult =>
      h.assert_eq[U16](101, result.response.status)
      h.assert_eq[USize](0, result.remaining.size())
      match result.response.header("Upgrade")
      | let v: String val => h.assert_eq[String]("websocket", v)
      | None => h.fail("case-insensitive header lookup failed")
      end
    | _ClientHandshakeNeedMore => h.fail("expected a result")
    | let err: ClientHandshakeError => h.fail("unexpected: " + err.string())
    end

class \nodoc\ iso _TestClientHandshakeRemainingBytes is UnitTest
  """Frame bytes arriving in the same segment are handed back."""
  fun name(): String => "client_handshake/remaining_bytes"

  fun apply(h: TestHelper) ? =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())
    let data: String val = _TestClientHandshakeHelper.response() + "AB"
    match \exhaustive\ hs(_TestClientHandshakeHelper.bytes(data))
    | let result: _ClientHandshakeResult =>
      h.assert_eq[USize](2, result.remaining.size())
      h.assert_eq[U8]('A', result.remaining(0)?)
      h.assert_eq[U8]('B', result.remaining(1)?)
    | _ClientHandshakeNeedMore => h.fail("expected a result")
    | let err: ClientHandshakeError => h.fail("unexpected: " + err.string())
    end

class \nodoc\ iso _TestClientHandshakeIncremental is UnitTest
  """A response split across two reads is buffered until complete."""
  fun name(): String => "client_handshake/incremental"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())
    let full = _TestClientHandshakeHelper.response()

    match \exhaustive\ hs(_TestClientHandshakeHelper.bytes(full.substring(0, 20)))
    | _ClientHandshakeNeedMore => None // expected
    | let result: _ClientHandshakeResult => h.fail("completed too early")
    | let err: ClientHandshakeError => h.fail("unexpected: " + err.string())
    end

    match \exhaustive\ hs(_TestClientHandshakeHelper.bytes(full.substring(20)))
    | let result: _ClientHandshakeResult =>
      h.assert_eq[U16](101, result.response.status)
    | _ClientHandshakeNeedMore => h.fail("still incomplete")
    | let err: ClientHandshakeError => h.fail("unexpected: " + err.string())
    end

class \nodoc\ iso _TestClientHandshakeAcceptMismatch is UnitTest
  """
  An accept value not derived from our key fails the handshake.

  This is the check that distinguishes a server completing this handshake
  from a cache replaying an old response or a proxy answering on its own.
  """
  fun name(): String => "client_handshake/accept_mismatch"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      "AAAAAAAAAAAAAAAAAAAAAA==",
      _TestClientHandshakeHelper.config())
    match hs(
      _TestClientHandshakeHelper.bytes(_TestClientHandshakeHelper.response()))
    | ClientHandshakeAcceptMismatch => None // expected
    else
      h.fail("expected ClientHandshakeAcceptMismatch")
    end

class \nodoc\ iso _TestClientHandshakeMissingAccept is UnitTest
  """A 101 response without Sec-WebSocket-Accept is rejected."""
  fun name(): String => "client_handshake/missing_accept"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())
    let response: String val =
      "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n" +
      "Connection: Upgrade\r\n\r\n"
    match hs(_TestClientHandshakeHelper.bytes(response))
    | ClientHandshakeMissingAccept => None // expected
    else
      h.fail("expected ClientHandshakeMissingAccept")
    end

class \nodoc\ iso _TestClientHandshakeMissingUpgrade is UnitTest
  """A 101 response without the Upgrade handshake headers is rejected."""
  fun name(): String => "client_handshake/missing_upgrade"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())
    let response: String val =
      "HTTP/1.1 101 Switching Protocols\r\nSec-WebSocket-Accept: " +
      _TestClientHandshakeHelper.accept() + "\r\n\r\n"
    match hs(_TestClientHandshakeHelper.bytes(response))
    | ClientHandshakeMissingUpgrade => None // expected
    else
      h.fail("expected ClientHandshakeMissingUpgrade")
    end

class \nodoc\ iso _TestClientHandshakeUnexpectedStatus is UnitTest
  """
  A non-101 status is reported along with the status itself.

  The code is the useful part: 401 means supply credentials, 3xx means the
  endpoint moved, 5xx means retry.
  """
  fun name(): String => "client_handshake/unexpected_status"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())
    match hs(_TestClientHandshakeHelper.bytes(
      "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic\r\n\r\n"))
    | let err: ClientHandshakeUnexpectedStatus =>
      h.assert_eq[U16](401, err.status)
      h.assert_eq[String]("Unexpected HTTP status 401", err.string())
    else
      h.fail("expected ClientHandshakeUnexpectedStatus")
    end

class \nodoc\ iso _TestClientHandshakeInvalidHTTP is UnitTest
  """A response that is not HTTP/1.1 is rejected."""
  fun name(): String => "client_handshake/invalid_http"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())
    match hs(_TestClientHandshakeHelper.bytes("ICY 200 OK\r\n\r\n"))
    | ClientHandshakeInvalidHTTP => None // expected
    else
      h.fail("expected ClientHandshakeInvalidHTTP")
    end

class \nodoc\ iso _TestClientHandshakeResponseTooLarge is UnitTest
  """A response exceeding max_handshake_size is rejected."""
  fun name(): String => "client_handshake/response_too_large"

  fun apply(h: TestHelper) =>
    let config = WebSocketClientConfig(where max_handshake_size' = 16)
    let hs = _ClientHandshake(_TestClientHandshakeHelper.key(), config)
    match hs(
      _TestClientHandshakeHelper.bytes(_TestClientHandshakeHelper.response()))
    | ClientHandshakeResponseTooLarge => None // expected
    else
      h.fail("expected ClientHandshakeResponseTooLarge")
    end

class \nodoc\ iso _TestClientHandshakeUnsolicitedExtension is UnitTest
  """
  An extension the client never offered is rejected.

  Mare offers none, so any value here would commit the connection to a
  framing the parser does not implement.
  """
  fun name(): String => "client_handshake/unsolicited_extension"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())
    match hs(_TestClientHandshakeHelper.bytes(
      _TestClientHandshakeHelper.response(
        "Sec-WebSocket-Extensions: permessage-deflate\r\n")))
    | ClientHandshakeUnsolicitedExtension => None // expected
    else
      h.fail("expected ClientHandshakeUnsolicitedExtension")
    end

class \nodoc\ iso _TestClientHandshakeUnsolicitedSubprotocol is UnitTest
  """A subprotocol the client never offered is rejected."""
  fun name(): String => "client_handshake/unsolicited_subprotocol"

  fun apply(h: TestHelper) =>
    let hs = _ClientHandshake(
      _TestClientHandshakeHelper.key(),
      _TestClientHandshakeHelper.config())
    match hs(_TestClientHandshakeHelper.bytes(
      _TestClientHandshakeHelper.response(
        "Sec-WebSocket-Protocol: chat\r\n")))
    | ClientHandshakeUnsolicitedSubprotocol => None // expected
    else
      h.fail("expected ClientHandshakeUnsolicitedSubprotocol")
    end

class \nodoc\ iso _TestClientHandshakeOfferedSubprotocol is UnitTest
  """A subprotocol that was offered is accepted and readable."""
  fun name(): String => "client_handshake/offered_subprotocol"

  fun apply(h: TestHelper) =>
    let config = WebSocketClientConfig(where
      subprotocols' = recover val ["chat"; "superchat"] end)
    let hs = _ClientHandshake(_TestClientHandshakeHelper.key(), config)
    match \exhaustive\ hs(_TestClientHandshakeHelper.bytes(
      _TestClientHandshakeHelper.response(
        "Sec-WebSocket-Protocol: superchat\r\n")))
    | let result: _ClientHandshakeResult =>
      match result.response.header("sec-websocket-protocol")
      | let v: String val => h.assert_eq[String]("superchat", v)
      | None => h.fail("selected subprotocol not readable")
      end
    | _ClientHandshakeNeedMore => h.fail("expected a result")
    | let err: ClientHandshakeError => h.fail("unexpected: " + err.string())
    end
