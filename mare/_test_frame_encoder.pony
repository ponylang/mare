use "pony_test"
use "pony_check"

class \nodoc\ iso _TestFrameEncoderText is UnitTest
  """Text frame: FIN=1, opcode=0x1, MASK=0, correct payload."""
  fun name(): String => "frame_encoder/text"

  fun apply(h: TestHelper) ? =>
    let frame = _FrameEncoder.text("Hello")
    // First byte: FIN(0x80) | opcode(0x01) = 0x81
    h.assert_eq[U8](0x81, frame(0)?)
    // Second byte: MASK=0, length=5
    h.assert_eq[U8](5, frame(1)?)
    // Payload
    h.assert_eq[U8]('H', frame(2)?)
    h.assert_eq[U8]('e', frame(3)?)
    h.assert_eq[U8]('l', frame(4)?)
    h.assert_eq[U8]('l', frame(5)?)
    h.assert_eq[U8]('o', frame(6)?)
    h.assert_eq[USize](7, frame.size())

class \nodoc\ iso _TestFrameEncoderBinary is UnitTest
  """Binary frame: FIN=1, opcode=0x2, correct payload."""
  fun name(): String => "frame_encoder/binary"

  fun apply(h: TestHelper) ? =>
    let data: Array[U8] val = recover val [as U8: 0x01; 0x02; 0x03] end
    let frame = _FrameEncoder.binary(data)
    h.assert_eq[U8](0x82, frame(0)?)
    h.assert_eq[U8](3, frame(1)?)
    h.assert_eq[U8](0x01, frame(2)?)
    h.assert_eq[U8](0x02, frame(3)?)
    h.assert_eq[U8](0x03, frame(4)?)

class \nodoc\ iso _TestFrameEncoderCloseWithCode is UnitTest
  """Close frame with status code and reason."""
  fun name(): String => "frame_encoder/close_with_code"

  fun apply(h: TestHelper) ? =>
    let frame = _FrameEncoder.close(CloseNormal, "bye")
    // FIN=1, opcode=0x8
    h.assert_eq[U8](0x88, frame(0)?)
    // Length: 2 (status) + 3 (reason) = 5
    h.assert_eq[U8](5, frame(1)?)
    // Status code 1000 big-endian
    h.assert_eq[U8](0x03, frame(2)?)
    h.assert_eq[U8](0xE8, frame(3)?)
    // Reason
    h.assert_eq[U8]('b', frame(4)?)
    h.assert_eq[U8]('y', frame(5)?)
    h.assert_eq[U8]('e', frame(6)?)

class \nodoc\ iso _TestFrameEncoderCloseEmpty is UnitTest
  """Close frame with no payload."""
  fun name(): String => "frame_encoder/close_empty"

  fun apply(h: TestHelper) ? =>
    let frame = _FrameEncoder.close_empty()
    h.assert_eq[U8](0x88, frame(0)?)
    h.assert_eq[U8](0, frame(1)?)
    h.assert_eq[USize](2, frame.size())

class \nodoc\ iso _TestFrameEncoderPong is UnitTest
  """Pong frame echoes payload."""
  fun name(): String => "frame_encoder/pong"

  fun apply(h: TestHelper) ? =>
    let payload: Array[U8] val = recover val [as U8: 0xAA; 0xBB] end
    let frame = _FrameEncoder.pong(payload)
    // FIN=1, opcode=0xA
    h.assert_eq[U8](0x8A, frame(0)?)
    h.assert_eq[U8](2, frame(1)?)
    h.assert_eq[U8](0xAA, frame(2)?)
    h.assert_eq[U8](0xBB, frame(3)?)

