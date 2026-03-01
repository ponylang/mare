use "pony_test"
use "pony_check"
use "encode/base64"
use crypto = "ssl/crypto"

primitive \nodoc\ _TestHandshakeHelper
  """Helpers for building HTTP upgrade requests."""

  fun valid_request(
    uri: String val = "/",
    key: String val = "dGhlIHNhbXBsZSBub25jZQ==",
    extra_headers: String val = "")
    : Array[U8] iso^
  =>
    """Build a valid HTTP upgrade request."""
    let s = String(512)
      .>append("GET ")
      .>append(uri)
      .>append(" HTTP/1.1\r\n")
      .>append("Host: localhost\r\n")
      .>append("Upgrade: websocket\r\n")
      .>append("Connection: Upgrade\r\n")
      .>append("Sec-WebSocket-Key: ")
      .>append(key)
      .>append("\r\n")
      .>append("Sec-WebSocket-Version: 13\r\n")
      .>append(extra_headers)
      .>append("\r\n")
    s.clone().iso_array()

  fun compute_accept_key(key: String val): String val =>
    """Compute expected Sec-WebSocket-Accept value."""
    let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    let sha = crypto.Digest.sha1()
    try sha.>append(key)?.append(magic)? else _Unreachable() end
    let hash = sha.final()
    Base64.encode(hash)

class \nodoc\ iso _TestHandshakeValid is UnitTest
  """Valid complete upgrade request produces correct result."""
  fun name(): String => "handshake/valid_complete"

  fun apply(h: TestHelper) =>
    let parser = _HandshakeParser
    let data = _TestHandshakeHelper.valid_request()
    match \exhaustive\ parser(consume data, 8192)
    | let result: _HandshakeResult =>
      h.assert_eq[String]("/", result.request.uri)
      let expected_key =
        _TestHandshakeHelper.compute_accept_key(
          "dGhlIHNhbXBsZSBub25jZQ==")
      h.assert_eq[String](expected_key, result.accept_key)
      h.assert_eq[USize](0, result.remaining.size())
    | _HandshakeNeedMore =>
      h.fail("expected result, got need more")
    | let err: HandshakeError =>
      h.fail("expected result, got error")
    end

class \nodoc\ iso _TestHandshakeRemainingBytes is UnitTest
  """Bytes after \\r\\n\\r\\n are returned as remaining."""
  fun name(): String => "handshake/remaining_bytes"

  fun apply(h: TestHelper) ? =>
    let request_data = _TestHandshakeHelper.valid_request()
    // Append extra bytes after the request
    let extra: Array[U8] val = recover val [as U8: 0x81; 0x85] end
    let combined = recover iso
      let c = Array[U8]
      c.append(consume request_data)
      c.append(extra)
      c
    end
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume combined, 8192)
    | let result: _HandshakeResult =>
      h.assert_eq[USize](2, result.remaining.size())
      h.assert_eq[U8](0x81, result.remaining(0)?)
      h.assert_eq[U8](0x85, result.remaining(1)?)
    | _HandshakeNeedMore => h.fail("expected result")
    | let err: HandshakeError => h.fail("expected result")
    end

class \nodoc\ iso _TestHandshakeTooLarge is UnitTest
  """Request exceeding max size produces HandshakeRequestTooLarge."""
  fun name(): String => "handshake/too_large"

  fun apply(h: TestHelper) =>
    let parser = _HandshakeParser
    let data = _TestHandshakeHelper.valid_request()
    match \exhaustive\ parser(consume data, 10) // tiny max_size
    | HandshakeRequestTooLarge => None // expected
    | _HandshakeNeedMore => h.fail("expected too large error")
    | let _: _HandshakeResult => h.fail("expected too large error")
    | let err: HandshakeError => h.fail("wrong error type")
    end

