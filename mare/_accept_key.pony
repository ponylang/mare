use crypto = "ssl/crypto"
use "encode/base64"

primitive _AcceptKey
  """
  Derives the Sec-WebSocket-Accept value from a Sec-WebSocket-Key.

  Both directions need this and must agree byte for byte: the server sends
  what this returns, and the client compares against it. Sharing one
  implementation is what makes that agreement structural rather than a
  thing to keep in sync.
  """

  fun apply(key: String val): String val ? =>
    """
    Concatenate the key with the WebSocket GUID, take the SHA-1 hash, and
    Base64-encode the result, per RFC 6455 Section 4.2.2.

    Raises when the hash cannot be taken.
    """
    let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    Base64.encode(
      crypto.Digest.sha1()?.>append(key)?.>append(magic)?.final()?)