class \nodoc\ iso _TestFrameEncoderLength16Bit is UnitTest
  """Payload 126-65535 bytes uses 16-bit extended length."""
  fun name(): String => "frame_encoder/length_16bit"

  fun apply(h: TestHelper) ? =>
    // Create 200-byte payload
    let payload: Array[U8] val = recover val
      let a = Array[U8](200)
      var i: USize = 0
      while i < 200 do
        a.push(0x41)
        i = i + 1
      end
      a
    end
    let frame = _FrameEncoder.binary(payload)
    h.assert_eq[U8](0x82, frame(0)?)
    // Length indicator: 126
    h.assert_eq[U8](126, frame(1)?)
    // 16-bit big-endian length: 200 = 0x00C8
    h.assert_eq[U8](0x00, frame(2)?)
    h.assert_eq[U8](0xC8, frame(3)?)
    // Total frame size: 2 + 2 (extended length) + 200 = 204
    h.assert_eq[USize](204, frame.size())

class \nodoc\ iso _TestFrameEncoderLength64Bit is UnitTest
  """Payload > 65535 bytes uses 64-bit extended length."""
  fun name(): String => "frame_encoder/length_64bit"

  fun apply(h: TestHelper) ? =>
    // Create 65536-byte payload
    let size: USize = 65536
    let payload: Array[U8] val = recover val
      let a = Array[U8](size)
      var i: USize = 0
      while i < size do
        a.push(0x42)
        i = i + 1
      end
      a
    end
    let frame = _FrameEncoder.binary(payload)
    h.assert_eq[U8](0x82, frame(0)?)
    // Length indicator: 127
    h.assert_eq[U8](127, frame(1)?)
    // 64-bit big-endian length: 65536 = 0x0000000000010000
    h.assert_eq[U8](0x00, frame(2)?)
    h.assert_eq[U8](0x00, frame(3)?)
    h.assert_eq[U8](0x00, frame(4)?)
    h.assert_eq[U8](0x00, frame(5)?)
    h.assert_eq[U8](0x00, frame(6)?)
    h.assert_eq[U8](0x01, frame(7)?)
    h.assert_eq[U8](0x00, frame(8)?)
    h.assert_eq[U8](0x00, frame(9)?)
    // Total frame size: 2 + 8 (extended length) + 65536 = 65546
    h.assert_eq[USize](65546, frame.size())

class \nodoc\ iso _TestFrameEncoderMaskedRfc6455 is UnitTest
  """
  A masked text frame matches the worked example in RFC 6455 Section 5.7.
  """
  fun name(): String => "frame_encoder/masked_rfc6455"

  fun apply(h: TestHelper) ? =>
    let frame = _FrameEncoder.text("Hello", 0x37FA213D)
    h.assert_eq[USize](11, frame.size())
    // FIN=1, opcode=0x1
    h.assert_eq[U8](0x81, frame(0)?)
    // MASK=1, length=5
    h.assert_eq[U8](0x85, frame(1)?)
    // Mask key, big-endian
    h.assert_eq[U8](0x37, frame(2)?)
    h.assert_eq[U8](0xFA, frame(3)?)
    h.assert_eq[U8](0x21, frame(4)?)
    h.assert_eq[U8](0x3D, frame(5)?)
    // "Hello" XORed with the key
    h.assert_eq[U8](0x7F, frame(6)?)
    h.assert_eq[U8](0x9F, frame(7)?)
    h.assert_eq[U8](0x4D, frame(8)?)
    h.assert_eq[U8](0x51, frame(9)?)
    h.assert_eq[U8](0x58, frame(10)?)

class \nodoc\ iso _TestFrameEncoderMaskedLength16Bit is UnitTest
  """A masked frame places the key after the extended length, not before."""
  fun name(): String => "frame_encoder/masked_length_16bit"

  fun apply(h: TestHelper) ? =>
    let payload: Array[U8] val = recover val
      let a = Array[U8](200)
      var i: USize = 0
      while i < 200 do
        a.push(0x41)
        i = i + 1
      end
      a
    end
    let frame = _FrameEncoder.binary(payload, 0x01020304)
    h.assert_eq[U8](0x82, frame(0)?)
    // MASK=1 combined with the 126 length indicator
    h.assert_eq[U8](0xFE, frame(1)?)
    // 16-bit big-endian length: 200 = 0x00C8
    h.assert_eq[U8](0x00, frame(2)?)
    h.assert_eq[U8](0xC8, frame(3)?)
    // Mask key follows the extended length
    h.assert_eq[U8](0x01, frame(4)?)
    h.assert_eq[U8](0x02, frame(5)?)
    h.assert_eq[U8](0x03, frame(6)?)
    h.assert_eq[U8](0x04, frame(7)?)
    // First payload byte: 0x41 xor 0x01
    h.assert_eq[U8](0x40, frame(8)?)
    // Total: 2 header + 2 length + 4 key + 200 payload
    h.assert_eq[USize](208, frame.size())

