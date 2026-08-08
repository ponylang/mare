primitive _CloseStatusExtractor
  """
  Extracts a typed close status and reason string from a raw close frame
  payload.

  Used in `WebSocketServer` to convert raw frame bytes into the
  `(CloseStatus, String val)` pair delivered to `on_closed()`.
  """

  fun from_payload(payload: Array[U8] val): (CloseStatus, String val) =>
    """
    Map a close frame payload to a typed status and reason string.

    Empty payloads produce `CloseNoStatusReceived`. Payloads with 2+ bytes
    have the first two bytes decoded as a big-endian U16 status code and the
    remainder as the reason string.

    Assumes the payload is either empty or >= 2 bytes — 1-byte close payloads
    are rejected earlier by `_FrameParser`.
    """
    if payload.size() == 0 then
      return (CloseNoStatusReceived, "")
    end

    try
      let code = (payload(0)?.u16() << 8) or payload(1)?.u16()
      let status = _code_to_status(code)

      let reason =
        if payload.size() > 2 then
          let s = String(payload.size() - 2)
          var i: USize = 2
          while i < payload.size() do
            s.push(payload(i)?)
            i = i + 1
          end
          s.clone()
        else
          ""
        end

      (status, consume reason)
    else
      _Unreachable()
      (CloseNoStatusReceived, "")
    end

  fun _code_to_status(code: U16): CloseStatus =>
    """
    Map a raw U16 close code to the appropriate `CloseStatus` member.

    Named primitives are returned for standard codes; all others get
    `OtherCloseCode`.
    """
    match code
    | 1000 => CloseNormal
    | 1001 => CloseGoingAway
    | 1002 => CloseProtocolError
    | 1003 => CloseUnsupportedData
    | 1007 => CloseInvalidPayload
    | 1008 => ClosePolicyViolation
    | 1009 => CloseMessageTooBig
    | 1011 => CloseInternalError
    else
      OtherCloseCode(code)
    end
