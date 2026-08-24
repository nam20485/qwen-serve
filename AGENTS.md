# Repository Guidelines

Ops repo for running `qwen serve` (Qwen Code daemon/server) in a detached tmux session bound to a Tailscale IP. No build system, package manager, or CI — shell tooling plus a VS Code workspace file.

## Project Structure & Module Organization

Single-purpose: `scripts/run-qwen-serve.sh` wraps the entire `qwen serve` lifecycle in one tmux session (`qwen-serve`, overridable via `QWEN_SERVE_SESSION`), one subcommand per routine operation. Env plumbing is the non-obvious part: the tmux server snapshots its global environment once at first launch, so `start` both expands `TS_ADDR` into the command string and passes it via `tmux new -e`, making it visible to panes inside the session. `qwen-serve.code-workspace` opens the repo root in VS Code with no custom settings.

## Build, Test, and Development Commands

```bash
TS_ADDR=100.x.x.x scripts/run-qwen-serve.sh start     # create detached session (TS_ADDR required)
scripts/run-qwen-serve.sh attach [-r]                 # attach; Ctrl-b d detaches
scripts/run-qwen-serve.sh logs [-n N | -f | -o FILE]  # scrollback / follow / full dump
scripts/run-qwen-serve.sh tee [FILE]                  # live-pipe pane output (default /tmp/qwen-serve.log)
scripts/run-qwen-serve.sh stop | kill | restart | status
bash -n scripts/run-qwen-serve.sh                     # syntax check — the only automated validation
```

`QWEN_SERVE_PORT` (default 4170) sets the web origin port. Verify session env with `tmux show-environment -t qwen-serve`.

## Coding Style & Naming Conventions

Bash follows the existing script: `set -euo pipefail`, errors to stderr via a `die` helper, shellcheck-safe quoting (`"${arr[@]}"`, `printf '%q'` for paths interpolated into tmux commands), `cmd_*` functions dispatched by a `case` on the first argument, and the heredoc usage text kept in sync with the header comment.

## Testing Guidelines

No test framework. Validate changes with `bash -n scripts/run-qwen-serve.sh` and manually exercise the affected subcommands (e.g. `status`, `logs`).

## Commit & Pull Request Guidelines

From history: lowercase imperative subject ≤ ~50 chars (`add tmux session manager for qwen serve`), optional short body explaining the why. No commit prefixes; no PR template.