class \nodoc\ iso _TestFrameEncoderMaskedClose is UnitTest
  """A masked close frame masks the status code, which is payload."""
  fun name(): String => "frame_encoder/masked_close"

  fun apply(h: TestHelper) ? =>
    let frame = _FrameEncoder.close(CloseNormal where mask_key = 0xFFFFFFFF)
    // FIN=1, opcode=0x8
    h.assert_eq[U8](0x88, frame(0)?)
    // MASK=1, length=2
    h.assert_eq[U8](0x82, frame(1)?)
    // Status 1000 = 0x03E8, each byte XORed with 0xFF
    h.assert_eq[U8](0xFC, frame(6)?)
    h.assert_eq[U8](0x17, frame(7)?)
    h.assert_eq[USize](8, frame.size())

class \nodoc\ iso _TestFrameEncoderPropertyRoundtrip is Property1[USize]
  """
  Masked frames of any payload size parse back to the original bytes.

  `_FrameParser` reads the server direction, which requires masked input,
  so encoding as a client would is exactly what it accepts.
  """
  fun name(): String => "frame_encoder/property_roundtrip"

  fun gen(): Generator[USize] =>
    Generators.usize(where min = 0, max = 300)

  fun property(payload_size: USize, h: PropertyHelper) ? =>
    // Vary the payload bytes so a masking error cannot cancel itself out
    let payload_s = String(payload_size)
    var i: USize = 0
    while i < payload_size do
      payload_s.push('A' + (i % 26).u8())
      i = i + 1
    end
    let payload: Array[U8] val = payload_s.clone().iso_array()

    let frame = _FrameEncoder.binary(payload, 0x37FA213D)

    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      let parsed = frames(0)?
      h.assert_true(parsed.fin)
      h.assert_eq[U8](0x02, parsed.opcode)
      h.assert_eq[USize](payload_size, parsed.payload.size())
      // Verify payload bytes match
      var j: USize = 0
      while j < payload_size do
        h.assert_eq[U8](payload(j)?, parsed.payload(j)?)
        j = j + 1
      end
    | let err: _FrameError =>
      h.fail("Frame parser returned error")
    end

class \nodoc\ iso _TestFrameEncoderPropertyMaskKeys is Property1[U32]
  """
  Any mask key round-trips. Catches byte-order and shift errors that a
  single fixed key can hide.
  """
  fun name(): String => "frame_encoder/property_mask_keys"

  fun gen(): Generator[U32] =>
    Generators.u32()

  fun property(mask_key: U32, h: PropertyHelper) ? =>
    let payload: Array[U8] val = recover val
      let a = Array[U8](64)
      var i: USize = 0
      while i < 64 do
        a.push(i.u8())
        i = i + 1
      end
      a
    end

    let frame = _FrameEncoder.binary(payload, mask_key)

    let parser = _FrameParser
    match \exhaustive\ parser.parse(frame)
    | let frames: Array[_ParsedFrame val] val =>
      h.assert_eq[USize](1, frames.size())
      let parsed = frames(0)?
      h.assert_eq[USize](64, parsed.payload.size())
      var j: USize = 0
      while j < 64 do
        h.assert_eq[U8](payload(j)?, parsed.payload(j)?)
        j = j + 1
      end
    | let err: _FrameError =>
      h.fail("Frame parser returned error")
    end
