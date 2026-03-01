use "pony_test"
use "pony_check"

class \nodoc\ iso _TestReassemblerSingleText is UnitTest
  """Single unfragmented text message is delivered immediately."""
  fun name(): String => "reassembler/single_text"

  fun apply(h: TestHelper) =>
    let reassembler = _FragmentReassembler
    let payload: Array[U8] val = "Hello".array()
    match \exhaustive\ reassembler.frame(true, 0x01, payload, 1_048_576)
    | let msg: _CompleteMessage =>
      h.assert_true(msg.is_text)
      h.assert_eq[USize](5, msg.data.size())
    | _FragmentContinue => h.fail("expected complete message")
    | let err: _ReassemblyError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestReassemblerSingleBinary is UnitTest
  """Single unfragmented binary message is delivered immediately."""
  fun name(): String => "reassembler/single_binary"

  fun apply(h: TestHelper) =>
    let reassembler = _FragmentReassembler
    let payload: Array[U8] val = recover val [as U8: 0x01; 0x02] end
    match \exhaustive\ reassembler.frame(true, 0x02, payload, 1_048_576)
    | let msg: _CompleteMessage =>
      h.assert_false(msg.is_text)
      h.assert_eq[USize](2, msg.data.size())
    | _FragmentContinue => h.fail("expected complete message")
    | let err: _ReassemblyError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestReassemblerMultiFragment is UnitTest
  """Multi-fragment text message delivers on final frame."""
  fun name(): String => "reassembler/multi_fragment"

  fun apply(h: TestHelper) ? =>
    let reassembler = _FragmentReassembler

    // First fragment: text, FIN=0
    let frag1: Array[U8] val = "Hel".array()
    match \exhaustive\ reassembler.frame(false, 0x01, frag1, 1_048_576)
    | _FragmentContinue => None // expected
    | let _: _CompleteMessage => h.fail("too early")
    | let err: _ReassemblyError => h.fail("unexpected error")
    end

    // Continuation: FIN=0
    let frag2: Array[U8] val = "lo ".array()
    match \exhaustive\ reassembler.frame(false, 0x00, frag2, 1_048_576)
    | _FragmentContinue => None // expected
    | let _: _CompleteMessage => h.fail("too early")
    | let err: _ReassemblyError => h.fail("unexpected error")
    end

    // Final continuation: FIN=1
    let frag3: Array[U8] val = "World".array()
    match \exhaustive\ reassembler.frame(true, 0x00, frag3, 1_048_576)
    | let msg: _CompleteMessage =>
      h.assert_true(msg.is_text)
      h.assert_eq[USize](11, msg.data.size())
      // Verify "Hello World"
      h.assert_eq[U8]('H', msg.data(0)?)
      h.assert_eq[U8]('d', msg.data(10)?)
    | _FragmentContinue => h.fail("expected complete after final fragment")
    | let err: _ReassemblyError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestReassemblerInterleavedData is UnitTest
  """Interleaved data frame during fragmentation is rejected."""
  fun name(): String => "reassembler/interleaved_data"

  fun apply(h: TestHelper) =>
    let reassembler = _FragmentReassembler

    // Start a text message
    let frag1: Array[U8] val = "Hello".array()
    match reassembler.frame(false, 0x01, frag1, 1_048_576)
    | _FragmentContinue => None
    else h.fail("expected continue")
    end

    // Attempt to start a new text message (interleaved)
    let frag2: Array[U8] val = "World".array()
    match \exhaustive\ reassembler.frame(true, 0x01, frag2, 1_048_576)
    | let err: _ReassemblyError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    | _FragmentContinue => h.fail("expected error")
    | let _: _CompleteMessage => h.fail("expected error")
    end

class \nodoc\ iso _TestReassemblerMaxSize is UnitTest
  """Accumulated size exceeding max_message_size is rejected."""
  fun name(): String => "reassembler/max_size"

  fun apply(h: TestHelper) =>
    let reassembler = _FragmentReassembler
    let payload: Array[U8] val = recover val
      let a = Array[U8](100)
      var i: USize = 0
      while i < 100 do a.push(0x41); i = i + 1 end
      a
    end
    match \exhaustive\ reassembler.frame(true, 0x02, payload, 50) // max=50
    | let err: _ReassemblyError =>
      h.assert_is[CloseCode](CloseMessageTooBig, err.code)
    | _FragmentContinue => h.fail("expected error")
    | let _: _CompleteMessage => h.fail("expected error")
    end

