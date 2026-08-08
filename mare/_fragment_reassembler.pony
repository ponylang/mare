class _FragmentReassembler
  """
  Reassembles fragmented WebSocket messages.

  Buffers continuation frames until the final fragment arrives, enforces
  `max_message_size`, and validates UTF-8 for text messages. Control
  frames (ping, pong, close) bypass this class entirely — the caller
  dispatches them before reaching the reassembler.
  """
  var _in_progress: Bool = false
  var _is_text: Bool = false
  var _buf: Array[U8] ref = Array[U8]
  var _total_size: USize = 0

  fun ref frame(
    fin: Bool,
    opcode: U8,
    payload: Array[U8] val,
    max_size: USize)
    : (_CompleteMessage | _FragmentContinue | _ReassemblyError)
  =>
    """
    Process a data frame (text, binary, or continuation).

    Returns `_CompleteMessage` when the full message is assembled,
    `_FragmentContinue` when more fragments are expected, or
    `_ReassemblyError` on protocol violation.
    """
    if opcode == 0x00 then
      // Continuation frame
      if not _in_progress then
        return _ReassemblyError(CloseProtocolError)
      end
    else
      // Text (0x01) or binary (0x02) — starts a new message
      if _in_progress then
        return _ReassemblyError(CloseProtocolError)
      end
      _in_progress = true
      _is_text = (opcode == 0x01)
      _buf = Array[U8]
      _total_size = 0
    end

    // Accumulate payload
    _total_size = _total_size + payload.size()
    if _total_size > max_size then
      _reset()
      return _ReassemblyError(CloseMessageTooBig)
    end
    _buf.append(payload)

    if fin then
      // Message complete. Build val array from buffer using String
      // intermediary: build ref String, clone to iso, iso_array to val.
      let is_text' = _is_text
      let msg_s = String(_buf.size())
      for b in _buf.values() do
        msg_s.push(b)
      end
      let message_data: Array[U8] val = msg_s.clone().iso_array()
      _reset()

      if is_text' then
        if not _Utf8Validator.is_valid(message_data) then
          return _ReassemblyError(CloseInvalidPayload)
        end
      end

      _CompleteMessage(is_text', message_data)
    else
      _FragmentContinue
    end

  fun ref _reset() =>
    """
    Reset reassembly state for the next message.
    """
    _in_progress = false
    _is_text = false
    _buf = Array[U8]
    _total_size = 0

class val _CompleteMessage
  """
  A fully reassembled WebSocket message.
  """
  let is_text: Bool
  let data: Array[U8] val

  new val create(is_text': Bool, data': Array[U8] val) =>
    is_text = is_text'
    data = data'

primitive _FragmentContinue
  """
  More fragments are expected to complete the message.
  """

class val _ReassemblyError
  """
  A reassembly error with the close code to send.
  """
  let code: CloseCode

  new val create(code': CloseCode) =>
    code = code'
