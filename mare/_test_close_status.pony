use "pony_test"
use "pony_check"

// -- Example-based tests for _CloseStatusExtractor --

class \nodoc\ _TestExtractorEmptyPayload is UnitTest
  fun name(): String => "CloseStatusExtractor/empty payload"

  fun apply(h: TestHelper) =>
    (let status, let reason) =
      _CloseStatusExtractor.from_payload(recover val Array[U8] end)
    h.assert_is[CloseStatus](CloseNoStatusReceived, status)
    h.assert_eq[String val]("", reason)

class \nodoc\ _TestExtractorStandardCode is UnitTest
  fun name(): String => "CloseStatusExtractor/standard code 1000"

  fun apply(h: TestHelper) =>
    let payload: Array[U8] val = recover val [as U8: 0x03; 0xE8] end
    (let status, let reason) = _CloseStatusExtractor.from_payload(payload)
    h.assert_is[CloseStatus](CloseNormal, status)
    h.assert_eq[String val]("", reason)

class \nodoc\ _TestExtractorCodeWithReason is UnitTest
  fun name(): String => "CloseStatusExtractor/code with reason"

  fun apply(h: TestHelper) =>
    // 1000 + "bye"
    let payload: Array[U8] val =
      recover val [as U8: 0x03; 0xE8; 'b'; 'y'; 'e'] end
    (let status, let reason) = _CloseStatusExtractor.from_payload(payload)
    h.assert_is[CloseStatus](CloseNormal, status)
    h.assert_eq[String val]("bye", reason)

class \nodoc\ _TestExtractorApplicationCode is UnitTest
  fun name(): String => "CloseStatusExtractor/application code 3000"

  fun apply(h: TestHelper) =>
    // 3000 = 0x0BB8
    let payload: Array[U8] val = recover val [as U8: 0x0B; 0xB8] end
    (let status, let reason) = _CloseStatusExtractor.from_payload(payload)
    match status
    | let o: OtherCloseCode =>
      h.assert_eq[U16](3000, o.code())
    else
      h.fail("Expected OtherCloseCode, got named primitive")
    end
    h.assert_eq[String val]("", reason)

class \nodoc\ _TestExtractorAllNamedCodes is UnitTest
  fun name(): String => "CloseStatusExtractor/all named codes"

  fun apply(h: TestHelper) =>
    _check(h, 1000, CloseNormal)
    _check(h, 1001, CloseGoingAway)
    _check(h, 1002, CloseProtocolError)
    _check(h, 1003, CloseUnsupportedData)
    _check(h, 1007, CloseInvalidPayload)
    _check(h, 1008, ClosePolicyViolation)
    _check(h, 1009, CloseMessageTooBig)
    _check(h, 1011, CloseInternalError)

  fun _check(h: TestHelper, code: U16, expected: CloseStatus) =>
    let payload: Array[U8] val = recover val
      [as U8: (code >> 8).u8(); code.u8()]
    end
    (let status, _) = _CloseStatusExtractor.from_payload(payload)
    h.assert_is[CloseStatus](expected, status)

// -- Example-based tests for new types --

class \nodoc\ _TestCloseNoStatusReceivedType is UnitTest
  fun name(): String => "CloseNoStatusReceived/code and string"

  fun apply(h: TestHelper) =>
    h.assert_eq[U16](1005, CloseNoStatusReceived.code())
    h.assert_eq[String val]("1005 No Status Received",
      CloseNoStatusReceived.string())

class \nodoc\ _TestCloseAbnormalClosureType is UnitTest
  fun name(): String => "CloseAbnormalClosure/code and string"

  fun apply(h: TestHelper) =>
    h.assert_eq[U16](1006, CloseAbnormalClosure.code())
    h.assert_eq[String val]("1006 Abnormal Closure",
      CloseAbnormalClosure.string())

class \nodoc\ _TestOtherCloseCodeType is UnitTest
  fun name(): String => "OtherCloseCode/code and string"

  fun apply(h: TestHelper) =>
    let c = OtherCloseCode(3500)
    h.assert_eq[U16](3500, c.code())
    h.assert_eq[String val]("3500 Other", c.string())