class \nodoc\ iso _TestHandshakeInvalidMethod is UnitTest
  """Non-GET method produces HandshakeInvalidHTTP."""
  fun name(): String => "handshake/invalid_method"

  fun apply(h: TestHelper) =>
    let request: Array[U8] iso = recover iso
      let s = String(256)
        .>append("POST / HTTP/1.1\r\n")
        .>append("Host: localhost\r\n")
        .>append("Upgrade: websocket\r\n")
        .>append("Connection: Upgrade\r\n")
        .>append("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n")
        .>append("Sec-WebSocket-Version: 13\r\n")
        .>append("\r\n")
      s.clone().iso_array()
    end
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume request, 8192)
    | HandshakeInvalidHTTP => None // expected
    | _HandshakeNeedMore => h.fail("expected error")
    | let _: _HandshakeResult => h.fail("expected error")
    | let err: HandshakeError => h.fail("wrong error: " + err.string())
    end

class \nodoc\ iso _TestHandshakeMissingHost is UnitTest
  """Missing Host header produces HandshakeMissingHost."""
  fun name(): String => "handshake/missing_host"

  fun apply(h: TestHelper) =>
    let request: Array[U8] iso = recover iso
      let s = String(256)
        .>append("GET / HTTP/1.1\r\n")
        .>append("Upgrade: websocket\r\n")
        .>append("Connection: Upgrade\r\n")
        .>append("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n")
        .>append("Sec-WebSocket-Version: 13\r\n")
        .>append("\r\n")
      s.clone().iso_array()
    end
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume request, 8192)
    | HandshakeMissingHost => None // expected
    | _HandshakeNeedMore => h.fail("expected error")
    | let _: _HandshakeResult => h.fail("expected error")
    | let err: HandshakeError => h.fail("wrong error: " + err.string())
    end

class \nodoc\ iso _TestHandshakeMissingUpgrade is UnitTest
  """Missing Upgrade header produces HandshakeMissingUpgrade."""
  fun name(): String => "handshake/missing_upgrade"

  fun apply(h: TestHelper) =>
    let request: Array[U8] iso = recover iso
      let s = String(256)
        .>append("GET / HTTP/1.1\r\n")
        .>append("Host: localhost\r\n")
        .>append("Connection: Upgrade\r\n")
        .>append("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n")
        .>append("Sec-WebSocket-Version: 13\r\n")
        .>append("\r\n")
      s.clone().iso_array()
    end
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume request, 8192)
    | HandshakeMissingUpgrade => None // expected
    | _HandshakeNeedMore => h.fail("expected error")
    | let _: _HandshakeResult => h.fail("expected error")
    | let err: HandshakeError => h.fail("wrong error: " + err.string())
    end

class \nodoc\ iso _TestHandshakeWrongVersion is UnitTest
  """Wrong Sec-WebSocket-Version produces HandshakeWrongVersion."""
  fun name(): String => "handshake/wrong_version"

  fun apply(h: TestHelper) =>
    let request: Array[U8] iso = recover iso
      let s = String(256)
        .>append("GET / HTTP/1.1\r\n")
        .>append("Host: localhost\r\n")
        .>append("Upgrade: websocket\r\n")
        .>append("Connection: Upgrade\r\n")
        .>append("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n")
        .>append("Sec-WebSocket-Version: 8\r\n")
        .>append("\r\n")
      s.clone().iso_array()
    end
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume request, 8192)
    | HandshakeWrongVersion => None // expected
    | _HandshakeNeedMore => h.fail("expected error")
    | let _: _HandshakeResult => h.fail("expected error")
    | let err: HandshakeError => h.fail("wrong error: " + err.string())
    end

class \nodoc\ iso _TestHandshakeMissingKey is UnitTest
  """Missing Sec-WebSocket-Key produces HandshakeMissingKey."""
  fun name(): String => "handshake/missing_key"

  fun apply(h: TestHelper) =>
    let request: Array[U8] iso = recover iso
      let s = String(256)
        .>append("GET / HTTP/1.1\r\n")
        .>append("Host: localhost\r\n")
        .>append("Upgrade: websocket\r\n")
        .>append("Connection: Upgrade\r\n")
        .>append("Sec-WebSocket-Version: 13\r\n")
        .>append("\r\n")
      s.clone().iso_array()
    end
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume request, 8192)
    | HandshakeMissingKey => None // expected
    | _HandshakeNeedMore => h.fail("expected error")
    | let _: _HandshakeResult => h.fail("expected error")
    | let err: HandshakeError => h.fail("wrong error: " + err.string())
    end

