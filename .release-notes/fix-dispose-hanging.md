## Fix dispose() hanging when peer FIN is missed

On POSIX with edge-triggered oneshot events, there's a narrow timing window where the peer's FIN notification can be missed after event resubscription. When that happens, `dispose()` would leave the socket stuck in CLOSE_WAIT and the runtime would never exit.

`dispose()` now performs an unconditional hard close — it unsubscribes from ASIO, closes the fd, and fires `_on_closed()` immediately instead of attempting a graceful half-close that waits for the peer. If you need a graceful close, call `close()` explicitly before disposal.

