class _ClientHandshake
  """
  Builds a WebSocket upgrade request and validates the server's response.

  The client counterpart to `_HandshakeParser`. It holds the
  `Sec-WebSocket-Key` it sent for the lifetime of the handshake, because
  the accept value in the response only means anything when checked
  against that exact key.

  The key is supplied rather than generated here, which keeps the class
  pure: a given key and a given response have one right verdict, so
  RFC 6455's worked example is usable as a test vector.
  """
  let _key: String val
  let _config: WebSocketClientConfig val
  var _buf: Array[U8] ref = Array[U8]

  new create(key: String val, config: WebSocketClientConfig val) =>
    """Create a handshake that will offer the given key."""
    _key = key
    _config = config

  fun request(host: String val, port: String val, secure: Bool): String val =>
    """
    Build the HTTP upgrade request to send once TCP is connected.

    The `Host` header omits the port when it is the default for the scheme
    (RFC 6455 Section 4.1), so a connection to port 443 over TLS sends
    `Host: example.com` rather than `Host: example.com:443` — some servers
    and routing layers match on the exact value.
    """
    let default_port = if secure then "443" else "80" end

    recover val
      let r = String(256)
      r.>append("GET ")
        .>append(_config.path)
        .>append(" HTTP/1.1\r\nHost: ")
        .append(host)
      if port != default_port then
        r.>append(":").append(port)
      end
      r.>append("\r\nUpgrade: websocket\r\n")
        .>append("Connection: Upgrade\r\n")
        .>append("Sec-WebSocket-Key: ")
        .>append(_key)
        .append("\r\nSec-WebSocket-Version: 13\r\n")

      match _config.origin
      | let o: String val =>
        r.>append("Origin: ").>append(o).append("\r\n")
      | None => None
      end

      if _config.subprotocols.size() > 0 then
        r.append("Sec-WebSocket-Protocol: ")
        var first = true
        for p in _config.subprotocols.values() do
          if not first then
            r.append(", ")
          end
          r.append(p)
          first = false
        end
        r.append("\r\n")
      end

      for (name, value) in _config.headers.values() do
        r.>append(name).>append(": ").>append(value).append("\r\n")
      end

      r.append("\r\n")
      r
    end

  fun ref apply(data: Array[U8] iso)
    : ( _ClientHandshakeResult
      | _ClientHandshakeNeedMore
      | ClientHandshakeError )
  =>
    """
    Feed incoming data into the buffer and attempt to parse the response.

    Returns `_ClientHandshakeNeedMore` if the full HTTP response hasn't
    arrived yet, a `_ClientHandshakeResult` on success, or a
    `ClientHandshakeError` on failure.
    """
    _buf.append(consume data)

    if _buf.size() > _config.max_handshake_size then
      return ClientHandshakeResponseTooLarge
    end

    match \exhaustive\ _find_header_end()
    | None => _ClientHandshakeNeedMore
    | let pos: USize => _parse_response(pos)
    end

  fun _find_header_end(): (USize | None) =>
    """Find the position of \\r\\n\\r\\n in the buffer."""
    if _buf.size() < 4 then return None end
    var i: USize = 0
    let limit = _buf.size() - 3
    while i < limit do
      try
        if (_buf(i)? == '\r') and (_buf(i + 1)? == '\n')
          and (_buf(i + 2)? == '\r') and (_buf(i + 3)? == '\n')
        then
          return i
        end
      else
        _Unreachable()
      end
      i = i + 1
    end
    None

  fun _parse_response(header_end: USize)
    : (_ClientHandshakeResult | ClientHandshakeError)
  =>
    """Parse the buffered HTTP response up to header_end."""
    // Build response string from buffer bytes. String.clone() gives iso^
    // which auto-converts to val.
    let response_ref = String(header_end)
    var i: USize = 0
    while i < header_end do
      try response_ref.push(_buf(i)?) else _Unreachable() end
      i = i + 1
    end
    let response_str: String val = response_ref.clone()

    let lines = response_str.split_by("\r\n")

    try
      // Parse status line: "HTTP/1.1 101 Switching Protocols"
      let status_line = lines(0)?
      let parts = status_line.split(" ")
      if parts.size() < 2 then return ClientHandshakeInvalidHTTP end
      if parts(0)? != "HTTP/1.1" then return ClientHandshakeInvalidHTTP end
      let status =
        try
          parts(1)?.u16()?
        else
          return ClientHandshakeInvalidHTTP
        end

      // A non-101 status is reported before the headers are validated:
      // there is no upgrade to check, and the status is the useful part.
      if status != 101 then
        return ClientHandshakeUnexpectedStatus(status)
      end

      // Parse headers
      let headers = recover val
        let h = Array[(String val, String val)]
        var j: USize = 1
        while j < lines.size() do
          let line = lines(j)?
          let colon = try line.find(":")? else j = j + 1; continue end
          // UpgradeResponse.header() depends on names being pre-lowered here.
          let name: String val = line.substring(0, colon).lower()
          let value: String val = line.substring(colon + 1).>strip()
          h.push((name, value))
          j = j + 1
        end
        h
      end

      var has_upgrade = false
      var has_connection_upgrade = false
      var has_extensions = false
      var accept: (String val | None) = None
      var subprotocol: (String val | None) = None

      for (name, value) in headers.values() do
        if name == "upgrade" then
          if value.lower() == "websocket" then
            has_upgrade = true
          end
        elseif name == "connection" then
          // Connection header may contain multiple comma-separated tokens
          let tokens: Array[String val] val = value.split(",")
          for token in tokens.values() do
            let trimmed: String val = token.clone().>strip()
            if trimmed.lower() == "upgrade" then
              has_connection_upgrade = true
            end
          end
        elseif name == "sec-websocket-accept" then
          accept = value
        elseif name == "sec-websocket-protocol" then
          subprotocol = value
        elseif name == "sec-websocket-extensions" then
          if value.size() > 0 then
            has_extensions = true
          end
        end
      end

      if not (has_upgrade and has_connection_upgrade) then
        return ClientHandshakeMissingUpgrade
      end

      // Mare offers no extensions, so any value here is unsolicited and
      // would commit us to a framing the parser does not implement.
      if has_extensions then
        return ClientHandshakeUnsolicitedExtension
      end

      match \exhaustive\ subprotocol
      | let s: String val =>
        if not _offered(s) then
          return ClientHandshakeUnsolicitedSubprotocol
        end
      | None => None
      end

      match \exhaustive\ accept
      | let a: String val =>
        let expected =
          try
            _AcceptKey(_key)?
          else
            return ClientHandshakeAcceptKeyFailed
          end
        if a != expected then
          return ClientHandshakeAcceptMismatch
        end
      | None => return ClientHandshakeMissingAccept
      end

      // Extract remaining bytes after \r\n\r\n using String intermediary:
      // build ref String, clone to iso, iso_array to val. A server may
      // send frames immediately after the response, in the same segment.
      let remaining_start = header_end + 4
      let remaining_s = String(_buf.size() - remaining_start)
      var k: USize = remaining_start
      while k < _buf.size() do
        try remaining_s.push(_buf(k)?) else _Unreachable() end
        k = k + 1
      end
      let remaining: Array[U8] val = remaining_s.clone().iso_array()

      _ClientHandshakeResult(UpgradeResponse(status, headers), remaining)
    else
      ClientHandshakeInvalidHTTP
    end

  fun _offered(subprotocol: String val): Bool =>
    """
    Whether the given subprotocol was among those offered.

    A server that selects anything else — including selecting one when
    none were offered — fails the handshake, because it has committed to a
    protocol this client never claimed to speak.
    """
    for p in _config.subprotocols.values() do
      if p == subprotocol then
        return true
      end
    end
    false

class val _ClientHandshakeResult
  """A successfully validated WebSocket upgrade response."""
  let response: UpgradeResponse val
  let remaining: Array[U8] val

  new val create(
    response': UpgradeResponse val,
    remaining': Array[U8] val)
  =>
    response = response'
    remaining = remaining'

primitive _ClientHandshakeNeedMore
  """More data is needed to complete the HTTP upgrade response."""
