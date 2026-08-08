primitive _FrameEncoder
  """
  Builds outgoing WebSocket frames (server-to-client, never masked).

  All methods return a complete frame as a `val` byte array ready to
  send over TCP.
  """

  fun text(data: String val): Array[U8] val =>
    """
    Encode a text message frame (FIN=1, opcode=0x1).
    """
    _encode(true, 0x01, data)

  fun binary(data: Array[U8] val): Array[U8] val =>
    """
    Encode a binary message frame (FIN=1, opcode=0x2).
    """
    _encode(true, 0x02, data)

  fun close(code: CloseCode, reason: String val = ""): Array[U8] val =>
    """
    Encode a close frame with a status code and optional reason.
    """
    let code_val = code.code()
    let payload =
      recover iso
        let p = Array[U8](2 + reason.size())
        p .> push((code_val >> 8).u8())
          .> push((code_val and 0xFF).u8())
        p.append(reason)
        p
      end
    _encode(true, 0x08, consume payload)

  fun close_payload(payload: Array[U8] val): Array[U8] val =>
    """
    Encode a close frame echoing back the client's raw close payload.
    """
    _encode(true, 0x08, payload)

  fun close_empty(): Array[U8] val =>
    """
    Encode a close frame with no payload.
    """
    _encode(true, 0x08, recover val Array[U8] end)

  fun pong(data: Array[U8] val): Array[U8] val =>
    """
    Encode a pong frame echoing the ping payload.
    """
    _encode(true, 0x0A, data)

  fun _encode(fin: Bool, opcode: U8, payload: ByteSeq): Array[U8] val =>
    """
    Build a complete frame with the given FIN bit, opcode, and payload.

    Server-to-client frames are never masked (RFC 6455 Section 5.1).
    Payload length uses the appropriate encoding: 7-bit for 0..125,
    16-bit for 126..65535, 64-bit for larger.
    """
    let payload_size = payload.size()
    let header_size: USize =
      if payload_size <= 125 then 2
      elseif payload_size <= 65535 then 4
      else 10
      end

    recover val
      let frame = Array[U8](header_size + payload_size)

      // First byte: FIN + opcode
      let first: U8 = if fin then 0x80 or opcode else opcode end
      frame.push(first)

      // Second byte: MASK=0 + payload length
      if payload_size <= 125 then
        frame.push(payload_size.u8())
      elseif payload_size <= 65535 then
        frame.push(126)
        frame .> push((payload_size >> 8).u8())
          .push((payload_size and 0xFF).u8())
      else
        frame.push(127)
        frame .> push((payload_size >> 56).u8())
          .> push(((payload_size >> 48) and 0xFF).u8())
          .> push(((payload_size >> 40) and 0xFF).u8())
          .> push(((payload_size >> 32) and 0xFF).u8())
          .> push(((payload_size >> 24) and 0xFF).u8())
          .> push(((payload_size >> 16) and 0xFF).u8())
          .> push(((payload_size >> 8) and 0xFF).u8())
          .push((payload_size and 0xFF).u8())
      end

      frame.append(payload)
      frame
    end
