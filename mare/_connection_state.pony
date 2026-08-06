use lori = "lori"

trait ref _WebSocketNode
  """
  The protocol handler surface that connection states drive.

  Both `WebSocketServer` and `WebSocketClient` implement this trait, which
  is what lets them share one set of state primitives. The states only ever
  reach a handler through this trait, so each side is free to give these
  methods a direction-appropriate meaning: `_feed_handshake` parses an
  upgrade request on the server and an upgrade response on the client, and
  the `_send_*` methods mask on the client but not on the server.

  Every method is abstract. None gets a default body, because a default
  here would be a no-op: an implementer who omitted one would silently
  stop sending rather than fail to compile.
  """

  fun ref _set_state(state: _ConnectionState)
    """Transition to a new connection state."""

  fun ref _feed_handshake(data: Array[U8] iso)
    """Process incoming data during the handshake phase."""

  fun ref _feed_frames(data: Array[U8] iso)
    """Process incoming frame data in the Open state."""

  fun ref _feed_frames_closing(data: Array[U8] iso)
    """Process incoming frame data in the Closing state."""

  fun ref _send_text(data: String val)
    """Encode and send a text message."""

  fun ref _send_binary(data: Array[U8] val)
    """Encode and send a binary message."""

  fun ref _send_ping(payload: Array[U8] val)
    """Encode and send a ping."""

  fun ref _close(code: CloseCode, reason: String val)
    """Send a close frame and await the peer's response."""

  fun ref _fire_on_closed(
    close_status: CloseStatus,
    close_reason: String val)
    """Deliver the close event to the lifecycle event receiver."""

  fun ref _fire_on_throttled()
    """Deliver the backpressure applied event."""

  fun ref _fire_on_unthrottled()
    """Deliver the backpressure released event."""

  fun ref _fire_on_idle_timeout()
    """Deliver the idle timeout event."""

trait val _ConnectionState
  """
  Connection lifecycle state.

  Dispatches WebSocket events to the appropriate handler methods based on
  what operations are valid in each state. Four states:
  `_Handshaking` (exchanging the HTTP upgrade), `_Open` (exchanging
  messages), `_Closing` (this side initiated a close and is awaiting the
  peer's response), and `_Closed` (all operations are no-ops).

  States are shared between the server and the client. They take a
  `_WebSocketNode` rather than a concrete handler, so one set of primitives
  serves both directions.
  """

  fun on_received(node: _WebSocketNode ref, data: Array[U8] iso)
    """Handle incoming data from the TCP connection."""

  fun on_closed(node: _WebSocketNode ref)
    """Handle connection close notification."""

  fun on_throttled(node: _WebSocketNode ref)
    """Handle backpressure applied notification."""

  fun on_unthrottled(node: _WebSocketNode ref)
    """Handle backpressure released notification."""

  fun on_sent(node: _WebSocketNode ref, token: lori.SendToken)
    """Handle send completion notification from lori."""

  fun on_idle_timeout(node: _WebSocketNode ref)
    """Handle connection going idle."""

  fun send_text(node: _WebSocketNode ref, data: String val)
    """Send a text message."""

  fun send_binary(node: _WebSocketNode ref, data: Array[U8] val)
    """Send a binary message."""

  fun send_ping(node: _WebSocketNode ref, payload: Array[U8] val)
    """Send a ping."""

  fun close(
    node: _WebSocketNode ref,
    code: CloseCode,
    reason: String val)
    """Initiate a close handshake."""

primitive _Connecting is _ConnectionState
  """
  Waiting for TCP to open. Client side only.

  A server is handed an already-connected socket, so it never enters this
  state. Sends are dropped rather than queued: there is no socket to write
  to yet, which matches what `_send_frame` does under backpressure.
  """

  fun on_received(node: _WebSocketNode ref, data: Array[U8] iso) => None

  fun on_closed(node: _WebSocketNode ref) =>
    // Never connected — no user callbacks
    node._set_state(_Closed)

  fun on_throttled(node: _WebSocketNode ref) => None
  fun on_unthrottled(node: _WebSocketNode ref) => None
  fun on_sent(node: _WebSocketNode ref, token: lori.SendToken) => None
  fun on_idle_timeout(node: _WebSocketNode ref) => None
  fun send_text(node: _WebSocketNode ref, data: String val) => None
  fun send_binary(node: _WebSocketNode ref, data: Array[U8] val) => None
  fun send_ping(node: _WebSocketNode ref, payload: Array[U8] val) => None

  fun close(
    node: _WebSocketNode ref,
    code: CloseCode,
    reason: String val)
  =>
    None

