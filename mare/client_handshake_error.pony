// Errors that can occur while validating a server's WebSocket upgrade
// response. These mirror the client-side requirements in RFC 6455
// Section 4.1; every one of them means the connection must be failed
// rather than downgraded to plain HTTP.
type ClientHandshakeError is
  ( ClientHandshakeKeyUnavailable
  | ClientHandshakeResponseTooLarge
  | ClientHandshakeInvalidHTTP
  | ClientHandshakeUnexpectedStatus
  | ClientHandshakeMissingUpgrade
  | ClientHandshakeMissingAccept
  | ClientHandshakeAcceptMismatch
  | ClientHandshakeAcceptKeyFailed
  | ClientHandshakeUnsolicitedSubprotocol
  | ClientHandshakeUnsolicitedExtension )

primitive ClientHandshakeKeyUnavailable is Stringable
  """
  A Sec-WebSocket-Key could not be generated, so no request was sent.

  Unlike the rest of this union, nothing arrived from the server — the
  failure is local. The CSPRNG could not produce secure bytes, and there is
  no safe fallback: a predictable key leaves the client unable to tell a
  completed handshake from a replayed response.
  """
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Could not generate Sec-WebSocket-Key".clone()

primitive ClientHandshakeResponseTooLarge is Stringable
  """The HTTP upgrade response exceeded the maximum allowed size."""
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Handshake response too large".clone()

primitive ClientHandshakeInvalidHTTP is Stringable
  """The HTTP status line was malformed or the version was not HTTP/1.1."""
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Invalid HTTP response".clone()

class val ClientHandshakeUnexpectedStatus is Stringable
  """
  The server answered with a status other than 101 Switching Protocols.

  This carries the status it did send, because the distinction matters to
  the caller: 401 means supply credentials, 3xx means the endpoint moved,
  5xx means retry later. The other errors in this union are all "the
  server agreed to upgrade but did it wrong", where there is nothing
  further to report.
  """
  let status: U16

  new val create(status': U16) =>
    """Create the error for a response that was not 101."""
    status = status'

  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    recover
      String(32)
        .>append("Unexpected HTTP status ")
        .>append(status.string())
    end

primitive ClientHandshakeMissingUpgrade is Stringable
  """
  The Upgrade or Connection header was missing or had an incorrect value.
  """
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Missing or invalid Upgrade/Connection headers".clone()

primitive ClientHandshakeMissingAccept is Stringable
  """The Sec-WebSocket-Accept header was missing."""
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Missing Sec-WebSocket-Accept header".clone()

primitive ClientHandshakeAcceptMismatch is Stringable
  """
  The Sec-WebSocket-Accept value did not match the key that was sent.

  A mismatch means the peer did not derive the value from our key, so it
  is not a WebSocket server completing our handshake — it may be a cache
  replaying an old response, or a proxy answering on its own.
  """
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Sec-WebSocket-Accept did not match the key sent".clone()

primitive ClientHandshakeAcceptKeyFailed is Stringable
  """
  The expected Sec-WebSocket-Accept value could not be computed.

  The response was well formed; the SHA-1 the accept value is built from
  could not be taken. Nothing about the server's answer was wrong.
  """
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Could not compute expected Sec-WebSocket-Accept".clone()

primitive ClientHandshakeUnsolicitedSubprotocol is Stringable
  """
  The server selected a subprotocol that was not offered.

  RFC 6455 Section 4.1 requires the client to fail the connection: the
  server has committed to a protocol the client never claimed to speak.
  """
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Server selected a subprotocol that was not offered".clone()

primitive ClientHandshakeUnsolicitedExtension is Stringable
  """
  The server selected an extension that was not offered.

  Mare offers no extensions, so any Sec-WebSocket-Extensions value in a
  response is unsolicited. Accepting one would mean agreeing to a framing
  the parser does not implement.
  """
  fun string(): String iso^ =>
    """Returns a human-readable description of this error."""
    "Server selected an extension that was not offered".clone()
