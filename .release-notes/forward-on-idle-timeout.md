## Forward on_idle_timeout to WebSocketLifecycleEventReceiver

`WebSocketLifecycleEventReceiver` now includes an `on_idle_timeout()` callback, fired when lori's idle timeout triggers on an open connection. This lets connection actors react to idle timeouts — for example, to implement heartbeat-based dead connection detection.

The callback has a default no-op implementation, so existing code is unaffected. Override it in your `WebSocketServerActor` to handle idle timeouts:

```pony
fun ref on_idle_timeout() =>
  // Connection went idle — close it
  _ws.close()
```
