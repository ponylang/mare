use crypto = "ssl/crypto"
use "encode/base64"

primitive _ClientKey
  """
  Source of Sec-WebSocket-Key values.

  RFC 6455 Section 4.1 requires the key to be 16 freshly generated random
  bytes, Base64-encoded, and requires that it be unpredictable. The key is
  not a secret — it travels in the clear and the server echoes a hash of
  it straight back. It exists so a client can tell a real handshake from a
  replayed or fabricated one: only a peer that saw this particular key can
  produce the matching accept value.

  Hence OpenSSL's CSPRNG, for the same reason `_MaskKey` uses it.
  """

  fun apply(): (String val | _ClientKeyUnavailable) =>
    """
    Generate a Base64-encoded 16-byte key.

    Returns `_ClientKeyUnavailable` when the CSPRNG cannot produce secure
    output, which in practice means the system entropy pool has not been
    initialised.
    """
    try
      Base64.encode(crypto.RandBytes(16)?)
    else
      _ClientKeyUnavailable
    end

primitive _ClientKeyUnavailable
  """
  The CSPRNG could not produce a Sec-WebSocket-Key.

  There is no safe fallback: a predictable key would leave the client
  unable to distinguish a server that completed this handshake from one
  replaying an old response. The connection attempt is abandoned instead.
  """
