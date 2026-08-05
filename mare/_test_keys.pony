use "pony_test"
use "encode/base64"

class \nodoc\ iso _TestMaskKeyFresh is UnitTest
  """
  Successive mask keys differ.

  RFC 6455 Section 5.3 requires a fresh key per frame and requires it to be
  unpredictable. A generator that returned a constant, or that was seeded
  once and reused, would satisfy neither — and would pass every masking
  round-trip test in the suite, which is why this is checked directly.
  """
  fun name(): String => "mask_key/fresh"

  fun apply(h: TestHelper) =>
    var previous: (U32 | None) = None
    var i: USize = 0
    var distinct: USize = 0
    while i < 32 do
      match _MaskKey()
      | let key: U32 =>
        match previous
        | let p: U32 => if key != p then distinct = distinct + 1 end
        | None => None
        end
        previous = key
      | _MaskKeyUnavailable => h.fail("CSPRNG unavailable")
      end
      i = i + 1
    end
    // Consecutive collisions are possible but 31 of them is not.
    h.assert_true(distinct >= 30, "keys repeated: " + distinct.string() + "/31")

class \nodoc\ iso _TestClientKeyShape is UnitTest
  """A client key is 16 bytes, Base64-encoded."""
  fun name(): String => "client_key/shape"

  fun apply(h: TestHelper) =>
    match _ClientKey()
    | let key: String val =>
      // Base64 of 16 bytes is 24 characters including one '=' of padding
      h.assert_eq[USize](24, key.size())
      try
        h.assert_eq[USize](16, Base64.decode[Array[U8] iso](key)?.size())
      else
        h.fail("key was not valid base64")
      end
    | _ClientKeyUnavailable => h.fail("CSPRNG unavailable")
    end

class \nodoc\ iso _TestClientKeyFresh is UnitTest
  """Successive client keys differ."""
  fun name(): String => "client_key/fresh"

  fun apply(h: TestHelper) =>
    match _ClientKey()
    | let first: String val =>
      match _ClientKey()
      | let second: String val =>
        h.assert_false(first == second, "two keys were identical")
      | _ClientKeyUnavailable => h.fail("CSPRNG unavailable")
      end
    | _ClientKeyUnavailable => h.fail("CSPRNG unavailable")
    end
