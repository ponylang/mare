use lori = "lori"
use ssl_net = "ssl/net"

class WebSocketServer is lori.ServerLifecycleEventReceiver
  """
  WebSocket protocol handler that manages handshaking, framing, and
  connection lifecycle for a single WebSocket connection.

  This class is NOT an actor — it lives inside the user's actor and
  handles protocol details. The user's actor implements
  `WebSocketServerActor` and stores this class as a field.

  Use `none()` as the field default so that `this` is `ref` in the
  actor constructor body, then replace with `create()` or `ssl()`:

  ```pony
  actor MyHandler is WebSocketServerActor
    var _ws: WebSocketServer = WebSocketServer.none()

    new create(auth: lori.TCPServerAuth, fd: U32,
      config: WebSocketConfig val)
    =>
      _ws = WebSocketServer(auth, fd, this, config)

    fun ref _websocket(): WebSocketServer => _ws
  ```
  """
  let _lifecycle_event_receiver: (WebSocketLifecycleEventReceiver ref | None)
  let _config: (WebSocketConfig val | None)
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  var _state: _ConnectionState = _Closed
  var _handshake_parser: _HandshakeParser = _HandshakeParser
  var _frame_parser: _FrameParser = _FrameParser
  var _reassembler: _FragmentReassembler = _FragmentReassembler

  new none() =>
    """
    Create a placeholder protocol instance.

    Used as the default value for the `_ws` field in
    `WebSocketServerActor` implementations, allowing `this` to be `ref`
    in the actor constructor body. The placeholder is immediately
    replaced by `create()` or `ssl()` — its methods must never be
    called.
    """
    _lifecycle_event_receiver = None
    _config = None

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    server_actor: WebSocketServerActor ref,
    config: WebSocketConfig val)
  =>
    """Create a plain WebSocket (WS) connection handler."""
    _lifecycle_event_receiver = server_actor
    _config = config
    _state = _Handshaking
    _tcp_connection =
      lori.TCPConnection.server(auth, fd, server_actor, this)

  new ssl(
    auth: lori.TCPServerAuth,
    ssl_ctx: ssl_net.SSLContext val,
    fd: U32,
    server_actor: WebSocketServerActor ref,
    config: WebSocketConfig val)
  =>
    """Create a secure WebSocket (WSS) connection handler."""
    _lifecycle_event_receiver = server_actor
    _config = config
    _state = _Handshaking
    _tcp_connection =
      lori.TCPConnection.ssl_server(
        auth, ssl_ctx, fd, server_actor, this)

  // -- Public send API --

  fun ref send_text(data: String val) =>
    """Send a text message to the client."""
    _state.send_text(this, data)

  fun ref send_binary(data: Array[U8] val) =>
    """Send a binary message to the client."""
    _state.send_binary(this, data)

  fun ref close(
    code: CloseCode = CloseNormal,
    reason: String val = "")
  =>
    """
    Initiate a close handshake with the client.

    Sends a close frame and transitions to the Closing state. The
    connection will close after the client responds with its own close
    frame, or if TCP drops.
    """
    _state.close(this, code, reason)

  // -- lori ServerLifecycleEventReceiver --

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_started() => None

  fun ref _on_received(data: Array[U8] iso) =>
    _state.on_received(this, consume data)

  fun ref _on_closed() =>
    _state.on_closed(this)

  fun ref _on_start_failure() =>
    _state = _Closed

  fun ref _on_throttled() =>
    _state.on_throttled(this)

  fun ref _on_unthrottled() =>
    _state.on_unthrottled(this)

  fun ref _on_sent(token: lori.SendToken) =>
    _state.on_sent(this, token)

  fun ref _on_send_failed(token: lori.SendToken) => None

  fun ref _on_idle_timeout() =>
    _state.on_idle_timeout(this)

  fun ref _on_tls_ready() => None

  fun ref _on_tls_failure() => None

  // -- Internal methods called by state classes --

  fun ref _set_state(state: _ConnectionState) =>
    """Transition to a new connection state."""
    _state = state

  fun ref _feed_handshake(data: Array[U8] iso) =>
    """Process incoming data during the handshake phase."""
    let max_size = match \exhaustive\ _config
      | let c: WebSocketConfig val => c.max_handshake_size
      | None => _Unreachable(); return
      end

    match \exhaustive\ _handshake_parser(consume data, max_size)
    | _HandshakeNeedMore => None
    | let result: _HandshakeResult =>
      match \exhaustive\ _lifecycle_event_receiver
      | let r: WebSocketLifecycleEventReceiver ref =>
        if r.on_upgrade_request(result.request) then
          // Accept: send 101 response
          _send_101_response(result.accept_key)
          _state = _Open
          _fire_on_open(result.request)
          // Forward any remaining bytes to frame parser
          if result.remaining.size() > 0 then
            _feed_frames_from_val(result.remaining)
          end
        else
          // Reject: send 403 and close
          _send_http_error("403 Forbidden")
          _tcp_connection.close()
          _state = _Closed
        end
      | None => _Unreachable()
      end
    | let err: HandshakeError =>
      match err
      | HandshakeWrongVersion =>
        _send_http_error("426 Upgrade Required",
          "Sec-WebSocket-Version: 13\r\n")
      else
        _send_http_error("400 Bad Request")
      end
      _tcp_connection.close()
      _state = _Closed
    end

  fun ref _feed_frames(data: Array[U8] iso) =>
    """Process incoming frame data in the Open state."""
    let data_val: Array[U8] val = consume data
    _feed_frames_from_val(data_val)

  fun ref _feed_frames_from_val(data: Array[U8] val) =>
    """Process incoming frame data from a val array."""
    match \exhaustive\ _frame_parser.parse(data)
    | let frames: Array[_ParsedFrame val] val =>
      for frame in frames.values() do
        _dispatch_frame(frame)
        // Check if state changed to Closed during dispatch
        match _state
        | let _: _Closed => return
        end
      end
    | let err: _FrameError =>
      _send_frame(_FrameEncoder.close(err.code))
      _fire_on_closed(err.code, "")
      _tcp_connection.close()
      _state = _Closed
    end

  fun ref _feed_frames_closing(data: Array[U8] iso) =>
    """Process incoming frame data in the Closing state."""
    let data_val: Array[U8] val = consume data
    match \exhaustive\ _frame_parser.parse(data_val)
    | let frames: Array[_ParsedFrame val] val =>
      for frame in frames.values() do
        match frame.opcode
        | 0x08 =>
          // Close response received — complete the close handshake
          (let status, let reason) =
            _CloseStatusExtractor.from_payload(frame.payload)
          _fire_on_closed(status, reason)
          _tcp_connection.close()
          _state = _Closed
          return
        | 0x09 =>
          // Ping — still respond with pong during close
          _send_frame(_FrameEncoder.pong(frame.payload))
        | 0x0A => None // Pong — discard
        else
          None // Data frames — discard during closing
        end
      end
    | let err: _FrameError =>
      _fire_on_closed(err.code, "")
      _tcp_connection.close()
      _state = _Closed
    end

  fun ref _dispatch_frame(frame: _ParsedFrame val) =>
    """Dispatch a parsed frame by opcode in the Open state."""
    match frame.opcode
    | 0x09 =>
      // Ping — auto-respond with pong
      _send_frame(_FrameEncoder.pong(frame.payload))
    | 0x0A =>
      // Pong — discard
      None
    | 0x08 =>
      // Close — echo the client's close payload (status code + reason)
      if frame.payload.size() >= 2 then
        _send_frame(_FrameEncoder.close_payload(frame.payload))
      else
        _send_frame(_FrameEncoder.close_empty())
      end
      (let status, let reason) =
        _CloseStatusExtractor.from_payload(frame.payload)
      _fire_on_closed(status, reason)
      _tcp_connection.close()
      _state = _Closed
    else
      // Data frame (text, binary, continuation) — reassemble
      let max_size = match \exhaustive\ _config
        | let c: WebSocketConfig val => c.max_message_size
        | None => _Unreachable(); return
        end

      match \exhaustive\ _reassembler.frame(
        frame.fin, frame.opcode, frame.payload, max_size)
      | let msg: _CompleteMessage =>
        if msg.is_text then
          _fire_on_text(String.from_array(msg.data))
        else
          _fire_on_binary(msg.data)
        end
      | _FragmentContinue => None
      | let err: _ReassemblyError =>
        _send_frame(_FrameEncoder.close(err.code))
        _fire_on_closed(err.code, "")
        _tcp_connection.close()
        _state = _Closed
      end
    end

  fun ref _send_frame(data: Array[U8] val) =>
    """
    Send a framed WebSocket message over TCP.

    Ignores send errors: `SendErrorNotConnected` means the connection is
    already closing, `SendErrorNotWriteable` means backpressure. In both
    cases the frame is silently dropped — this matches v1 fire-and-forget
    send semantics.
    """
    _tcp_connection.send(data)

  fun ref _send_101_response(accept_key: String val) =>
    """Send the HTTP 101 Switching Protocols response."""
    let response: String val = recover val
      String(256)
        .>append("HTTP/1.1 101 Switching Protocols\r\n")
        .>append("Upgrade: websocket\r\n")
        .>append("Connection: Upgrade\r\n")
        .>append("Sec-WebSocket-Accept: ")
        .>append(accept_key)
        .>append("\r\n\r\n")
    end
    _tcp_connection.send(response)

  fun ref _send_http_error(
    status: String val,
    extra_headers: String val = "")
  =>
    """Send an HTTP error response and close."""
    let response: String val = recover val
      String(256)
        .>append("HTTP/1.1 ")
        .>append(status)
        .>append("\r\n")
        .>append(extra_headers)
        .>append("Content-Length: 0\r\n\r\n")
    end
    _tcp_connection.send(response)

  fun ref _fire_on_open(request: UpgradeRequest val) =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketLifecycleEventReceiver ref => r.on_open(request)
    | None => _Unreachable()
    end

  fun ref _fire_on_text(data: String val) =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketLifecycleEventReceiver ref => r.on_text_message(data)
    | None => _Unreachable()
    end

  fun ref _fire_on_binary(data: Array[U8] val) =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketLifecycleEventReceiver ref =>
      r.on_binary_message(data)
    | None => _Unreachable()
    end

  fun ref _fire_on_closed(
    close_status: CloseStatus,
    close_reason: String val)
  =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketLifecycleEventReceiver ref =>
      r.on_closed(close_status, close_reason)
    | None => _Unreachable()
    end

  fun ref _fire_on_throttled() =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketLifecycleEventReceiver ref => r.on_throttled()
    | None => _Unreachable()
    end

  fun ref _fire_on_unthrottled() =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketLifecycleEventReceiver ref => r.on_unthrottled()
    | None => _Unreachable()
    end
