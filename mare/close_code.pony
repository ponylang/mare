// WebSocket close status codes defined in RFC 6455 Section 7.4.1.
type CloseCode is
  ( CloseNormal
  | CloseGoingAway
  | CloseProtocolError
  | CloseUnsupportedData
  | CloseInvalidPayload
  | ClosePolicyViolation
  | CloseMessageTooBig
  | CloseInternalError )

primitive CloseNormal is Stringable
  """
  Normal closure (1000). The connection fulfilled its purpose.
  """

  fun code(): U16 =>
    """
    Returns the RFC 6455 numeric close code.
    """
    1000

  fun string(): String iso^ =>
    """
    Returns a human-readable representation including the code and name.
    """
    "1000 Normal Closure".clone()

primitive CloseGoingAway is Stringable
  """
  Going away (1001). The endpoint is shutting down.
  """

  fun code(): U16 =>
    """
    Returns the RFC 6455 numeric close code.
    """
    1001

  fun string(): String iso^ =>
    """
    Returns a human-readable representation including the code and name.
    """
    "1001 Going Away".clone()

primitive CloseProtocolError is Stringable
  """
  Protocol error (1002). A protocol violation was detected.
  """

  fun code(): U16 =>
    """
    Returns the RFC 6455 numeric close code.
    """
    1002

  fun string(): String iso^ =>
    """
    Returns a human-readable representation including the code and name.
    """
    "1002 Protocol Error".clone()

primitive CloseUnsupportedData is Stringable
  """
  Unsupported data (1003). An unsupported data type was received.
  """

  fun code(): U16 =>
    """
    Returns the RFC 6455 numeric close code.
    """
    1003

  fun string(): String iso^ =>
    """
    Returns a human-readable representation including the code and name.
    """
    "1003 Unsupported Data".clone()

primitive CloseInvalidPayload is Stringable
  """
  Invalid payload (1007). A message payload was not valid.
  """

  fun code(): U16 =>
    """
    Returns the RFC 6455 numeric close code.
    """
    1007

  fun string(): String iso^ =>
    """
    Returns a human-readable representation including the code and name.
    """
    "1007 Invalid Payload".clone()

primitive ClosePolicyViolation is Stringable
  """
  Policy violation (1008). A policy was violated.
  """

  fun code(): U16 =>
    """
    Returns the RFC 6455 numeric close code.
    """
    1008

  fun string(): String iso^ =>
    """
    Returns a human-readable representation including the code and name.
    """
    "1008 Policy Violation".clone()

primitive CloseMessageTooBig is Stringable
  """
  Message too big (1009). A message exceeded the size limit.
  """

  fun code(): U16 =>
    """
    Returns the RFC 6455 numeric close code.
    """
    1009

  fun string(): String iso^ =>
    """
    Returns a human-readable representation including the code and name.
    """
    "1009 Message Too Big".clone()

primitive CloseInternalError is Stringable
  """
  Internal error (1011). An unexpected server error occurred.
  """

  fun code(): U16 =>
    """
    Returns the RFC 6455 numeric close code.
    """
    1011

  fun string(): String iso^ =>
    """
    Returns a human-readable representation including the code and name.
    """
    "1011 Internal Error".clone()
