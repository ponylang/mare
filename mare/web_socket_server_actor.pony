use lori = "lori"

trait tag WebSocketServerActor is
  (lori.TCPConnectionActor & WebSocketLifecycleEventReceiver)
  """
  Trait for actors that serve WebSocket connections.

  Extends `TCPConnectionActor` (for lori ASIO plumbing) and
  `WebSocketLifecycleEventReceiver` (for WebSocket-level callbacks).
  The actor stores a `WebSocketServer` as a field and implements
  `_websocket()` to return it. All other required methods
  have default implementations that delegate to the protocol.

  Minimal implementation:

  ```pony
  actor MyHandler is WebSocketServerActor
    var _ws: WebSocketServer = WebSocketServer.none()

    new create(auth: lori.TCPServerAuth, fd: U32,
      config: WebSocketConfig)
    =>
      _ws = WebSocketServer(auth, fd, this, config)

    fun ref _websocket(): WebSocketServer => _ws

    fun ref on_text_message(data: String val) =>
      _ws.send_text(data)  // echo back
  ```
  """

  fun ref _websocket(): WebSocketServer
    """
    Return the protocol instance owned by this actor.
    """

  fun ref _connection(): lori.TCPConnection =>
    """
    Delegates to the protocol's TCP connection.
    """
    _websocket()._connection()
