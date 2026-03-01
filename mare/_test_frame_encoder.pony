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

class \nodoc\ iso _TestFrameEncoderPropertyRoundtrip is Property1[USize]
  """Encoded frames can be parsed back through the frame parser."""
  fun name(): String => "frame_encoder/property_roundtrip"

  fun gen(): Generator[USize] =>
    Generators.usize(where min = 0, max = 300)

  fun property(payload_size: USize, h: PropertyHelper) ? =>
    // Build a payload of the given size
    let payload_s = String(payload_size)
    var i: USize = 0
    while i < payload_size do
      payload_s.push('A')
      i = i + 1
    end
    let payload: Array[U8] val = payload_s.clone().iso_array()

    // Encode as binary frame (server-to-client, unmasked)
    let frame = _FrameEncoder.binary(payload)

    // To parse through _FrameParser, we need to mask the frame
    // (client-to-server). Build a masked version.
    let mask_key: Array[U8] val =
      recover val [as U8: 0x37; 0xFA; 0x21; 0x3D] end
    let masked = _mask_frame(frame, mask_key)?

    // Parse
    let parser = _FrameParser
    match \exhaustive\ parser.parse(masked)
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

  fun _mask_frame(
    frame: Array[U8] val,
    mask_key: Array[U8] val)
    : Array[U8] val ?
  =>
    """
    Convert an unmasked server frame to a masked client frame for
    testing. Sets the MASK bit and inserts the mask key, then XORs
    the payload.
    """
    // Read the original header
    let b0 = frame(0)?
    let b1 = frame(1)?
    let orig_len_byte = b1 and 0x7F

    // Determine header size and payload offset
    var header_size: USize = 2
    if orig_len_byte == 126 then header_size = 4
    elseif orig_len_byte == 127 then header_size = 10
    end
    let payload_offset = header_size
    let payload_size = frame.size() - payload_offset

    // Build masked frame
    let result = recover iso
      let r = Array[U8](header_size + 4 + payload_size)
      // Copy first byte unchanged
      r.push(b0)
      // Set MASK bit on second byte
      r.push(b1 or 0x80)
      // Copy extended length bytes if any
      var i: USize = 2
      while i < header_size do
        r.push(frame(i)?)
        i = i + 1
      end
      // Insert mask key
      r.push(mask_key(0)?)
      r.push(mask_key(1)?)
      r.push(mask_key(2)?)
      r.push(mask_key(3)?)
      // Mask payload
      var j: USize = 0
      while j < payload_size do
        r.push(frame(payload_offset + j)? xor mask_key(j % 4)?)
        j = j + 1
      end
      r
    end
    consume result
