# Mare

A WebSocket server library for Pony, built on lori.

<!-- contributor-only -->
## Contributing with an AI assistant

This is a Pony project. The ponylang org maintains a set of LLM coding skills. Get set up with them before contributing:

- **Not set up yet?** Install them once:

  ```bash
  git clone https://github.com/ponylang/llm-skills.git
  cd llm-skills
  python install.py
  ```

- **Already set up?** Make sure you're on the latest. If you installed with the script above, `git pull` in the directory where you cloned `llm-skills` and the symlinked skills update automatically — if you set them up another way, refresh them however that setup expects.

See the [llm-skills README](https://github.com/ponylang/llm-skills) for details and other harnesses.

When you start working on this project, load the `pony-skills` skill — it tells your assistant which Pony skill to use for each task.

Read [CONTRIBUTING.md](CONTRIBUTING.md).
<!-- /contributor-only -->

## Building and testing

```
make test ssl=3.0.x                 # build + run tests + build examples
make unit-tests ssl=3.0.x           # tests only
make test-one t=TestName ssl=3.0.x  # run a single test by name
make examples ssl=3.0.x             # examples only
```

`ssl=` is required because mare uses `ssl/crypto` for the SHA-1 that computes the WebSocket handshake accept key.

## Connection states

`WebSocketServer` — a class the handler actor owns — tracks the connection through four states. Every state handles every event, so the state machine shows which handler runs in each phase; the behavior itself lives in `WebSocketServer`.

```
_Handshaking → _Open → _Closing → _Closed
     │           │                   ↑
     └───────────┴───────────────────┘
        (handshake failure, error, or abnormal close)
```

A close-handshake timeout looks like a job for lori's idle timeout, but that resets on any TCP receive, so it cannot bound a close; the OS TCP timeout covers the degenerate case instead.

## Conventions

- Prefer qualified imports (`use lori = "lori"`, `use crypto = "ssl/crypto"`, and so on).
- New test classes go in `_test_*.pony` files, registered in `_test.pony`.
- `\nodoc\` on test classes.