// -- Property-based tests --

class \nodoc\ _TestExtractorPropertyNamedCodes is Property1[U16]
  """All named code values produce their respective primitive."""

  fun name(): String => "CloseStatusExtractor/property: named codes"

  fun gen(): Generator[U16] =>
    Generators.one_of[U16]([as U16: 1000; 1001; 1002; 1003
      1007; 1008; 1009; 1011])

  fun property(sample: U16, h: PropertyHelper) =>
    let payload: Array[U8] val = recover val
      [as U8: (sample >> 8).u8(); sample.u8()]
    end
    (let status, _) = _CloseStatusExtractor.from_payload(payload)
    match status
    | let _: OtherCloseCode =>
      h.fail("Named code " + sample.string() + " produced OtherCloseCode")
    end
    // Verify the code() method returns the input
    match status
    | let s: CloseNormal => h.assert_eq[U16](sample, s.code())
    | let s: CloseGoingAway => h.assert_eq[U16](sample, s.code())
    | let s: CloseProtocolError => h.assert_eq[U16](sample, s.code())
    | let s: CloseUnsupportedData => h.assert_eq[U16](sample, s.code())
    | let s: CloseInvalidPayload => h.assert_eq[U16](sample, s.code())
    | let s: ClosePolicyViolation => h.assert_eq[U16](sample, s.code())
    | let s: CloseMessageTooBig => h.assert_eq[U16](sample, s.code())
    | let s: CloseInternalError => h.assert_eq[U16](sample, s.code())
    end

class \nodoc\ _TestExtractorPropertyOtherCodes is Property1[U16]
  """Valid-but-unnamed codes produce OtherCloseCode with matching code()."""

  fun name(): String => "CloseStatusExtractor/property: other codes"

  fun gen(): Generator[U16] =>
    // Valid codes that don't have named primitives:
    // 1010, 1012-1014, 3000-4999
    Generators.frequency[U16]([as (USize, Generator[U16]):
      (1, Generators.one_of[U16]([as U16: 1010; 1012; 1013; 1014]))
      (4, Generators.u16(3000, 4999))
    ])

  fun property(sample: U16, h: PropertyHelper) =>
    let payload: Array[U8] val = recover val
      [as U8: (sample >> 8).u8(); sample.u8()]
    end
    (let status, _) = _CloseStatusExtractor.from_payload(payload)
    match status
    | let o: OtherCloseCode =>
      h.assert_eq[U16](sample, o.code())
    else
      h.fail("Code " + sample.string()
        + " should produce OtherCloseCode but got named primitive")
    end

class \nodoc\ _TestExtractorPropertyRoundtrip is Property1[U16]
  """All valid close codes roundtrip through extraction."""

  fun name(): String => "CloseStatusExtractor/property: roundtrip"

  fun gen(): Generator[U16] =>
    // All valid receivable codes: 1000-1003, 1007-1014, 3000-4999
    Generators.frequency[U16]([as (USize, Generator[U16]):
      (1, Generators.u16(1000, 1003))
      (1, Generators.u16(1007, 1014))
      (4, Generators.u16(3000, 4999))
    ])

  fun property(sample: U16, h: PropertyHelper) =>
    let payload: Array[U8] val = recover val
      [as U8: (sample >> 8).u8(); sample.u8()]
    end
    (let status, _) = _CloseStatusExtractor.from_payload(payload)
    // Verify the extracted code matches the input regardless of type
    let extracted_code = match \exhaustive\ status
      | let s: CloseNormal => s.code()
      | let s: CloseGoingAway => s.code()
      | let s: CloseProtocolError => s.code()
      | let s: CloseUnsupportedData => s.code()
      | let s: CloseInvalidPayload => s.code()
      | let s: ClosePolicyViolation => s.code()
      | let s: CloseMessageTooBig => s.code()
      | let s: CloseInternalError => s.code()
      | let s: CloseNoStatusReceived => s.code()
      | let s: CloseAbnormalClosure => s.code()
      | let s: OtherCloseCode => s.code()
      end
    h.assert_eq[U16](sample, extracted_code)
