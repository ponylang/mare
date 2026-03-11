use lori = "lori"

trait val _ConnectionState
  """
  Connection lifecycle state.

  Dispatches WebSocket events to the appropriate server methods based on
  what operations are valid in each state. Four states:
  `_Handshaking` (parsing HTTP upgrade), `_Open` (exchanging messages),
  `_Closing` (server initiated close, awaiting client response), and
  `_Closed` (all operations are no-ops).
  """

  fun on_received(server: WebSocketServer ref, data: Array[U8] iso)
    """Handle incoming data from the TCP connection."""

  fun on_closed(server: WebSocketServer ref)
    """Handle connection close notification."""

  fun on_throttled(server: WebSocketServer ref)
    """Handle backpressure applied notification."""

  fun on_unthrottled(server: WebSocketServer ref)
    """Handle backpressure released notification."""

  fun on_sent(server: WebSocketServer ref, token: lori.SendToken)
    """Handle send completion notification from lori."""

  fun on_idle_timeout(server: WebSocketServer ref)
    """Handle connection going idle."""

  fun send_text(server: WebSocketServer ref, data: String val)
    """Send a text message."""

  fun send_binary(server: WebSocketServer ref, data: Array[U8] val)
    """Send a binary message."""

  fun close(
    server: WebSocketServer ref,
    code: CloseCode,
    reason: String val)
    """Initiate a close handshake."""

primitive _Handshaking is _ConnectionState
  """Parsing the HTTP upgrade request. No WebSocket messages yet."""

  fun on_received(server: WebSocketServer ref, data: Array[U8] iso) =>
    server._feed_handshake(consume data)

  fun on_closed(server: WebSocketServer ref) =>
    // Handshake never completed — no user callbacks
    server._set_state(_Closed)

  fun on_throttled(server: WebSocketServer ref) => None
  fun on_unthrottled(server: WebSocketServer ref) => None
  fun on_sent(server: WebSocketServer ref, token: lori.SendToken) => None
  fun on_idle_timeout(server: WebSocketServer ref) => None
  fun send_text(server: WebSocketServer ref, data: String val) => None
  fun send_binary(server: WebSocketServer ref, data: Array[U8] val) => None

  fun close(
    server: WebSocketServer ref,
    code: CloseCode,
    reason: String val)
  =>
    None

primitive _Open is _ConnectionState
  """WebSocket connection is open — exchanging messages."""

  fun on_received(server: WebSocketServer ref, data: Array[U8] iso) =>
    server._feed_frames(consume data)

  fun on_closed(server: WebSocketServer ref) =>
    // Abnormal TCP close
    server._fire_on_closed(CloseAbnormalClosure, "")
    server._set_state(_Closed)

  fun on_throttled(server: WebSocketServer ref) =>
    server._fire_on_throttled()

  fun on_unthrottled(server: WebSocketServer ref) =>
    server._fire_on_unthrottled()

  fun on_sent(server: WebSocketServer ref, token: lori.SendToken) => None

  fun on_idle_timeout(server: WebSocketServer ref) =>
    server._fire_on_idle_timeout()

  fun send_text(server: WebSocketServer ref, data: String val) =>
    server._send_frame(_FrameEncoder.text(data))

  fun send_binary(server: WebSocketServer ref, data: Array[U8] val) =>
    server._send_frame(_FrameEncoder.binary(data))

  fun close(
    server: WebSocketServer ref,
    code: CloseCode,
    reason: String val)
  =>
    server._send_frame(_FrameEncoder.close(code, reason))
    server._set_state(_Closing)

primitive _Closing is _ConnectionState
  """
  Server initiated close, waiting for client's close response.

  Data frames are discarded. Control frames are still processed:
  ping gets a pong, pong is ignored, close completes the handshake.
  """

  fun on_received(server: WebSocketServer ref, data: Array[U8] iso) =>
    server._feed_frames_closing(consume data)

  fun on_closed(server: WebSocketServer ref) =>
    // TCP dropped before close response
    server._fire_on_closed(CloseAbnormalClosure, "")
    server._set_state(_Closed)

  fun on_throttled(server: WebSocketServer ref) => None
  fun on_unthrottled(server: WebSocketServer ref) => None
  fun on_sent(server: WebSocketServer ref, token: lori.SendToken) => None
  fun on_idle_timeout(server: WebSocketServer ref) => None
  fun send_text(server: WebSocketServer ref, data: String val) => None
  fun send_binary(server: WebSocketServer ref, data: Array[U8] val) => None

  fun close(
    server: WebSocketServer ref,
    code: CloseCode,
    reason: String val)
  =>
    None

primitive _Closed is _ConnectionState
  """Connection is closed — all operations are no-ops."""

  fun on_received(server: WebSocketServer ref, data: Array[U8] iso) => None
  fun on_closed(server: WebSocketServer ref) => None
  fun on_throttled(server: WebSocketServer ref) => None
  fun on_unthrottled(server: WebSocketServer ref) => None
  fun on_sent(server: WebSocketServer ref, token: lori.SendToken) => None
  fun on_idle_timeout(server: WebSocketServer ref) => None
  fun send_text(server: WebSocketServer ref, data: String val) => None
  fun send_binary(server: WebSocketServer ref, data: Array[U8] val) => None

  fun close(
    server: WebSocketServer ref,
    code: CloseCode,
    reason: String val)
  =>
    None
