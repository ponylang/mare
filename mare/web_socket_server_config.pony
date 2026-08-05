class val WebSocketServerConfig
  """
  Immutable configuration for a WebSocket connection.

  All fields have sensible defaults. Create with named arguments to
  override specific values:

  ```pony
  let config = WebSocketServerConfig(where
    host' = "0.0.0.0",
    port' = "9090",
    max_message_size' = 4_194_304)
  ```
  """
  let host: String
  let port: String
  let max_message_size: USize
  let max_handshake_size: USize

  new val create(
    host': String = "localhost",
    port': String = "8080",
    max_message_size': USize = 1_048_576,
    max_handshake_size': USize = 8192)
  =>
    """Create WebSocket configuration with optional overrides."""
    host = host'
    port = port'
    max_message_size = max_message_size'
    max_handshake_size = max_handshake_size'
