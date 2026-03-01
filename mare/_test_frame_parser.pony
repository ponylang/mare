use "pony_test"
use "pony_check"

primitive \nodoc\ _TestFrameHelper
  """Helpers for building masked WebSocket frames for parser testing."""

  fun masked_frame(
    fin: Bool,
    opcode: U8,
    payload: Array[U8] val,
    mask_key: Array[U8] val = recover val [as U8: 0x37; 0xFA; 0x21; 0x3D] end)
    : Array[U8] val
  =>
    """Build a masked client frame from components."""
    let payload_size = payload.size()

    recover val
      let frame = Array[U8]
      // First byte
      let first: U8 = if fin then 0x80 or opcode else opcode end
      frame.push(first)

      // Second byte: MASK=1 + length
      if payload_size <= 125 then
        frame.push(0x80 or payload_size.u8())
      elseif payload_size <= 65535 then
        frame.push(0x80 or 126)
        frame.>push((payload_size >> 8).u8())
          .push((payload_size and 0xFF).u8())
      else
        frame.push(0x80 or 127)
        frame.>push((payload_size >> 56).u8())
          .>push(((payload_size >> 48) and 0xFF).u8())
          .>push(((payload_size >> 40) and 0xFF).u8())
          .>push(((payload_size >> 32) and 0xFF).u8())
          .>push(((payload_size >> 24) and 0xFF).u8())
          .>push(((payload_size >> 16) and 0xFF).u8())
          .>push(((payload_size >> 8) and 0xFF).u8())
          .push((payload_size and 0xFF).u8())
      end

      // Mask key
      try
        frame.>push(mask_key(0)?)
          .>push(mask_key(1)?)
          .>push(mask_key(2)?)
          .push(mask_key(3)?)

        // Masked payload
        var i: USize = 0
        while i < payload_size do
          frame.push(payload(i)? xor mask_key(i % 4)?)
          i = i + 1
        end
      else
        _Unreachable()
      end
      frame
    end

  fun unmasked_frame(
    fin: Bool,
    opcode: U8,
    payload: Array[U8] val)
    : Array[U8] val
  =>
    """Build an unmasked frame (for testing rejection)."""
    let payload_size = payload.size()

    recover val
      let frame = Array[U8]
      let first: U8 = if fin then 0x80 or opcode else opcode end
      frame.push(first)

      if payload_size <= 125 then
        frame.push(payload_size.u8())
      elseif payload_size <= 65535 then
        frame.push(126)
        frame.>push((payload_size >> 8).u8())
          .push((payload_size and 0xFF).u8())
      else
        frame.push(127)
        frame.>push((payload_size >> 56).u8())
          .>push(((payload_size >> 48) and 0xFF).u8())
          .>push(((payload_size >> 40) and 0xFF).u8())
          .>push(((payload_size >> 32) and 0xFF).u8())
          .>push(((payload_size >> 24) and 0xFF).u8())
          .>push(((payload_size >> 16) and 0xFF).u8())
          .>push(((payload_size >> 8) and 0xFF).u8())
          .push((payload_size and 0xFF).u8())
      end

      frame.append(payload)
      frame
    end

