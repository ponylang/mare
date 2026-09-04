use "pony_test"
use "pony_check"

class \nodoc\ iso _TestUtf8ValidAscii is UnitTest
  """Valid ASCII bytes are accepted."""
  fun name(): String => "utf8/valid_ascii"

  fun apply(h: TestHelper) =>
    h.assert_true(_Utf8Validator.is_valid("Hello, world!".array()))

class \nodoc\ iso _TestUtf8ValidEmpty is UnitTest
  """Empty input is valid."""
  fun name(): String => "utf8/valid_empty"

  fun apply(h: TestHelper) =>
    h.assert_true(_Utf8Validator.is_valid(recover val Array[U8] end))

class \nodoc\ iso _TestUtf8ValidTwoByte is UnitTest
  """Valid two-byte UTF-8 sequence (e.g., U+00E9 'e with acute')."""
  fun name(): String => "utf8/valid_two_byte"

  fun apply(h: TestHelper) =>
    // U+00E9 = 0xC3 0xA9
    h.assert_true(_Utf8Validator.is_valid(
      recover val [as U8: 0xC3; 0xA9] end))

class \nodoc\ iso _TestUtf8ValidThreeByte is UnitTest
  """Valid three-byte UTF-8 sequence (e.g., U+4E16 CJK character)."""
  fun name(): String => "utf8/valid_three_byte"

  fun apply(h: TestHelper) =>
    // U+4E16 = 0xE4 0xB8 0x96
    h.assert_true(_Utf8Validator.is_valid(
      recover val [as U8: 0xE4; 0xB8; 0x96] end))

class \nodoc\ iso _TestUtf8ValidFourByte is UnitTest
  """Valid four-byte UTF-8 sequence (e.g., U+1F600 emoji)."""
  fun name(): String => "utf8/valid_four_byte"

  fun apply(h: TestHelper) =>
    // U+1F600 = 0xF0 0x9F 0x98 0x80
    h.assert_true(_Utf8Validator.is_valid(
      recover val [as U8: 0xF0; 0x9F; 0x98; 0x80] end))

class \nodoc\ iso _TestUtf8InvalidTruncated is UnitTest
  """Truncated multi-byte sequence is rejected."""
  fun name(): String => "utf8/invalid_truncated"

  fun apply(h: TestHelper) =>
    // Two-byte lead without continuation
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xC3] end))
    // Three-byte lead with only one continuation
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xE4; 0xB8] end))
    // Four-byte lead with only two continuations
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xF0; 0x9F; 0x98] end))

class \nodoc\ iso _TestUtf8InvalidOverlong is UnitTest
  """Overlong encodings are rejected."""
  fun name(): String => "utf8/invalid_overlong"

  fun apply(h: TestHelper) =>
    // Overlong two-byte encoding of U+0000 (0xC0 0x80)
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xC0; 0x80] end))
    // Overlong two-byte encoding of U+007F (0xC1 0xBF)
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xC1; 0xBF] end))
    // Overlong three-byte encoding of U+007F (0xE0 0x81 0xBF)
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xE0; 0x81; 0xBF] end))
    // Overlong four-byte encoding (0xF0 0x80 0x80 0x80)
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xF0; 0x80; 0x80; 0x80] end))

class \nodoc\ iso _TestUtf8InvalidSurrogate is UnitTest
  """Surrogate halves (U+D800-U+DFFF) are rejected."""
  fun name(): String => "utf8/invalid_surrogate"

  fun apply(h: TestHelper) =>
    // U+D800 = 0xED 0xA0 0x80
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xED; 0xA0; 0x80] end))
    // U+DFFF = 0xED 0xBF 0xBF
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xED; 0xBF; 0xBF] end))

class \nodoc\ iso _TestUtf8InvalidAboveMax is UnitTest
  """Codepoints above U+10FFFF are rejected."""
  fun name(): String => "utf8/invalid_above_max"

  fun apply(h: TestHelper) =>
    // 0xF4 0x90 0x80 0x80 = U+110000 (first invalid)
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xF4; 0x90; 0x80; 0x80] end))
    // Lead byte 0xF5 (always invalid)
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xF5; 0x80; 0x80; 0x80] end))

class \nodoc\ iso _TestUtf8InvalidContinuationFirst is UnitTest
  """Continuation byte at start of sequence is rejected."""
  fun name(): String => "utf8/invalid_continuation_first"

  fun apply(h: TestHelper) =>
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0x80] end))
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: 0xBF] end))

class \nodoc\ iso _TestUtf8PropertyValidStrings is Property1[String]
  """Valid Unicode strings encoded as UTF-8 are accepted."""
  fun name(): String => "utf8/property_valid_strings"

  fun gen(): Generator[String] =>
    Generators.ascii_printable(
      where from = 0, to = 100)

  fun property(sample: String, h: PropertyHelper) =>
    h.assert_true(_Utf8Validator.is_valid(sample.array()))

class \nodoc\ iso _TestUtf8PropertyInvalidByte is Property1[U8]
  """Bytes 0xF5-0xFF at start of sequence are always invalid."""
  fun name(): String => "utf8/property_invalid_lead_byte"

  fun gen(): Generator[U8] =>
    // Generate bytes in range 0xF5..0xFF
    Generators.u8(where from = 0xF5)

  fun property(sample: U8, h: PropertyHelper) =>
    h.assert_false(_Utf8Validator.is_valid(
      recover val [as U8: sample; 0x80; 0x80; 0x80] end))
