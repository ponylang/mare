class _FrameParser
  """
  Incremental WebSocket frame parser.

  Accumulates incoming bytes and parses complete frames, validates frame
  structure per RFC 6455, and returns unmasked payloads.

  Masking is directional and mandatory in both directions: a server must
  receive only masked frames and a client must receive only unmasked ones
  (RFC 6455 Sections 5.1 and 5.2). `expect_masked` selects which. A frame
  that disagrees is a protocol error rather than something to tolerate —
  an unmasked frame arriving at a server is the proxy-smuggling case
  masking exists to prevent.
  """
  let _expect_masked: Bool
  var _buf: Array[U8] ref = Array[U8]

  new create(expect_masked: Bool = true) =>
    """
    Create a parser for one direction.

    Servers keep the default; clients pass `false`.
    """
    _expect_masked = expect_masked

  fun ref parse(data: Array[U8] val)
    : (Array[_ParsedFrame val] val | _FrameError)
  =>
    """
    Feed data and parse all complete frames.

    Returns an array of parsed frames, or a `_FrameError` for the first
    protocol violation encountered.
    """
    _buf.append(data)

    let frames = recover iso Array[_ParsedFrame val] end

    while _buf.size() > 0 do
      match \exhaustive\ _try_parse_frame()
      | let frame: _ParsedFrame val =>
        frames.push(frame)
      | let err: _FrameError =>
        return err
      | None =>
        break
      end
    end

    consume frames

  fun ref _try_parse_frame(): (_ParsedFrame val | _FrameError | None) =>
    """Attempt to parse a single frame from the buffer."""
    if _buf.size() < 2 then return None end

    try
      let b0 = _buf(0)?
      let b1 = _buf(1)?

      let fin = (b0 and 0x80) != 0
      let rsv = (b0 and 0x70)
      let opcode = b0 and 0x0F
      let masked = (b1 and 0x80) != 0
      var payload_len: USize = (b1 and 0x7F).usize()

      // Validate RSV bits
      if rsv != 0 then
        return _FrameError(CloseProtocolError)
      end

      // Validate opcode
      if not _valid_opcode(opcode) then
        return _FrameError(CloseProtocolError)
      end

      // Masking is required in one direction and forbidden in the other
      if masked != _expect_masked then
        return _FrameError(CloseProtocolError)
      end

      // Control frame validation
      let is_control = (opcode >= 0x08)
      if is_control then
        if not fin then
          return _FrameError(CloseProtocolError)
        end
        if payload_len > 125 then
          return _FrameError(CloseProtocolError)
        end
      end

      // Determine header size and extended payload length
      var header_size: USize = 2
      if payload_len == 126 then
        header_size = 4
        if _buf.size() < header_size then return None end
        payload_len =
          (_buf(2)?.usize() << 8) or _buf(3)?.usize()
      elseif payload_len == 127 then
        header_size = 10
        if _buf.size() < header_size then return None end
        // RFC 6455 Section 5.2: MSB of 64-bit payload length must be 0
        if (_buf(2)? and 0x80) != 0 then
          return _FrameError(CloseProtocolError)
        end
        payload_len =
          (_buf(2)?.usize() << 56) or
          (_buf(3)?.usize() << 48) or
          (_buf(4)?.usize() << 40) or
          (_buf(5)?.usize() << 32) or
          (_buf(6)?.usize() << 24) or
          (_buf(7)?.usize() << 16) or
          (_buf(8)?.usize() << 8) or
          _buf(9)?.usize()
      end

      // Mask key (4 bytes, present only when the frame is masked)
      let total_header = if masked then header_size + 4 else header_size end
      if _buf.size() < total_header then return None end

      // An unmasked frame unmasks against a zero key, which is the
      // identity, so the payload loop below needs no second form.
      let mask_key: U32 =
        if masked then
          (_buf(header_size)?.u32() << 24) or
            (_buf(header_size + 1)?.u32() << 16) or
            (_buf(header_size + 2)?.u32() << 8) or
            _buf(header_size + 3)?.u32()
        else
          0
        end

      // Check if we have the full payload
      let frame_size = total_header + payload_len
      if _buf.size() < frame_size then return None end

      // Extract and unmask payload. Build ref String from bytes, then
      // clone().iso_array() to get Array[U8] val without a recover
      // block that accesses _buf.
      let payload_s = String(payload_len)
      var i: USize = 0
      while i < payload_len do
        let shift = (24 - (8 * (i % 4))).u32()
        payload_s.push(_buf(total_header + i)? xor (mask_key >> shift).u8())
        i = i + 1
      end
      let payload: Array[U8] val = payload_s.clone().iso_array()

      // Validate close frame payload
      if opcode == 0x08 then
        // Coupling: _CloseStatusExtractor.from_payload assumes close payloads
        // are either empty or >= 2 bytes. Removing this check would cause the
        // extractor to mishandle 1-byte payloads.
        if payload.size() == 1 then
          return _FrameError(CloseProtocolError)
        end
        // Validate close status code per RFC 6455 Section 7.4.1
        if payload.size() >= 2 then
          let code = (payload(0)?.u16() << 8) or payload(1)?.u16()
          if not _valid_close_code(code) then
            return _FrameError(CloseProtocolError)
          end
        end
        // Validate close reason is valid UTF-8
        if payload.size() > 2 then
          let reason_s = String(payload.size() - 2)
          var ri: USize = 2
          while ri < payload.size() do
            reason_s.push(payload(ri)?)
            ri = ri + 1
          end
          let reason_bytes: Array[U8] val = reason_s.clone().iso_array()
          if not _Utf8Validator.is_valid(reason_bytes) then
            return _FrameError(CloseProtocolError)
          end
        end
      end

      // Compact buffer: remove consumed bytes
      let new_buf = Array[U8](_buf.size() - frame_size)
      var j: USize = frame_size
      while j < _buf.size() do
        new_buf.push(_buf(j)?)
        j = j + 1
      end
      _buf = new_buf

      _ParsedFrame(fin, opcode, payload)
    else
      _Unreachable()
      _FrameError(CloseInternalError)
    end

  fun _valid_opcode(opcode: U8): Bool =>
    """Check if the opcode is a known WebSocket opcode."""
    match opcode
    | 0x00 => true // Continuation
    | 0x01 => true // Text
    | 0x02 => true // Binary
    | 0x08 => true // Close
    | 0x09 => true // Ping
    | 0x0A => true // Pong
    else false
    end

  fun _valid_close_code(code: U16): Bool =>
    """Check if a close status code is valid to receive per RFC 6455."""
    // Coupling: _CloseStatusExtractor._code_to_status must stay in sync with
    // these valid code ranges. Adding new ranges here means adding
    // corresponding match arms in the extractor.
    if (code >= 1000) and (code <= 1003) then true
    elseif (code >= 1007) and (code <= 1014) then true
    elseif (code >= 3000) and (code <= 4999) then true
    else false
    end

class val _ParsedFrame
  """A parsed and unmasked WebSocket frame."""
  let fin: Bool
  let opcode: U8
  let payload: Array[U8] val

  new val create(fin': Bool, opcode': U8, payload': Array[U8] val) =>
    fin = fin'
    opcode = opcode'
    payload = payload'

class val _FrameError
  """A protocol violation detected during frame parsing."""
  let code: CloseCode

  new val create(code': CloseCode) =>
    code = code'