class \nodoc\ iso _TestFrameParserText is UnitTest
  """Single masked text frame is parsed correctly."""
  fun name(): String => "frame_parser/text"

  fun apply(h: TestHelper) ? =>
    let frame = _TestFrameHelper.masked_frame(
      true, 0x01, "Hello".array())
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_true(frames(0)?.fin)
      h.assert_eq[U8](0x01, frames(0)?.opcode)
      h.assert_eq[USize](5, frames(0)?.payload.size())
      h.assert_eq[U8]('H', frames(0)?.payload(0)?)
    | let err: _FrameError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestFrameParserBinary is UnitTest
  """Single masked binary frame is parsed correctly."""
  fun name(): String => "frame_parser/binary"

  fun apply(h: TestHelper) ? =>
    let payload: Array[U8] val = recover val [as U8: 0x01; 0x02; 0x03] end
    let frame = _TestFrameHelper.masked_frame(true, 0x02, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[U8](0x02, frames(0)?.opcode)
      h.assert_eq[U8](0x01, frames(0)?.payload(0)?)
      h.assert_eq[U8](0x02, frames(0)?.payload(1)?)
      h.assert_eq[U8](0x03, frames(0)?.payload(2)?)
    | let err: _FrameError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestFrameParserPing is UnitTest
  """Ping frame with payload ≤ 125 bytes."""
  fun name(): String => "frame_parser/ping"

  fun apply(h: TestHelper) ? =>
    let payload: Array[U8] val = recover val [as U8: 0xAA; 0xBB] end
    let frame = _TestFrameHelper.masked_frame(true, 0x09, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[U8](0x09, frames(0)?.opcode)
      h.assert_eq[USize](2, frames(0)?.payload.size())
    | let err: _FrameError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestFrameParserPong is UnitTest
  """Pong frame."""
  fun name(): String => "frame_parser/pong"

  fun apply(h: TestHelper) ? =>
    let frame = _TestFrameHelper.masked_frame(
      true, 0x0A, recover val Array[U8] end)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[U8](0x0A, frames(0)?.opcode)
    | let err: _FrameError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestFrameParserCloseWithCode is UnitTest
  """Close frame with status code and reason."""
  fun name(): String => "frame_parser/close_with_code"

  fun apply(h: TestHelper) ? =>
    // Close frame payload: 2-byte status (1000) + "bye"
    let payload: Array[U8] val =
      recover val [as U8: 0x03; 0xE8; 'b'; 'y'; 'e'] end
    let frame = _TestFrameHelper.masked_frame(true, 0x08, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[U8](0x08, frames(0)?.opcode)
      h.assert_eq[USize](5, frames(0)?.payload.size())
      // Status code 1000 big-endian
      h.assert_eq[U8](0x03, frames(0)?.payload(0)?)
      h.assert_eq[U8](0xE8, frames(0)?.payload(1)?)
    | let err: _FrameError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestFrameParserCloseEmpty is UnitTest
  """Close frame with no payload is valid."""
  fun name(): String => "frame_parser/close_empty"

  fun apply(h: TestHelper) ? =>
    let frame = _TestFrameHelper.masked_frame(
      true, 0x08, recover val Array[U8] end)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[U8](0x08, frames(0)?.opcode)
      h.assert_eq[USize](0, frames(0)?.payload.size())
    | let err: _FrameError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestFrameParserCloseOneByte is UnitTest
  """Close frame with 1-byte payload is a protocol error."""
  fun name(): String => "frame_parser/close_one_byte"

  fun apply(h: TestHelper) =>
    let payload: Array[U8] val = recover val [as U8: 0x03] end
    let frame = _TestFrameHelper.masked_frame(true, 0x08, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.fail("expected error for 1-byte close payload")
    | let err: _FrameError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    end

class \nodoc\ iso _TestFrameParserCloseInvalidUtf8Reason is UnitTest
  """Close frame with invalid UTF-8 in reason is a protocol error."""
  fun name(): String => "frame_parser/close_invalid_utf8_reason"

  fun apply(h: TestHelper) =>
    // Status 1000 + invalid UTF-8 (0xFF)
    let payload: Array[U8] val =
      recover val [as U8: 0x03; 0xE8; 0xFF] end
    let frame = _TestFrameHelper.masked_frame(true, 0x08, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.fail("expected error for invalid UTF-8 in close reason")
    | let err: _FrameError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    end

class \nodoc\ iso _TestFrameParserCloseValidUtf8Reason is UnitTest
  """Close frame with valid UTF-8 in reason is accepted."""
  fun name(): String => "frame_parser/close_valid_utf8_reason"

  fun apply(h: TestHelper) ? =>
    // Status 1000 + valid UTF-8 "OK"
    let payload: Array[U8] val =
      recover val [as U8: 0x03; 0xE8; 'O'; 'K'] end
    let frame = _TestFrameHelper.masked_frame(true, 0x08, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[U8](0x08, frames(0)?.opcode)
    | let err: _FrameError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestFrameParserLength16Bit is UnitTest
  """16-bit extended payload length (126-65535 bytes)."""
  fun name(): String => "frame_parser/length_16bit"

  fun apply(h: TestHelper) ? =>
    let payload: Array[U8] val = recover val
      let a = Array[U8](200)
      var i: USize = 0
      while i < 200 do a.push(0x41); i = i + 1 end
      a
    end
    let frame = _TestFrameHelper.masked_frame(true, 0x02, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[USize](200, frames(0)?.payload.size())
    | let err: _FrameError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestFrameParserLength64Bit is UnitTest
  """64-bit extended payload length (> 65535 bytes)."""
  fun name(): String => "frame_parser/length_64bit"

  fun apply(h: TestHelper) ? =>
    let size: USize = 65536
    let payload: Array[U8] val = recover val
      let a = Array[U8](size)
      var i: USize = 0
      while i < size do a.push(0x42); i = i + 1 end
      a
    end
    let frame = _TestFrameHelper.masked_frame(true, 0x02, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[USize](size, frames(0)?.payload.size())
    | let err: _FrameError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestFrameParserLength64BitMsbSet is UnitTest
  """64-bit payload length with MSB set is rejected per RFC 6455."""
  fun name(): String => "frame_parser/length_64bit_msb_set"

  fun apply(h: TestHelper) =>
    // Manually build a masked frame with 64-bit length whose MSB is set.
    // The 8-byte extended length is [0x80 0x00 0x00 0x00 0x00 0x01 0x00 0x00],
    // which has bit 63 set. This must be rejected before attempting to read
    // that many payload bytes.
    let raw: Array[U8] val = recover val
      let f = Array[U8]
      f.push(0x80 or 0x02) // FIN + binary
      f.push(0x80 or 127)  // MASK + 64-bit length indicator
      // 8-byte extended length with MSB set
      f.>push(0x80).>push(0x00).>push(0x00).>push(0x00)
        .>push(0x00).>push(0x01).>push(0x00).push(0x00)
      // Mask key
      f.>push(0x00).>push(0x00).>push(0x00).push(0x00)
      f
    end
    let parser = _FrameParser
    match \exhaustive\ parser.parse(raw)
    | let frames: Array[_ParsedFrame val] val =>
      h.fail("expected error for 64-bit length with MSB set")
    | let err: _FrameError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    end

class \nodoc\ iso _TestFrameParserUnmasked is UnitTest
  """Unmasked client frame is rejected."""
  fun name(): String => "frame_parser/unmasked_rejected"

  fun apply(h: TestHelper) =>
    let frame = _TestFrameHelper.unmasked_frame(
      true, 0x01, "Hello".array())
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.fail("expected error for unmasked frame")
    | let err: _FrameError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    end

class \nodoc\ iso _TestFrameParserNonZeroRsv is UnitTest
  """Non-zero RSV bits are rejected."""
  fun name(): String => "frame_parser/non_zero_rsv"

  fun apply(h: TestHelper) =>
    // Build frame with RSV1 set (0x40)
    let raw = recover val
      let f = Array[U8]
      f.push(0x80 or 0x40 or 0x01) // FIN + RSV1 + text
      f.push(0x80 or 0x00) // MASK + 0 length
      f.>push(0x00).>push(0x00).>push(0x00).push(0x00) // mask key
      f
    end
    let parser = _FrameParser
    match \exhaustive\ parser.parse(raw)
    | let frames: Array[_ParsedFrame val] val =>
      h.fail("expected error for RSV bits")
    | let err: _FrameError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    end

class \nodoc\ iso _TestFrameParserFragmentedControl is UnitTest
  """Fragmented control frame (FIN=0) is rejected."""
  fun name(): String => "frame_parser/fragmented_control"

  fun apply(h: TestHelper) =>
    let frame = _TestFrameHelper.masked_frame(
      false, 0x09, recover val Array[U8] end)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.fail("expected error for fragmented control frame")
    | let err: _FrameError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    end

class \nodoc\ iso _TestFrameParserControlTooLarge is UnitTest
  """Control frame with payload > 125 bytes is rejected."""
  fun name(): String => "frame_parser/control_too_large"

  fun apply(h: TestHelper) =>
    let payload: Array[U8] val = recover val
      let a = Array[U8](126)
      var i: USize = 0
      while i < 126 do a.push(0x00); i = i + 1 end
      a
    end
    let frame = _TestFrameHelper.masked_frame(true, 0x09, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.fail("expected error for oversized control frame")
    | let err: _FrameError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    end

class \nodoc\ iso _TestFrameParserUnknownOpcode is UnitTest
  """Unknown opcode is rejected."""
  fun name(): String => "frame_parser/unknown_opcode"

  fun apply(h: TestHelper) =>
    let frame = _TestFrameHelper.masked_frame(
      true, 0x03, recover val Array[U8] end)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.fail("expected error for unknown opcode")
    | let err: _FrameError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    end

class \nodoc\ iso _TestFrameParserIncremental is UnitTest
  """Byte-by-byte delivery assembles correct frame."""
  fun name(): String => "frame_parser/incremental"

  fun apply(h: TestHelper) ? =>
    let full_frame = _TestFrameHelper.masked_frame(
      true, 0x01, "Hi".array())
    let parser = _FrameParser

    // Feed one byte at a time
    var i: USize = 0
    while i < (full_frame.size() - 1) do
      let byte: Array[U8] val = recover val [as U8: full_frame(i)?] end
      match \exhaustive\ parser.parse(byte)
      | let frames: Array[_ParsedFrame val] val =>
        h.assert_eq[USize](0, frames.size())
      | let err: _FrameError => h.fail("unexpected error at byte " +
          i.string())
      end
      i = i + 1
    end

    // Feed last byte — should complete the frame
    let last: Array[U8] val = recover val [as U8: full_frame(i)?] end
    match \exhaustive\ parser.parse(last)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[U8](0x01, frames(0)?.opcode)
      h.assert_eq[U8]('H', frames(0)?.payload(0)?)
      h.assert_eq[U8]('i', frames(0)?.payload(1)?)
    | let err: _FrameError => h.fail("unexpected error on last byte")
    end

class \nodoc\ iso _TestFrameParserMultipleFrames is UnitTest
  """Multiple frames in one buffer are all parsed."""
  fun name(): String => "frame_parser/multiple_frames"

  fun apply(h: TestHelper) ? =>
    let frame1 = _TestFrameHelper.masked_frame(
      true, 0x01, "Hi".array())
    let frame2 = _TestFrameHelper.masked_frame(
      true, 0x02, recover val [as U8: 0x01] end)

    // Concatenate both frames
    let combined: Array[U8] val = recover val
      let c = Array[U8](frame1.size() + frame2.size())
      for b in frame1.values() do c.push(b) end
      for b in frame2.values() do c.push(b) end
      c
    end

    let parser = _FrameParser
    match \exhaustive\ parser.parse(combined)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](2, frames.size())
      h.assert_eq[U8](0x01, frames(0)?.opcode)
      h.assert_eq[U8](0x02, frames(1)?.opcode)
    | let err: _FrameError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestFrameParserCloseValidCodes is Property1[U16]
  """Valid close status codes are accepted by the frame parser."""
  fun name(): String => "frame_parser/close_valid_codes"

  fun gen(): Generator[U16] =>
    Generators.frequency[U16]([
      as WeightedGenerator[U16]:
      (1, Generators.u16(where min = 1000, max = 1003))
      (1, Generators.u16(where min = 1007, max = 1014))
      (1, Generators.u16(where min = 3000, max = 4999))
    ])

  fun property(code: U16, h: PropertyHelper) ? =>
    let payload: Array[U8] val =
      recover val [as U8: (code >> 8).u8(); code.u8()] end
    let frame = _TestFrameHelper.masked_frame(true, 0x08, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[U8](0x08, frames(0)?.opcode)
      h.assert_eq[U8]((code >> 8).u8(), frames(0)?.payload(0)?)
      h.assert_eq[U8](code.u8(), frames(0)?.payload(1)?)
    | let err: _FrameError =>
      h.fail("unexpected error for code " + code.string())
    end

class \nodoc\ iso _TestFrameParserCloseInvalidCodes is Property1[U16]
  """Invalid close status codes are rejected by the frame parser."""
  fun name(): String => "frame_parser/close_invalid_codes"

  fun gen(): Generator[U16] =>
    Generators.frequency[U16]([
      as WeightedGenerator[U16]:
      (1, Generators.u16(where min = 0, max = 999))
      (1, Generators.u16(where min = 1004, max = 1006))
      (1, Generators.u16(where min = 1015, max = 2999))
      (1, Generators.u16(where min = 5000, max = 65535))
    ])

  fun property(code: U16, h: PropertyHelper) =>
    let payload: Array[U8] val =
      recover val [as U8: (code >> 8).u8(); code.u8()] end
    let frame = _TestFrameHelper.masked_frame(true, 0x08, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.fail("expected error for invalid code " + code.string())
    | let err: _FrameError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    end

class \nodoc\ iso _TestFrameParserCloseMixedCodes is Property1[U16]
  """Close frame parsing succeeds if and only if the code is valid."""
  fun name(): String => "frame_parser/close_mixed_codes"

  fun gen(): Generator[U16] =>
    Generators.frequency[U16]([
      as WeightedGenerator[U16]:
      // Valid ranges
      (1, Generators.u16(where min = 1000, max = 1003))
      (1, Generators.u16(where min = 1007, max = 1014))
      (1, Generators.u16(where min = 3000, max = 4999))
      // Invalid ranges
      (1, Generators.u16(where min = 0, max = 999))
      (1, Generators.u16(where min = 1004, max = 1006))
      (1, Generators.u16(where min = 1015, max = 2999))
      (1, Generators.u16(where min = 5000, max = 65535))
    ])

  fun property(code: U16, h: PropertyHelper) =>
    let valid =
      if (code >= 1000) and (code <= 1003) then true
      elseif (code >= 1007) and (code <= 1014) then true
      elseif (code >= 3000) and (code <= 4999) then true
      else false
      end
    let payload: Array[U8] val =
      recover val [as U8: (code >> 8).u8(); code.u8()] end
    let frame = _TestFrameHelper.masked_frame(true, 0x08, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_true(valid, "code " + code.string() + " should be rejected")
    | let err: _FrameError =>
      h.assert_false(valid, "code " + code.string() + " should be accepted")
    end

class \nodoc\ iso _TestFrameParserPropertyRandom is Property1[USize]
  """Random valid masked frames parse successfully."""
  fun name(): String => "frame_parser/property_random_frames"

  fun gen(): Generator[USize] =>
    Generators.usize(where min = 0, max = 200)

  fun property(payload_size: USize, h: PropertyHelper) ? =>
    let payload: Array[U8] val = recover val
      let a = Array[U8](payload_size)
      var i: USize = 0
      while i < payload_size do a.push((i % 256).u8()); i = i + 1 end
      a
    end
    let frame = _TestFrameHelper.masked_frame(true, 0x02, payload)
    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      h.assert_eq[U8](0x02, frames(0)?.opcode)
      h.assert_eq[USize](payload_size, frames(0)?.payload.size())
    | let err: _FrameError =>
      h.fail("unexpected error for size " + payload_size.string())
    end
