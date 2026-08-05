use lori = "lori"

trait tag WebSocketClientActor is
  (lori.TCPConnectionActor & WebSocketClientLifecycleEventReceiver)
  """
  Trait for actors that open WebSocket connections.

  Extends `TCPConnectionActor` (for lori ASIO plumbing) and
  `WebSocketClientLifecycleEventReceiver` (for WebSocket-level callbacks).
  The actor stores a `WebSocketClient` as a field and implements
  `_websocket()` to return it. All other required methods
  have default implementations that delegate to the protocol.

  Minimal implementation:

  ```pony
  actor MyHandler is WebSocketClientActor
    var _ws: WebSocketClient = WebSocketClient.none()

    new create(
      auth: lori.TCPConnectAuth,
      host: String,
      port: String,
      from: String,
      config: WebSocketClientConfig val)
    =>
      _ws = WebSocketClient(auth, host, port, from, this, config)

    fun ref _websocket(): WebSocketClient => _ws

    fun ref on_open(response: UpgradeResponse val) =>
      _ws.send_text("hello")  // the connection is ready to use
  ```
  """

  fun ref _websocket(): WebSocketClient
    """Return the protocol instance owned by this actor."""

  fun ref _connection(): lori.TCPConnection =>
    """Delegates to the protocol's TCP connection."""
    _websocket()._connection()