primitive _Handshaking is _ConnectionState
  """Exchanging the HTTP upgrade. No WebSocket messages yet."""

  fun on_received(node: _WebSocketNode ref, data: Array[U8] iso) =>
    node._feed_handshake(consume data)

  fun on_closed(node: _WebSocketNode ref) =>
    // Handshake never completed — no user callbacks
    node._set_state(_Closed)

  fun on_throttled(node: _WebSocketNode ref) => None
  fun on_unthrottled(node: _WebSocketNode ref) => None
  fun on_sent(node: _WebSocketNode ref, token: lori.SendToken) => None
  fun on_idle_timeout(node: _WebSocketNode ref) => None
  fun send_text(node: _WebSocketNode ref, data: String val) => None
  fun send_binary(node: _WebSocketNode ref, data: Array[U8] val) => None
  fun send_ping(node: _WebSocketNode ref, payload: Array[U8] val) => None

  fun close(
    node: _WebSocketNode ref,
    code: CloseCode,
    reason: String val)
  =>
    None

primitive _Open is _ConnectionState
  """WebSocket connection is open — exchanging messages."""

  fun on_received(node: _WebSocketNode ref, data: Array[U8] iso) =>
    node._feed_frames(consume data)

  fun on_closed(node: _WebSocketNode ref) =>
    // Abnormal TCP close
    node._fire_on_closed(CloseAbnormalClosure, "")
    node._set_state(_Closed)

  fun on_throttled(node: _WebSocketNode ref) =>
    node._fire_on_throttled()

  fun on_unthrottled(node: _WebSocketNode ref) =>
    node._fire_on_unthrottled()

  fun on_sent(node: _WebSocketNode ref, token: lori.SendToken) => None

  fun on_idle_timeout(node: _WebSocketNode ref) =>
    node._fire_on_idle_timeout()

  fun send_text(node: _WebSocketNode ref, data: String val) =>
    node._send_text(data)

  fun send_binary(node: _WebSocketNode ref, data: Array[U8] val) =>
    node._send_binary(data)

  fun send_ping(node: _WebSocketNode ref, payload: Array[U8] val) =>
    node._send_ping(payload)

  fun close(node: _WebSocketNode ref, code: CloseCode, reason: String val) =>
    node._close(code, reason)

primitive _Closing is _ConnectionState
  """
  This side initiated a close, waiting for the peer's close response.

  Data frames are discarded. Control frames are still processed:
  ping gets a pong, pong is ignored, close completes the handshake.
  """

  fun on_received(node: _WebSocketNode ref, data: Array[U8] iso) =>
    node._feed_frames_closing(consume data)

  fun on_closed(node: _WebSocketNode ref) =>
    // TCP dropped before close response
    node._fire_on_closed(CloseAbnormalClosure, "")
    node._set_state(_Closed)

  fun on_throttled(node: _WebSocketNode ref) => None
  fun on_unthrottled(node: _WebSocketNode ref) => None
  fun on_sent(node: _WebSocketNode ref, token: lori.SendToken) => None
  fun on_idle_timeout(node: _WebSocketNode ref) => None
  fun send_text(node: _WebSocketNode ref, data: String val) => None
  fun send_binary(node: _WebSocketNode ref, data: Array[U8] val) => None
  fun send_ping(node: _WebSocketNode ref, payload: Array[U8] val) => None

  fun close(
    node: _WebSocketNode ref,
    code: CloseCode,
    reason: String val)
  =>
    None

primitive _Closed is _ConnectionState
  """Connection is closed — all operations are no-ops."""

  fun on_received(node: _WebSocketNode ref, data: Array[U8] iso) => None
  fun on_closed(node: _WebSocketNode ref) => None
  fun on_throttled(node: _WebSocketNode ref) => None
  fun on_unthrottled(node: _WebSocketNode ref) => None
  fun on_sent(node: _WebSocketNode ref, token: lori.SendToken) => None
  fun on_idle_timeout(node: _WebSocketNode ref) => None
  fun send_text(node: _WebSocketNode ref, data: String val) => None
  fun send_binary(node: _WebSocketNode ref, data: Array[U8] val) => None
  fun send_ping(node: _WebSocketNode ref, payload: Array[U8] val) => None

  fun close(
    node: _WebSocketNode ref,
    code: CloseCode,
    reason: String val)
  =>
    None
