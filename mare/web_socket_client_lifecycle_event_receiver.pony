use lori = "lori"

trait WebSocketClientLifecycleEventReceiver
  """
  WebSocket lifecycle callbacks delivered to the connection actor.

  All callbacks have default no-op implementations. Override only the
  callbacks your actor needs. For most clients, `on_open()` is where you
  start sending and `on_text_message()` or `on_binary_message()` is the
  main callback — it delivers complete, reassembled messages after all
  fragments are received and validated.

  This is the client counterpart to
  `WebSocketServerLifecycleEventReceiver`. It has no `on_upgrade_request()`,
  since a client is the side making the request, and it adds two failure
  callbacks the server side has no analogue for: `on_connection_failure()`
  when the connection never opens, and `on_handshake_failure()` when TCP
  connected but the server's upgrade response was unacceptable.

  Callbacks are invoked synchronously inside the actor that owns the
  `WebSocketClient`. The protocol class handles the handshake, framing,
  masking, fragmentation, and the close handshake internally, delivering
  only application-level events through this interface.
  """

  fun ref on_connection_failure(reason: lori.ConnectionFailureReason) =>
    """
    Called when the connection could not be established.

    `reason` identifies the stage that failed — name resolution, TCP,
    the TLS handshake, or the connection timeout. The WebSocket handshake
    was never attempted, so `on_closed()` does not follow.
    """
    None

  fun ref on_handshake_failure(err: ClientHandshakeError) =>
    """
    Called when the server's upgrade response was not acceptable.

    The TCP connection was established but the WebSocket handshake did not
    complete, so the connection is failed without a close handshake —
    there is no open WebSocket to close. `on_open()` is never delivered.
    """
    None

  fun ref on_open(response: UpgradeResponse val) =>
    """
    Called after the WebSocket handshake completes successfully.

    `response` carries the server's upgrade response, which is where a
    selected subprotocol would appear.
    """
    None

  fun ref on_text_message(data: String val) =>
    """Called when a complete text message is received."""
    None

  fun ref on_binary_message(data: Array[U8] val) =>
    """Called when a complete binary message is received."""
    None

  fun ref on_closed(
    close_status: CloseStatus,
    close_reason: String val)
  =>
    """
    Called when the WebSocket connection closes.

    `close_status` indicates why the connection closed — a named primitive
    for standard codes (e.g., `CloseNormal`), `CloseNoStatusReceived` when
    the close frame had no payload, `CloseAbnormalClosure` when TCP dropped
    without a close handshake, or `OtherCloseCode` for application-defined
    or IANA-registered codes without named primitives.

    `close_reason` is the UTF-8 reason string from the close frame, or
    empty when no reason was provided or the close was abnormal.
    """
    None

  fun ref on_throttled() =>
    """Called when backpressure is applied on the connection."""
    None

  fun ref on_unthrottled() =>
    """Called when backpressure is released on the connection."""
    None

  fun ref on_idle_timeout() =>
    """Called when the connection's idle timeout fires."""
    None
