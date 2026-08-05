// Errors that can occur during WebSocket HTTP upgrade handshake validation.
type ServerHandshakeError is
  ( ServerHandshakeRequestTooLarge
  | ServerHandshakeInvalidHTTP
  | ServerHandshakeMissingHost
  | ServerHandshakeMissingUpgrade
  | ServerHandshakeWrongVersion
  | ServerHandshakeMissingKey
  | ServerHandshakeInvalidKey
  | ServerHandshakeAcceptKeyFailed )

primitive ServerHandshakeRequestTooLarge is Stringable
  """The HTTP upgrade request exceeded the maximum allowed size."""
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Handshake request too large".clone()

primitive ServerHandshakeInvalidHTTP is Stringable
  """The HTTP request line was malformed or not a GET request."""
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Invalid HTTP request".clone()

primitive ServerHandshakeMissingHost is Stringable
  """The required Host header was missing."""
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Missing Host header".clone()

primitive ServerHandshakeMissingUpgrade is Stringable
  """
  The required Upgrade and Connection headers were missing or had
  incorrect values.
  """
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Missing or invalid Upgrade/Connection headers".clone()

primitive ServerHandshakeWrongVersion is Stringable
  """The Sec-WebSocket-Version header was not 13."""
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Wrong WebSocket version (expected 13)".clone()

primitive ServerHandshakeMissingKey is Stringable
  """The Sec-WebSocket-Key header was missing."""
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Missing Sec-WebSocket-Key header".clone()

primitive ServerHandshakeInvalidKey is Stringable
  """
  The Sec-WebSocket-Key header was not a valid base64-encoded
  16-byte value.
  """
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Invalid Sec-WebSocket-Key (must be base64-encoded 16 bytes)".clone()

primitive ServerHandshakeAcceptKeyFailed is Stringable
  """
  The Sec-WebSocket-Accept value could not be computed.

  The request was well formed; the SHA-1 the accept value is built from
  could not be taken. A server that reports this answers 500 rather than
  400, because nothing about the client's request was wrong.
  """
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Could not compute Sec-WebSocket-Accept".clone()
