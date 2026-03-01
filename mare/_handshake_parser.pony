use crypto = "ssl/crypto"
use "encode/base64"

class _HandshakeParser
  """
  Buffers and parses an HTTP upgrade request for the WebSocket handshake.

  Accumulates incoming data until the full HTTP request is received
  (delimited by `\r\n\r\n`). Validates WebSocket-specific headers and
  computes the Sec-WebSocket-Accept key per RFC 6455 Section 4.2.2.
  """
  var _buf: Array[U8] ref = Array[U8]

  fun ref apply(
    data: Array[U8] iso,
    max_size: USize)
    : (_HandshakeResult | _HandshakeNeedMore | HandshakeError)
  =>
    """
    Feed incoming data into the buffer and attempt to parse.

    Returns `_HandshakeNeedMore` if the full HTTP request hasn't arrived
    yet, a `_HandshakeResult` on success, or a `HandshakeError` on
    failure.
    """
    _buf.append(consume data)

    if _buf.size() > max_size then
      return HandshakeRequestTooLarge
    end

    match \exhaustive\ _find_header_end()
    | None => _HandshakeNeedMore
    | let pos: USize => _parse_request(pos)
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

  fun _parse_request(header_end: USize)
    : (_HandshakeResult | HandshakeError)
  =>
    """Parse the buffered HTTP request up to header_end."""
    // Build request string from buffer bytes. String.clone() gives iso^
    // which auto-converts to val.
    let request_ref = String(header_end)
    var i: USize = 0
    while i < header_end do
      try request_ref.push(_buf(i)?) else _Unreachable() end
      i = i + 1
    end
    let request_str: String val = request_ref.clone()

    // Split into lines
    let lines = request_str.split_by("\r\n")

    // Parse request line
    try
      let request_line = lines(0)?
      let parts = request_line.split(" ")
      if parts.size() < 3 then return HandshakeInvalidHTTP end
      let method = parts(0)?
      let uri = parts(1)?
      let version = parts(2)?
      if method != "GET" then return HandshakeInvalidHTTP end
      if version != "HTTP/1.1" then return HandshakeInvalidHTTP end

      // Parse headers
      let headers = recover val
        let h = Array[(String val, String val)]
        var j: USize = 1
        while j < lines.size() do
          let line = lines(j)?
          let colon = try line.find(":")? else j = j + 1; continue end
          // UpgradeRequest.header() depends on names being pre-lowered here.
          let name: String val = line.substring(0, colon).lower()
          let value: String val = line.substring(colon + 1).>strip()
          h.push((name, value))
          j = j + 1
        end
        h
      end

      // Validate required WebSocket headers
      var has_host = false
      var has_upgrade = false
      var has_connection_upgrade = false
      var websocket_key: (String val | None) = None
      var websocket_version: (String val | None) = None

      for (name, value) in headers.values() do
        if name == "host" then
          has_host = true
        elseif name == "upgrade" then
          let value_lower: String val = value.lower()
          if value_lower == "websocket" then
            has_upgrade = true
          end
        elseif name == "connection" then
          // Connection header may contain multiple comma-separated tokens
          let tokens: Array[String val] val = value.split(",")
          for token in tokens.values() do
            let trimmed: String val = token.clone().>strip()
            let trimmed_lower: String val = trimmed.lower()
            if trimmed_lower == "upgrade" then
              has_connection_upgrade = true
            end
          end
        elseif name == "sec-websocket-version" then
          websocket_version = value
        elseif name == "sec-websocket-key" then
          websocket_key = value
        end
      end

      if not has_host then return HandshakeMissingHost end
      if not has_upgrade then return HandshakeMissingUpgrade end
      if not has_connection_upgrade then return HandshakeMissingUpgrade end

      match \exhaustive\ websocket_version
      | let v: String val =>
        if v != "13" then return HandshakeWrongVersion end
      | None => return HandshakeWrongVersion
      end

      match \exhaustive\ websocket_key
      | let key: String val =>
        let decoded_size =
          try
            Base64.decode[Array[U8] iso](key)?.size()
          else
            return HandshakeInvalidKey
          end
        if decoded_size != 16 then return HandshakeInvalidKey end
        let accept_key = _compute_accept_key(key)

        // Extract remaining bytes after \r\n\r\n using String
        // intermediary: build ref String, clone to iso, iso_array to val
        let remaining_start = header_end + 4
        let remaining_s = String(_buf.size() - remaining_start)
        var k: USize = remaining_start
        while k < _buf.size() do
          try remaining_s.push(_buf(k)?) else _Unreachable() end
          k = k + 1
        end
        let remaining: Array[U8] val = remaining_s.clone().iso_array()

        let request = UpgradeRequest(uri, headers)
        _HandshakeResult(request, accept_key, remaining)
      | None => HandshakeMissingKey
      end
    else
      HandshakeInvalidHTTP
    end

  fun _compute_accept_key(key: String val): String val =>
    """
    Compute the Sec-WebSocket-Accept value.

    Concatenates the client key with the WebSocket GUID, takes the SHA-1
    hash, and Base64-encodes the result.
    """
    let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    let sha = crypto.Digest.sha1()
    try
      sha.>append(key)?.append(magic)?
    else
      _Unreachable()
    end
    let hash = sha.final()
    let encoded: String val = Base64.encode(hash)
    encoded

class val _HandshakeResult
  """A successfully parsed WebSocket upgrade request."""
  let request: UpgradeRequest val
  let accept_key: String val
  let remaining: Array[U8] val

  new val create(
    request': UpgradeRequest val,
    accept_key': String val,
    remaining': Array[U8] val)
  =>
    request = request'
    accept_key = accept_key'
    remaining = remaining'

primitive _HandshakeNeedMore
  """More data is needed to complete the HTTP upgrade request."""
