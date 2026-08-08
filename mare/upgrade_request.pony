class val UpgradeRequest
  """
  A parsed HTTP upgrade request from a WebSocket client.

  Provides access to the request URI and headers. Header lookups are
  case-insensitive per HTTP/1.1 (RFC 7230 Section 3.2).
  """
  let uri: String
  let _headers: Array[(String val, String val)] val

  new val create(uri': String, headers': Array[(String val, String val)] val) =>
    """
    Create an upgrade request with the given URI and headers.
    """
    uri = uri'
    _headers = headers'

  fun header(name: String): (String val | None) =>
    """
    Look up a header value by name (case-insensitive).

    Returns the first matching header value, or `None` if not found.
    Header names are stored pre-lowered by `_HandshakeParser`, so this
    only needs to lower the lookup key.
    """
    let lower: String val = name.lower()
    for (k, v) in _headers.values() do
      if k == lower then
        return v
      end
    end
    None
