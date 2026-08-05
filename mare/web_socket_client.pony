use lori = "lori"
use ssl_net = "ssl/net"

class WebSocketClient is
  (lori.ClientLifecycleEventReceiver & _WebSocketNode)
  """
  WebSocket protocol handler that manages handshaking, framing, and
  connection lifecycle for a single WebSocket connection.

  This class is NOT an actor — it lives inside the user's actor and
  handles protocol details. The user's actor implements
  `WebSocketClientActor` and stores this class as a field.

  Use `none()` as the field default so that `this` is `ref` in the
  actor constructor body, then replace with `create()` or `ssl()`:

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
  ```

  Unlike a server, which is handed an already-connected socket, a client
  opens the connection itself. lori connects asynchronously, so the
  upgrade request is not sent from the constructor — it goes out from
  `_on_connected()`, once there is a socket to write to.
  """
  let _lifecycle_event_receiver:
    (WebSocketClientLifecycleEventReceiver ref | None)
  let _config: (WebSocketClientConfig val | None)
  let _host: String
  let _port: String
  let _secure: Bool
  var _tcp_connection: lori.TCPConnection = lori.TCPConnection.none()
  var _state: _ConnectionState = _Closed
  var _handshake: (_ClientHandshake | None) = None
  var _frame_parser: _FrameParser = _FrameParser(where expect_masked = false)
  var _reassembler: _FragmentReassembler = _FragmentReassembler

  new none() =>
    """
    Create a placeholder protocol instance.

    Used as the default value for the `_ws` field in
    `WebSocketClientActor` implementations, allowing `this` to be `ref`
    in the actor constructor body. The placeholder is immediately
    replaced by `create()` or `ssl()` — its methods must never be
    called.
    """
    _lifecycle_event_receiver = None
    _config = None
    _host = ""
    _port = ""
    _secure = false

  new create(
    auth: lori.TCPConnectAuth,
    host: String,
    port: String,
    from: String,
    client_actor: WebSocketClientActor ref,
    config: WebSocketClientConfig val)
  =>
    """Create a plain WebSocket (WS) connection handler."""
    _lifecycle_event_receiver = client_actor
    _config = config
    _host = host
    _port = port
    _secure = false
    _state = _Connecting
    _tcp_connection =
      lori.TCPConnection.client(auth, host, port, from, client_actor, this)

  new ssl(
    auth: lori.TCPConnectAuth,
    ssl_ctx: ssl_net.SSLContext val,
    host: String,
    port: String,
    from: String,
    client_actor: WebSocketClientActor ref,
    config: WebSocketClientConfig val)
  =>
    """Create a secure WebSocket (WSS) connection handler."""
    _lifecycle_event_receiver = client_actor
    _config = config
    _host = host
    _port = port
    _secure = true
    _state = _Connecting
    _tcp_connection =
      lori.TCPConnection.ssl_client(
        auth, ssl_ctx, host, port, from, client_actor, this)

  // -- Public send API --

  fun ref send_text(data: String val) =>
    """Send a text message to the server."""
    _state.send_text(this, data)

  fun ref send_binary(data: Array[U8] val) =>
    """Send a binary message to the server."""
    _state.send_binary(this, data)

  fun ref close(
    code: CloseCode = CloseNormal,
    reason: String val = "")
  =>
    """
    Initiate a close handshake with the server.

    Sends a close frame and transitions to the Closing state. The
    connection will close after the server responds with its own close
    frame, or if TCP drops.
    """
    _state.close(this, code, reason)

  // -- lori ClientLifecycleEventReceiver --

  fun ref _connection(): lori.TCPConnection => _tcp_connection

  fun ref _on_connected() =>
    """
    Send the upgrade request now that there is a socket to write to.

    The key is generated here rather than in the constructor so that a
    CSPRNG failure can be reported through `on_handshake_failure()`.
    """
    let config = match \exhaustive\ _config
      | let c: WebSocketClientConfig val => c
      | None => _Unreachable(); return
      end

    match \exhaustive\ _ClientKey()
    | let key: String val =>
      let handshake = _ClientHandshake(key, config)
      _handshake = handshake
      _tcp_connection.send(handshake.request(_host, _port, _secure))
      _state = _Handshaking
    | _ClientKeyUnavailable =>
      _fire_on_handshake_failure(ClientHandshakeKeyUnavailable)
      _tcp_connection.close()
      _state = _Closed
    end

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    """
    The connection never opened, so no WebSocket ever existed to close.
    """
    _fire_on_connection_failure(reason)
    _state = _Closed

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _state.on_received(this, consume data)
    lori.KeepReading

  fun ref _on_closed() =>
    _state.on_closed(this)

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

  fun ref _on_tls_failure(reason: lori.TLSFailureReason) => None

  fun ref _on_timer(token: lori.TimerToken) => None

  // -- Internal methods called by state classes --

  fun ref _set_state(state: _ConnectionState) =>
    """Transition to a new connection state."""
    _state = state

  fun ref _feed_handshake(data: Array[U8] iso) =>
    """Validate the server's upgrade response."""
    let handshake = match \exhaustive\ _handshake
      | let h: _ClientHandshake => h
      | None => _Unreachable(); return
      end

    match \exhaustive\ handshake(consume data)
    | _ClientHandshakeNeedMore => None
    | let result: _ClientHandshakeResult =>
      _state = _Open
      _fire_on_open(result.response)
      // Forward any frame bytes that arrived in the same segment
      if result.remaining.size() > 0 then
        _feed_frames_from_val(result.remaining)
      end
    | let err: ClientHandshakeError =>
      // No WebSocket was established, so there is no close handshake to
      // perform and no on_closed to deliver — just drop the TCP connection.
      _fire_on_handshake_failure(err)
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
      _send_close_frame(err.code)
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
          _send_pong(frame.payload)
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
      _send_pong(frame.payload)
    | 0x0A =>
      // Pong — discard
      None
    | 0x08 =>
      // Close — echo the server's close payload (status code + reason)
      if frame.payload.size() >= 2 then
        _send_close_payload(frame.payload)
      else
        _send_close_empty()
      end
      (let status, let reason) =
        _CloseStatusExtractor.from_payload(frame.payload)
      _fire_on_closed(status, reason)
      _tcp_connection.close()
      _state = _Closed
    else
      // Data frame (text, binary, continuation) — reassemble
      let max_size = match \exhaustive\ _config
        | let c: WebSocketClientConfig val => c.max_message_size
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
        _send_close_frame(err.code)
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

  // -- Masked frame encoding --

  fun ref _send_text(data: String val) =>
    """Encode and send a masked text message."""
    match _MaskKey()
    | let key: U32 => _send_frame(_FrameEncoder.text(data, key))
    | _MaskKeyUnavailable => None
    end

  fun ref _send_binary(data: Array[U8] val) =>
    """Encode and send a masked binary message."""
    match _MaskKey()
    | let key: U32 => _send_frame(_FrameEncoder.binary(data, key))
    | _MaskKeyUnavailable => None
    end

  fun ref _send_close_frame(code: CloseCode, reason: String val = "") =>
    """
    Encode and send a masked close frame, without changing state.

    The error paths transition straight to `_Closed`, so the transition is
    the caller's business rather than this method's.
    """
    match _MaskKey()
    | let key: U32 => _send_frame(_FrameEncoder.close(code, reason, key))
    | _MaskKeyUnavailable => None
    end

  fun ref _send_close_payload(payload: Array[U8] val) =>
    """Encode and send a masked close frame echoing the server's payload."""
    match _MaskKey()
    | let key: U32 =>
      _send_frame(_FrameEncoder.close_payload(payload, key))
    | _MaskKeyUnavailable => None
    end

  fun ref _send_close_empty() =>
    """Encode and send a masked close frame with no payload."""
    match _MaskKey()
    | let key: U32 => _send_frame(_FrameEncoder.close_empty(key))
    | _MaskKeyUnavailable => None
    end

  fun ref _send_pong(payload: Array[U8] val) =>
    """Encode and send a masked pong echoing a ping payload."""
    match _MaskKey()
    | let key: U32 => _send_frame(_FrameEncoder.pong(payload, key))
    | _MaskKeyUnavailable => None
    end

  fun ref _close(code: CloseCode, reason: String val) =>
    """Send a close frame and await the server's response."""
    _send_close_frame(code, reason)
    _set_state(_Closing)

  // -- Lifecycle event delivery --

  fun ref _fire_on_connection_failure(
    reason: lori.ConnectionFailureReason)
  =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketClientLifecycleEventReceiver ref =>
      r.on_connection_failure(reason)
    | None => _Unreachable()
    end

  fun ref _fire_on_handshake_failure(err: ClientHandshakeError) =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketClientLifecycleEventReceiver ref =>
      r.on_handshake_failure(err)
    | None => _Unreachable()
    end

  fun ref _fire_on_open(response: UpgradeResponse val) =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketClientLifecycleEventReceiver ref => r.on_open(response)
    | None => _Unreachable()
    end

  fun ref _fire_on_text(data: String val) =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketClientLifecycleEventReceiver ref =>
      r.on_text_message(data)
    | None => _Unreachable()
    end

  fun ref _fire_on_binary(data: Array[U8] val) =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketClientLifecycleEventReceiver ref =>
      r.on_binary_message(data)
    | None => _Unreachable()
    end

  fun ref _fire_on_closed(
    close_status: CloseStatus,
    close_reason: String val)
  =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketClientLifecycleEventReceiver ref =>
      r.on_closed(close_status, close_reason)
    | None => _Unreachable()
    end

  fun ref _fire_on_throttled() =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketClientLifecycleEventReceiver ref => r.on_throttled()
    | None => _Unreachable()
    end

  fun ref _fire_on_unthrottled() =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketClientLifecycleEventReceiver ref => r.on_unthrottled()
    | None => _Unreachable()
    end

  fun ref _fire_on_idle_timeout() =>
    match \exhaustive\ _lifecycle_event_receiver
    | let r: WebSocketClientLifecycleEventReceiver ref => r.on_idle_timeout()
    | None => _Unreachable()
    end
