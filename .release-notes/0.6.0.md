## Fix dropped messages when a connection closes under backpressure

When the socket cannot take more data, messages you send with `send_text()` and `send_binary()` are queued until it can, and `on_throttled()` fires. Anything still in that queue when the connection closed was discarded, so the client never received it. Queued data is now written out before the connection shuts down.

This matters most for `close()`, which sends a WebSocket close frame and then shuts the connection down. A message sent shortly before `close()` now reaches the client instead of being discarded.

## Fix a hang when closing a connection while handling a message

Closing a connection while handling a message that had just arrived — a `close()` from `on_text_message()` or `on_binary_message()`, or the close handshake completing when the client's close frame comes in — could leave one more read outstanding on the socket that had just been closed. With many connections opening and closing, that read could block one of the runtime's scheduler threads and keep the program from exiting.

## Fix a hang when sending under load

Under write load, sending on a connection could hang the whole program. When the operating system's send buffer filled on a blocking file descriptor, the write stalled and never returned. Connections use non-blocking descriptors, so this was reachable only after the operating system had reused a closed connection's descriptor number for a blocking socket elsewhere in the process — rare, but possible.

This is fixed on Linux, FreeBSD, OpenBSD, and DragonFly. macOS and Windows are unchanged.

## Add HandshakeAcceptKeyFailed to HandshakeError

Computing the `Sec-WebSocket-Accept` value takes a SHA-1, and that can now fail rather than crash or return a wrong hash. When it does, the handshake fails with a new `HandshakeError` member, `HandshakeAcceptKeyFailed`, and the server answers 500 Internal Server Error — the request was well formed, so 400 would be wrong.

Nothing else reports this error, and only an environment that cannot give OpenSSL a digest context produces it.

Code that matches `HandshakeError` exhaustively needs a new branch:

```pony
// Before
match \exhaustive\ err
| HandshakeRequestTooLarge => None
| HandshakeInvalidHTTP => None
| HandshakeMissingHost => None
| HandshakeMissingUpgrade => None
| HandshakeWrongVersion => None
| HandshakeMissingKey => None
| HandshakeInvalidKey => None
end

// After
match \exhaustive\ err
| HandshakeRequestTooLarge => None
| HandshakeInvalidHTTP => None
| HandshakeMissingHost => None
| HandshakeMissingUpgrade => None
| HandshakeWrongVersion => None
| HandshakeMissingKey => None
| HandshakeInvalidKey => None
| HandshakeAcceptKeyFailed => None
end
```

## Require ponyc 0.67.0 or later

mare now requires ponyc 0.67.0 or later on every platform. The previous minimum was 0.64.0, and 0.66.0 on Windows; 0.64.0 through 0.66.x are no longer supported. The write hang under load is closed by a socket call that ponyc added in 0.67.0.

## Move to ponylang/ssl 3.0.0

mare now depends on ponylang/ssl 3.0.0, where it depended on 2.0.1. If your application does not declare ssl itself, it picks up 3.0.0 through mare, and your own `use "ssl/net"` and `use "ssl/crypto"` code is built against it. If your application does declare ssl, your declaration is the one that applies.

Nothing in mare's own API changed: `WebSocketServer.ssl()` still takes an `SSLContext val`. The breaking changes are in your own ssl code. The one most likely to hit you is the renaming of the twelve protocol version primitives, which now spell their acronyms in full. These are the values you pass to `set_min_proto_version` and `set_max_proto_version` on the context you hand to mare:

```pony
// Before
ctx.set_min_proto_version(Tls1u2Version())?

// After
ctx.set_min_proto_version(TLS1u2Version())?
```

The rest of ponylang/ssl's breaking changes:

- `Digest` construction, `Digest.final`, and `HmacSha256` are now partial and need a `?`.
- `SSLContext.alpn_set_resolver` takes an `ALPNProtocolResolver val`, where it took a `box`.
- `SSLState` has a new member, `SSLDisposed`. An exhaustive match on `SSL.state()` does not compile until you handle it.
- A reference typed `HashFn tag` no longer compiles. Type it `val` or `box`.

See ponylang/ssl's 3.0.0 release notes for more on each of these.