class \nodoc\ iso _TestHandshakeInvalidKeyBadBase64 is UnitTest
  """Key with non-base64 characters produces HandshakeInvalidKey."""
  fun name(): String => "handshake/invalid_key_bad_base64"

  fun apply(h: TestHelper) =>
    let data = _TestHandshakeHelper.valid_request(
      where key = "!!!invalid-key!!!!!!!!!==")
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume data, 8192)
    | HandshakeInvalidKey => None // expected
    | _HandshakeNeedMore => h.fail("expected error")
    | let _: _HandshakeResult => h.fail("expected error")
    | let err: HandshakeError => h.fail("wrong error: " + err.string())
    end

class \nodoc\ iso _TestHandshakeInvalidKeyWrongLength is UnitTest
  """Valid base64 that decodes to != 16 bytes produces HandshakeInvalidKey."""
  fun name(): String => "handshake/invalid_key_wrong_length"

  fun apply(h: TestHelper) =>
    // "dGVzdA==" is base64 for "test" (4 bytes)
    let data = _TestHandshakeHelper.valid_request(where key = "dGVzdA==")
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume data, 8192)
    | HandshakeInvalidKey => None // expected
    | _HandshakeNeedMore => h.fail("expected error")
    | let _: _HandshakeResult => h.fail("expected error")
    | let err: HandshakeError => h.fail("wrong error: " + err.string())
    end

class \nodoc\ iso _TestHandshakeCaseInsensitive is UnitTest
  """Header values are matched case-insensitively."""
  fun name(): String => "handshake/case_insensitive"

  fun apply(h: TestHelper) =>
    let request: Array[U8] iso = recover iso
      let s = String(256)
        .>append("GET / HTTP/1.1\r\n")
        .>append("Host: localhost\r\n")
        .>append("upgrade: WebSocket\r\n")
        .>append("connection: Upgrade\r\n")
        .>append("sec-websocket-key: dGhlIHNhbXBsZSBub25jZQ==\r\n")
        .>append("sec-websocket-version: 13\r\n")
        .>append("\r\n")
      s.clone().iso_array()
    end
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume request, 8192)
    | let result: _HandshakeResult =>
      h.assert_eq[String]("/", result.request.uri)
    | _HandshakeNeedMore => h.fail("expected result")
    | let err: HandshakeError => h.fail("unexpected error: " + err.string())
    end

class \nodoc\ iso _TestHandshakeIncremental is UnitTest
  """Request split across multiple calls is assembled correctly."""
  fun name(): String => "handshake/incremental"

  fun apply(h: TestHelper) =>
    let full_request = _TestHandshakeHelper.valid_request()
    let full_size = full_request.size()

    // Split at roughly the middle
    let split_at = full_size / 2
    let parser = _HandshakeParser

    let first_half = recover iso
      let a = Array[U8](split_at)
      var i: USize = 0
      while i < split_at do
        try a.push(full_request(i)?) else _Unreachable() end
        i = i + 1
      end
      a
    end

    match \exhaustive\ parser(consume first_half, 8192)
    | _HandshakeNeedMore => None // expected
    | let _: _HandshakeResult => h.fail("too early")
    | let err: HandshakeError => h.fail("unexpected error")
    end

    let second_half = recover iso
      let a = Array[U8](full_size - split_at)
      var i: USize = split_at
      while i < full_size do
        try a.push(full_request(i)?) else _Unreachable() end
        i = i + 1
      end
      a
    end

    match \exhaustive\ parser(consume second_half, 8192)
    | let result: _HandshakeResult =>
      h.assert_eq[String]("/", result.request.uri)
    | _HandshakeNeedMore => h.fail("expected result after second chunk")
    | let err: HandshakeError => h.fail("unexpected error on second chunk")
    end

