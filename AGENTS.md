# Repository Guidelines

Ops repo for running `qwen serve` (Qwen Code daemon/server) in a detached tmux session bound to a Tailscale IP. No CI — shell tooling, a VS Code workspace file, and a uv-managed Python package (`pyproject.toml`, `main.py`). Licensed AGPL-3.0 (`LICENSE`); `README.md` carries the human-facing usage docs.

## Project Structure & Module Organization

Two parts: `scripts/run-qwen-serve.sh` wraps the entire `qwen serve` lifecycle in one tmux session (`qwen-serve`, overridable via `QWEN_SERVE_SESSION`), one subcommand per routine operation; and a Python entrypoint (`main.py`, deps in `pyproject.toml`/`uv.lock`) managed with uv. Env plumbing is the non-obvious part: the tmux server snapshots its global environment once at first launch, so `start` both expands `TS_ADDR` into the command string and passes it via `tmux new -e`, making it visible to panes inside the session. Log capture has two distinct paths: `logs` reads tmux's screen model via `capture-pane` — lines hard-wrapped at the pane width (80 cols for a detached session under default-size), and `tee` taps the raw pane stream via `pipe-pane` — original unwrapped lines. `qwen-serve.code-workspace` opens the repo root in VS Code with the Python interpreter pinned to `.venv`; `.gitignore` excludes runtime `*.log` files, `.qwen/tmp/`, and `__pycache__/`.

## Build, Test, and Development Commands

```bash
TS_ADDR=100.x.x.x scripts/run-qwen-serve.sh start     # create detached session (TS_ADDR required)
scripts/run-qwen-serve.sh attach [-r]                 # attach; Ctrl-b d detaches
scripts/run-qwen-serve.sh open                        # open Web UI in a browser (token as #token= fragment)
scripts/run-qwen-serve.sh logs [-n N | -f | -o FILE]  # scrollback / follow / full dump
scripts/run-qwen-serve.sh tee [-f] [FILE]             # live-pipe pane output; -f = also follow here
scripts/run-qwen-serve.sh tee-off                     # stop piping
scripts/run-qwen-serve.sh stop | kill | restart | status | help
uv sync                                               # install python deps into .venv
uv run main.py                                        # run the python entrypoint
bash -n scripts/run-qwen-serve.sh                     # shell syntax check
python3 -m py_compile main.py                         # python syntax check
```

`QWEN_SERVE_PORT` (default 4170) sets the web origin port. Verify session env with `tmux show-environment -t qwen-serve`.

## Coding Style & Naming Conventions

Bash follows the existing script: `set -euo pipefail`, errors to stderr via a `die` helper, shellcheck-safe quoting (`"${arr[@]}"`, `printf '%q'` for paths interpolated into tmux commands), `cmd_*` functions dispatched by a `case` on the first argument, and the heredoc usage text kept in sync with the header comment.

## Testing Guidelines

No test framework. Validate changes with `bash -n scripts/run-qwen-serve.sh` and `python3 -m py_compile main.py`, then manually exercise the affected subcommands (e.g. `status`, `logs`).

## Commit & Pull Request Guidelines

From history: lowercase imperative subject ≤ ~50 chars (`add tmux session manager for qwen serve`), optional short body explaining the why. No commit prefixes; no PR template.
