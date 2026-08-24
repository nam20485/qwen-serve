# qwen-serve

One script to run [`qwen serve`](https://github.com/QwenLM/qwen-code) — the Qwen Code daemon/server — as a detached tmux session bound to a Tailscale IP, with the whole lifecycle (start, attach, logs, stop) reduced to single subcommands.

## Requirements

- [`qwen`](https://github.com/QwenLM/qwen-code) CLI on `PATH`
- tmux ≥ 3.2 (for `new -e` env injection)
- [Tailscale](https://tailscale.com) (the server binds your tailnet IP)

## Quick start

```bash
TS_ADDR=100.x.x.x scripts/run-qwen-serve.sh start   # create the detached session
scripts/run-qwen-serve.sh status                    # check it's alive
scripts/run-qwen-serve.sh tee -f                    # follow the live log (Ctrl-c to stop)
```

The web UI is served at `http://$TS_ADDR:4170` (attach to the session to see the printed URL).

## Commands

| Command | What it does |
|---|---|
| `start` | create the detached server session (requires `TS_ADDR`) |
| `attach [-r]` | attach to the session (`-r` read-only); `Ctrl-b d` detaches |
| `logs [-n N]` | print last N scrollback lines (default 100) |
| `logs -f` | follow the pane (~2s refresh, `Ctrl-c` to stop) |
| `logs -o FILE` | write full scrollback since launch to FILE |
| `tee [-f] [FILE]` | append live pane output to FILE (default `/tmp/qwen-serve.log`); `-f` also follows it here — `Ctrl-c` stops the follow only |
| `tee-off` | stop piping pane output (file kept) |
| `stop` | graceful stop (sends `Ctrl-c`, waits ~10s) |
| `kill` | force: kill the session and the server with it |
| `restart` | stop (fall back to kill), then start |
| `status` | tmux version, session env, pane pid/cmd |
| `help` | show usage (`-h` / `--help` also work) |

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `TS_ADDR` | — | Tailscale IP to bind (`start`/`restart` only, required) |
| `QWEN_SERVE_SESSION` | `qwen-serve` | tmux session name |
| `QWEN_SERVE_PORT` | `4170` | web origin port |
| `QWEN_SERVE_LOG` | `/tmp/qwen-serve.log` | default `tee` target |

## Notes

- **Env plumbing:** the tmux server snapshots its global environment once at first launch, and panes inherit that snapshot — not your current shell. `start` therefore both expands `TS_ADDR` into the command string and injects it into the session via `tmux new -e`. Verify with `tmux show-environment -t qwen-serve`.
- **`logs` vs `tee`:** `logs` reads tmux's rendered screen, so long lines are hard-wrapped at the pane width (80 cols for a detached session). `tee` taps the raw pane stream *before* rendering, so the file gets original unwrapped lines — prefer it for anything you'll grep or parse.
- `stop` relies on `qwen serve` exiting on `Ctrl-c`; `kill-session` ends only this session, never the whole tmux server.

## License

[AGPL-3.0](LICENSE)
