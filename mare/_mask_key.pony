use crypto = "ssl/crypto"

primitive _MaskKey
  """
  Source of WebSocket frame masking keys.

  RFC 6455 Section 5.3 requires each client-to-server frame to carry a
  fresh 32-bit masking key, and requires that key to be unpredictable to
  the server. The requirement is not about confidentiality — the key
  travels in the clear, immediately before the data it masks. It exists so
  a client cannot be induced to lay out attacker-chosen bytes on the wire,
  which is what would let a hostile page smuggle a forged request past an
  intercepting proxy that does not understand WebSocket framing.

  Hence OpenSSL's CSPRNG rather than a general purpose PRNG: `Rand` is a
  xorshift generator, so an observer who has seen a few keys can predict
  the next ones, and the guarantee is gone.
  """

  fun apply(): (U32 | _MaskKeyUnavailable) =>
    """
    Generate a masking key, in wire order (big-endian).

    Returns `_MaskKeyUnavailable` when the CSPRNG cannot produce secure
    output, which in practice means the system entropy pool has not been
    initialised.
    """
    try
      let bytes = crypto.RandBytes(4)?
      (bytes(0)?.u32() << 24) or
        (bytes(1)?.u32() << 16) or
        (bytes(2)?.u32() << 8) or
        bytes(3)?.u32()
    else
      _MaskKeyUnavailable
    end

primitive _MaskKeyUnavailable
  """
  The CSPRNG could not produce a masking key.

  There is no safe fallback. Sending the frame unmasked would violate
  RFC 6455 Section 5.1, and a conformant server must fail the connection
  on receiving it. Masking with a predictable key would forfeit the
  guarantee the mask exists to provide. The frame is dropped instead.
  """