class \nodoc\ iso _TestHandshakeRfc6455AcceptKey is UnitTest
  """
  Accept key matches the RFC 6455 Section 4.2.2 example.

  Key: dGhlIHNhbXBsZSBub25jZQ==
  Expected Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
  """
  fun name(): String => "handshake/rfc6455_accept_key"

  fun apply(h: TestHelper) =>
    let parser = _HandshakeParser
    let data = _TestHandshakeHelper.valid_request()
    match \exhaustive\ parser(consume data, 8192)
    | let result: _HandshakeResult =>
      h.assert_eq[String]("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", result.accept_key)
    | _HandshakeNeedMore => h.fail("expected result")
    | let err: HandshakeError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestHandshakeConnectionMultiToken is UnitTest
  """
  Connection header with multiple comma-separated tokens containing
  'Upgrade' is accepted.
  """
  fun name(): String => "handshake/connection_multi_token"

  fun apply(h: TestHelper) =>
    let request: Array[U8] iso = recover iso
      let s = String(256)
        .>append("GET / HTTP/1.1\r\n")
        .>append("Host: localhost\r\n")
        .>append("Upgrade: websocket\r\n")
        .>append("Connection: keep-alive, Upgrade\r\n")
        .>append("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n")
        .>append("Sec-WebSocket-Version: 13\r\n")
        .>append("\r\n")
      s.clone().iso_array()
    end
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume request, 8192)
    | let result: _HandshakeResult =>
      h.assert_eq[String]("/", result.request.uri)
    | _HandshakeNeedMore => h.fail("expected result")
    | let err: HandshakeError => h.fail("unexpected error: " + err.string())
    end

class \nodoc\ iso _TestHandshakePropertyValidRequests is Property1[String]
  """Valid upgrade requests with random URIs always parse successfully."""
  fun name(): String => "handshake/property_valid_requests"

  fun gen(): Generator[String] =>
    Generators.ascii_letters(where min = 1, max = 50)

  fun property(uri_suffix: String, h: PropertyHelper) =>
    let test_uri: String val = "/" + uri_suffix
    let data = _TestHandshakeHelper.valid_request(where uri = test_uri)
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume data, 8192)
    | let result: _HandshakeResult =>
      h.assert_eq[String](test_uri, result.request.uri)
    | _HandshakeNeedMore =>
      h.fail("expected result for uri: " + test_uri)
    | let err: HandshakeError =>
      h.fail("unexpected error for uri: " + test_uri)
    end

class \nodoc\ iso _TestHandshakePropertyValidKeys is Property1[String]
  """
  Random 16-byte keys, base64-encoded, always produce a successful
  handshake.
  """
  fun name(): String => "handshake/property_valid_keys"

  fun gen(): Generator[String] =>
    Generators.byte_string(Generators.u8() where min = 16, max = 16)

  fun property(raw_key: String, h: PropertyHelper) =>
    let key: String val = Base64.encode(raw_key)
    let data = _TestHandshakeHelper.valid_request(where key = key)
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume data, 8192)
    | let result: _HandshakeResult => None // success expected
    | _HandshakeNeedMore =>
      h.fail("expected result for key: " + key)
    | let err: HandshakeError =>
      h.fail("unexpected error for key: " + key + " — " + err.string())
    end

class \nodoc\ iso _TestHandshakePropertyInvalidKeyLength is Property1[String]
  """
  Random byte strings of length != 16, base64-encoded, always produce
  HandshakeInvalidKey.
  """
  fun name(): String => "handshake/property_invalid_key_length"

  fun gen(): Generator[String] =>
    // Generate lengths 1-15 and 17-32, excluding 16
    let short = Generators.byte_string(Generators.u8() where min = 0, max = 15)
    let long = Generators.byte_string(Generators.u8() where min = 17, max = 32)
    short.union[String](long)

  fun property(raw_key: String, h: PropertyHelper) =>
    let key: String val = Base64.encode(raw_key)
    let data = _TestHandshakeHelper.valid_request(where key = key)
    let parser = _HandshakeParser
    match \exhaustive\ parser(consume data, 8192)
    | HandshakeInvalidKey => None // expected
    | _HandshakeNeedMore =>
      h.fail("expected HandshakeInvalidKey for key: " + key)
    | let _: _HandshakeResult =>
      h.fail("expected HandshakeInvalidKey but got success for key: " + key)
    | let err: HandshakeError =>
      h.fail("wrong error for key: " + key + " — " + err.string())
    end