class \nodoc\ iso _TestReassemblerInvalidUtf8 is UnitTest
  """Text message with invalid UTF-8 is rejected."""
  fun name(): String => "reassembler/invalid_utf8"

  fun apply(h: TestHelper) =>
    let reassembler = _FragmentReassembler
    let payload: Array[U8] val = recover val [as U8: 0xFF; 0xFE] end
    match \exhaustive\ reassembler.frame(true, 0x01, payload, 1_048_576)
    | let err: _ReassemblyError =>
      h.assert_is[CloseCode](CloseInvalidPayload, err.code)
    | _FragmentContinue => h.fail("expected error")
    | let _: _CompleteMessage => h.fail("expected error")
    end

class \nodoc\ iso _TestReassemblerValidUtf8 is UnitTest
  """Text message with valid UTF-8 succeeds."""
  fun name(): String => "reassembler/valid_utf8"

  fun apply(h: TestHelper) =>
    let reassembler = _FragmentReassembler
    // Valid UTF-8: "café" = 63 61 66 C3 A9
    let payload: Array[U8] val =
      recover val [as U8: 0x63; 0x61; 0x66; 0xC3; 0xA9] end
    match \exhaustive\ reassembler.frame(true, 0x01, payload, 1_048_576)
    | let msg: _CompleteMessage =>
      h.assert_true(msg.is_text)
      h.assert_eq[USize](5, msg.data.size())
    | _FragmentContinue => h.fail("expected complete message")
    | let err: _ReassemblyError => h.fail("unexpected error")
    end

class \nodoc\ iso _TestReassemblerContinuationWithoutStart is UnitTest
  """Continuation frame without a preceding start frame is rejected."""
  fun name(): String => "reassembler/continuation_without_start"

  fun apply(h: TestHelper) =>
    let reassembler = _FragmentReassembler
    let payload: Array[U8] val = "data".array()
    match \exhaustive\ reassembler.frame(true, 0x00, payload, 1_048_576)
    | let err: _ReassemblyError =>
      h.assert_is[CloseCode](CloseProtocolError, err.code)
    | _FragmentContinue => h.fail("expected error")
    | let _: _CompleteMessage => h.fail("expected error")
    end

class \nodoc\ iso _TestReassemblerPropertyRoundtrip is Property1[USize]
  """Random payloads split into fragments reassemble to original."""
  fun name(): String => "reassembler/property_roundtrip"

  fun gen(): Generator[USize] =>
    Generators.usize(where min = 1, max = 500)

  fun property(total_size: USize, h: PropertyHelper) ? =>
    // Build a payload
    let full_payload = recover val
      let a = Array[U8](total_size)
      var i: USize = 0
      while i < total_size do
        a.push((i % 256).u8())
        i = i + 1
      end
      a
    end

    // Split into 3 fragments
    let split1 = total_size / 3
    let split2 = (total_size * 2) / 3

    let frag1 = recover val
      let a = Array[U8](split1)
      var i: USize = 0
      while i < split1 do a.push(full_payload(i)?); i = i + 1 end
      a
    end
    let frag2 = recover val
      let a = Array[U8](split2 - split1)
      var i: USize = split1
      while i < split2 do a.push(full_payload(i)?); i = i + 1 end
      a
    end
    let frag3 = recover val
      let a = Array[U8](total_size - split2)
      var i: USize = split2
      while i < total_size do a.push(full_payload(i)?); i = i + 1 end
      a
    end

    let reassembler = _FragmentReassembler
    match \exhaustive\ reassembler.frame(false, 0x02, frag1, total_size + 1)
    | _FragmentContinue => None
    else h.fail("expected continue for frag1")
    end
    match \exhaustive\ reassembler.frame(false, 0x00, frag2, total_size + 1)
    | _FragmentContinue => None
    else h.fail("expected continue for frag2")
    end
    match \exhaustive\ reassembler.frame(true, 0x00, frag3, total_size + 1)
    | let msg: _CompleteMessage =>
      h.assert_false(msg.is_text)
      h.assert_eq[USize](total_size, msg.data.size())
      // Verify every byte
      var i: USize = 0
      while i < total_size do
        h.assert_eq[U8](full_payload(i)?, msg.data(i)?)
        i = i + 1
      end
    | _FragmentContinue =>
      h.fail("expected complete after final fragment")
    | let err: _ReassemblyError =>
      h.fail("unexpected error")
    end
