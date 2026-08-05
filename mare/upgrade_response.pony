class val UpgradeResponse
  """
  A parsed HTTP upgrade response from a WebSocket server.

  Provides access to the response status code and headers. Header lookups
  are case-insensitive per HTTP/1.1 (RFC 7230 Section 3.2).

  A response only reaches the application when the handshake succeeded, so
  `status` is always 101. It is kept because the response is otherwise
  opaque, and because a server may report a selected subprotocol or
  extension alongside it.
  """
  let status: U16
  let _headers: Array[(String val, String val)] val

  new val create(
    status': U16,
    headers': Array[(String val, String val)] val)
  =>
    """Create an upgrade response with the given status and headers."""
    status = status'
    _headers = headers'

  fun header(name: String): (String val | None) =>
    """
    Look up a header value by name (case-insensitive).

    Returns the first matching header value, or `None` if not found.
    Header names are stored pre-lowered by the response parser, so this
    only needs to lower the lookup key.
    """
    let lower: String val = name.lower()
    for (k, v) in _headers.values() do
      if k == lower then
        return v
      end
    end
    None
