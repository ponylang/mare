primitive _Utf8Validator
  """
  Validates that a byte sequence is well-formed UTF-8.

  Checks all encoding rules: valid lead bytes, correct continuation byte
  counts, no overlong encodings, no surrogates (U+D800..U+DFFF), and no
  codepoints above U+10FFFF.
  """

  fun is_valid(data: Array[U8] box): Bool =>
    """
    Return true if `data` is valid UTF-8.
    """
    var i: USize = 0
    let size = data.size()

    while i < size do
      try
        let b0 = data(i)?

        if b0 < 0x80 then
          // Single byte (ASCII)
          i = i + 1
        elseif (b0 and 0xE0) == 0xC0 then
          // Two-byte sequence
          if (i + 1) >= size then return false end
          let b1 = data(i + 1)?
          if (b1 and 0xC0) != 0x80 then return false end
          // Reject overlong: smallest two-byte is U+0080 (lead byte 0xC2)
          if b0 < 0xC2 then return false end
          i = i + 2
        elseif (b0 and 0xF0) == 0xE0 then
          // Three-byte sequence
          if (i + 2) >= size then return false end
          let b1 = data(i + 1)?
          let b2 = data(i + 2)?
          if (b1 and 0xC0) != 0x80 then return false end
          if (b2 and 0xC0) != 0x80 then return false end
          // Reject overlong: E0 requires b1 >= A0
          if (b0 == 0xE0) and (b1 < 0xA0) then return false end
          // Reject surrogates: ED requires b1 < A0
          if (b0 == 0xED) and (b1 >= 0xA0) then return false end
          i = i + 3
        elseif (b0 and 0xF8) == 0xF0 then
          // Four-byte sequence
          if (i + 3) >= size then return false end
          let b1 = data(i + 1)?
          let b2 = data(i + 2)?
          let b3 = data(i + 3)?
          if (b1 and 0xC0) != 0x80 then return false end
          if (b2 and 0xC0) != 0x80 then return false end
          if (b3 and 0xC0) != 0x80 then return false end
          // Reject overlong: F0 requires b1 >= 90
          if (b0 == 0xF0) and (b1 < 0x90) then return false end
          // Reject above U+10FFFF: F4 requires b1 < 90
          if (b0 == 0xF4) and (b1 >= 0x90) then return false end
          // Reject lead bytes above F4
          if b0 > 0xF4 then return false end
          i = i + 4
        else
          // Invalid lead byte (continuation byte or 0xF5+)
          return false
        end
      else
        _Unreachable()
        return false
      end
    end
    true
