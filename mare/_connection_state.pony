use lori = "lori"

type Node is (WebSocketServer | WebSocketClient)

trait val _ConnectionState[A: Node ref]
  """
  Connection lifecycle state.

  Dispatches WebSocket events to the appropriate methods based on
  what operations are valid in each state. Four states:
  `_Handshaking` (parsing HTTP upgrade), `_Open` (exchanging messages),
  `_Closing` (initiated close, awaiting response from the other side), and
  `_Closed` (all operations are no-ops).
  """

  fun on_received(node: A, data: Array[U8] iso)
    """Handle incoming data from the TCP connection."""

  fun on_closed(node: A)
    """Handle connection close notification."""

  fun on_throttled(node: A)
    """Handle backpressure applied notification."""

  fun on_unthrottled(node: A)
    """Handle backpressure released notification."""

  fun on_sent(node: A, token: lori.SendToken)
    """Handle send completion notification from lori."""

  fun on_idle_timeout(node: A)
    """Handle connection going idle."""

  fun send_text(node: A, data: String val)
    """Send a text message."""

  fun send_binary(node: A, data: Array[U8] val)
    """Send a binary message."""

  fun close(
    node: A,
    code: CloseCode,
    reason: String val)
    """Initiate a close handshake."""

primitive _Handshaking[A: Node ref] is _ConnectionState[A]
  """Parsing the HTTP upgrade request. No WebSocket messages yet."""

  fun on_received(node: A, data: Array[U8] iso) =>
    node._feed_handshake(consume data)

  fun on_closed(node: A) =>
    // Handshake never completed — no user callbacks
    node._set_state(_Closed[A])

  fun on_throttled(node: A) => None
  fun on_unthrottled(node: A) => None
  fun on_sent(node: A, token: lori.SendToken) => None
  fun on_idle_timeout(node: A) => None
  fun send_text(node: A, data: String val) => None
  fun send_binary(node: A, data: Array[U8] val) => None

  fun close(
    node: A,
    code: CloseCode,
    reason: String val)
  =>
    None

primitive _Open[A: Node ref] is _ConnectionState[A]
  """WebSocket connection is open — exchanging messages."""

  fun on_received(node: A, data: Array[U8] iso) =>
    node._feed_frames(consume data)

  fun on_closed(node: A) =>
    // Abnormal TCP close
    node._fire_on_closed(CloseAbnormalClosure, "")
    node._set_state(_Closed[A])

  fun on_throttled(node: A) =>
    node._fire_on_throttled()

  fun on_unthrottled(node: A) =>
    node._fire_on_unthrottled()

  fun on_sent(node: A, token: lori.SendToken) => None

  fun on_idle_timeout(node: WebSocketServer ref) =>
    node._fire_on_idle_timeout()

  fun send_text(node: A, data: String val) =>
    node._send_frame(_FrameEncoder.text(data))

  fun send_binary(node: A, data: Array[U8] val) =>
    node._send_frame(_FrameEncoder.binary(data))

  fun close(
    node: A,
    code: CloseCode,
    reason: String val)
  =>
    node._send_frame(_FrameEncoder.close(code, reason))
    node._set_state(_Closing[A])

primitive _Closing[A: Node ref] is _ConnectionState[A]
  """
  Server initiated close, waiting for client's close response.

  Data frames are discarded. Control frames are still processed:
  ping gets a pong, pong is ignored, close completes the handshake.
  """

  fun on_received(node: A, data: Array[U8] iso) =>
    node._feed_frames_closing(consume data)

  fun on_closed(node: A) =>
    // TCP dropped before close response
    node._fire_on_closed(CloseAbnormalClosure, "")
    node._set_state(_Closed[A])

  fun on_throttled(node: A) => None
  fun on_unthrottled(node: A) => None
  fun on_sent(node: A, token: lori.SendToken) => None
  fun on_idle_timeout(node: A) => None
  fun send_text(node: A, data: String val) => None
  fun send_binary(node: A, data: Array[U8] val) => None

  fun close(
    node: A,
    code: CloseCode,
    reason: String val)
  =>
    None

primitive _Closed[A: Node ref] is _ConnectionState[A]
  """Connection is closed — all operations are no-ops."""

  fun on_received(node: A, data: Array[U8] iso) => None
  fun on_closed(node: A) => None
  fun on_throttled(node: A) => None
  fun on_unthrottled(node: A) => None
  fun on_sent(node: A, token: lori.SendToken) => None
  fun on_idle_timeout(node: A) => None
  fun send_text(node: A, data: String val) => None
  fun send_binary(node: A, data: Array[U8] val) => None

  fun close(
    node: A,
    code: CloseCode,
    reason: String val)
  =>
    None
