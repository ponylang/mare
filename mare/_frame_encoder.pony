primitive _FrameEncoder
  """
  Builds outgoing WebSocket frames.

  Every method takes an optional `mask_key`. Server-to-client frames are
  never masked (RFC 6455 Section 5.1), so the server omits it. Client-to-
  server frames must be masked with a fresh 32-bit key (RFC 6455 Section
  5.3), so the client supplies one.

  The key arrives as a parameter rather than being generated here. Masking
  a given payload with a given key has exactly one right answer, so keeping
  this primitive pure is what makes the RFC's worked example usable as a
  test vector.

  All methods return a complete frame as a `val` byte array ready to
  send over TCP.
  """

  fun text(data: String val, mask_key: (U32 | None) = None): Array[U8] val =>
    """Encode a text message frame (FIN=1, opcode=0x1)."""
    _encode(true, 0x01, data, mask_key)

  fun binary(
    data: Array[U8] val,
    mask_key: (U32 | None) = None)
    : Array[U8] val
  =>
    """Encode a binary message frame (FIN=1, opcode=0x2)."""
    _encode(true, 0x02, data, mask_key)

  fun close(
    code: CloseCode,
    reason: String val = "",
    mask_key: (U32 | None) = None)
    : Array[U8] val
  =>
    """Encode a close frame with a status code and optional reason."""
    let code_val = code.code()
    let payload = recover iso
      let p = Array[U8](2 + reason.size())
      p.>push((code_val >> 8).u8())
        .>push((code_val and 0xFF).u8())
      p.append(reason)
      p
    end
    _encode(true, 0x08, consume payload, mask_key)

  fun close_payload(
    payload: Array[U8] val,
    mask_key: (U32 | None) = None)
    : Array[U8] val
  =>
    """Encode a close frame echoing back the peer's raw close payload."""
    _encode(true, 0x08, payload, mask_key)

  fun close_empty(mask_key: (U32 | None) = None): Array[U8] val =>
    """Encode a close frame with no payload."""
    _encode(true, 0x08, recover val Array[U8] end, mask_key)

  fun ping(
    data: Array[U8] val,
    mask_key: (U32 | None) = None)
    : Array[U8] val
  =>
    """
    Encode a ping frame (FIN=1, opcode=0x9).

    The caller is responsible for keeping `data` within the 125 byte
    control frame limit (RFC 6455 Section 5.5); this encoder will happily
    build a longer frame that the peer must then reject.
    """
    _encode(true, 0x09, data, mask_key)

  fun pong(
    data: Array[U8] val,
    mask_key: (U32 | None) = None)
    : Array[U8] val
  =>
    """Encode a pong frame echoing the ping payload."""
    _encode(true, 0x0A, data, mask_key)

  fun _encode(
    fin: Bool,
    opcode: U8,
    payload: ByteSeq,
    mask_key: (U32 | None))
    : Array[U8] val
  =>
    """
    Build a complete frame with the given FIN bit, opcode, and payload.

    Payload length uses the appropriate encoding: 7-bit for 0..125,
    16-bit for 126..65535, 64-bit for larger. When `mask_key` is present
    the MASK bit is set, the key follows the length big-endian, and the
    payload is XORed with it.
    """
    let payload_size = payload.size()
    let length_size: USize =
      if payload_size <= 125 then 0
      elseif payload_size <= 65535 then 2
      else 8
      end
    (let mask_size: USize, let mask_bit: U8) =
      match mask_key
      | let _: U32 => (USize(4), U8(0x80))
      | None => (USize(0), U8(0))
      end

    recover val
      let frame = Array[U8](2 + length_size + mask_size + payload_size)

      // First byte: FIN + opcode
      let first: U8 = if fin then 0x80 or opcode else opcode end
      frame.push(first)

      // Second byte: MASK bit + payload length
      if payload_size <= 125 then
        frame.push(mask_bit or payload_size.u8())
      elseif payload_size <= 65535 then
        frame
          .>push(mask_bit or 126)
          .>push((payload_size >> 8).u8())
          .>push((payload_size and 0xFF).u8())
      else
        frame
          .>push(mask_bit or 127)
          .>push((payload_size >> 56).u8())
          .>push(((payload_size >> 48) and 0xFF).u8())
          .>push(((payload_size >> 40) and 0xFF).u8())
          .>push(((payload_size >> 32) and 0xFF).u8())
          .>push(((payload_size >> 24) and 0xFF).u8())
          .>push(((payload_size >> 16) and 0xFF).u8())
          .>push(((payload_size >> 8) and 0xFF).u8())
          .>push((payload_size and 0xFF).u8())
      end

      match mask_key
      | let key: U32 =>
        frame
          .>push((key >> 24).u8())
          .>push(((key >> 16) and 0xFF).u8())
          .>push(((key >> 8) and 0xFF).u8())
          .>push((key and 0xFF).u8())

        // Append the plaintext, then XOR it in place. Every index used
        // below is inside the region just appended, so the else branch
        // cannot be reached.
        let payload_start = frame.size()
        frame.append(payload)
        try
          var i: USize = 0
          while i < payload_size do
            let at = payload_start + i
            let shift = (24 - (8 * (i % 4))).u32()
            frame.update(at, frame(at)? xor (key >> shift).u8())?
            i = i + 1
          end
        else
          _Unreachable()
        end
      | None =>
        frame.append(payload)
      end

      frame
    end
