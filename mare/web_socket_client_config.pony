class val WebSocketClientConfig
  """
  Immutable configuration for a WebSocket client connection.

  The target host and port are arguments to `WebSocketClient`'s
  constructor rather than fields here: lori needs them to open the
  connection, and the `Host` header is derived from them, so holding them
  in two places would let them disagree.

  All fields have sensible defaults. Create with named arguments to
  override specific values:

  ```pony
  let config = WebSocketClientConfig(where
    path' = "/socket",
    subprotocols' = recover val ["chat"] end)
  ```
  """
  let path: String
  let origin: (String val | None)
  let subprotocols: Array[String val] val
  let headers: Array[(String val, String val)] val
  let max_message_size: USize
  let max_handshake_size: USize

  new val create(
    path': String = "/",
    origin': (String val | None) = None,
    subprotocols': Array[String val] val = recover val Array[String val] end,
    headers': Array[(String val, String val)] val =
      recover val Array[(String val, String val)] end,
    max_message_size': USize = 1_048_576,
    max_handshake_size': USize = 8192)
  =>
    """
    Create WebSocket client configuration with optional overrides.

    `path` is the request target of the upgrade request. `origin` sets an
    `Origin` header when present. `subprotocols` are offered in
    `Sec-WebSocket-Protocol`; a server that selects one outside this list
    fails the handshake. `headers` are sent verbatim, which is where
    credentials belong.
    """
    path = path'
    origin = origin'
    subprotocols = subprotocols'
    headers = headers'
    max_message_size = max_message_size'
    max_handshake_size = max_handshake_size'
