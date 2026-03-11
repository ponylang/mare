trait WebSocketLifecycleEventReceiver
  """
  WebSocket lifecycle callbacks delivered to the connection actor.

  All callbacks have default no-op implementations. Override only the
  callbacks your actor needs. For most servers, `on_text_message()` or
  `on_binary_message()` is the main callback — it delivers complete,
  reassembled messages after all fragments are received and validated.

  Override `on_upgrade_request()` to inspect the HTTP upgrade request
  before accepting the connection (e.g., checking the URI path or
  Origin header). Return `false` to reject with 403 Forbidden.

  Callbacks are invoked synchronously inside the actor that owns the
  `WebSocketServer`. The protocol class handles framing, masking,
  fragmentation, and the close handshake internally, delivering only
  application-level events through this interface.
  """

  fun ref on_upgrade_request(request: UpgradeRequest val): Bool =>
    """
    Called when a valid upgrade request is received, before the
    connection is accepted.

    Return `true` to accept (sends 101 Switching Protocols) or `false`
    to reject (sends 403 Forbidden and closes TCP). The default
    implementation accepts all connections.
    """
    true

  fun ref on_open(request: UpgradeRequest val) =>
    """Called after the WebSocket handshake completes successfully."""
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
