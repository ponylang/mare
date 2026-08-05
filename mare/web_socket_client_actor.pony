use lori = "lori"

trait tag WebSocketClientActor is
  (lori.TCPConnectionActor & WebSocketLifecycleEventReceiver)
  """
  Trait for actors that serve WebSocket connections.

  Extends `TCPConnectionActor` (for lori ASIO plumbing) and
  `WebSocketLifecycleEventReceiver` (for WebSocket-level callbacks).
  The actor stores a `WebSocketClient` as a field and implements
  `_websocket()` to return it. All other required methods
  have default implementations that delegate to the protocol.

  Minimal implementation:

  ```pony
  actor MyHandler is WebSocketClientActor
    var _ws: WebSocketClient = WebSocketClient.none()

    new create(auth: lori.TCPConnectAuth, fd: U32,
      config: WebSocketConfig)
    =>
      _ws = WebSocketClient(auth, fd, this, config)

    fun ref _websocket(): WebSocketClient => _ws

    fun ref on_text_message(data: String val) =>
      _ws.send_text(data)  // echo back
  ```
  """

  fun ref _websocket(): WebSocketClient
    """Return the protocol instance owned by this actor."""

  fun ref _connection(): lori.TCPConnection =>
    """Delegates to the protocol's TCP connection."""
    _websocket()._connection()
