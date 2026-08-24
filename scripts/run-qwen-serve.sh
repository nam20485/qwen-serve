#!/usr/bin/env bash

# Manage the `qwen serve` tmux session from scripts/tmux_new.sh — one
# subcommand per routine operation, so the server lifecycle and log capture
# are each a single call.
#
# Usage:
#   ./scripts/run-qwen-serve.sh start          create the detached server session
#   ./scripts/run-qwen-serve.sh attach [-r]    attach (-r = read-only); Ctrl-b d detaches
#   ./scripts/run-qwen-serve.sh logs [-n N]    last N scrollback lines (default 100)
#   ./scripts/run-qwen-serve.sh logs -f        follow the pane (~2s refresh; Ctrl-c stops)
#   ./scripts/run-qwen-serve.sh logs -o FILE   full scrollback since launch -> FILE
#   ./scripts/run-qwen-serve.sh tee [-f] [FILE]
#                                               pipe live pane output to FILE
#                                               (default /tmp/qwen-serve.log); -f:
#                                               also follow it live here — Ctrl-c
#                                               stops the follow only (tee-off
#                                               stops the file)
#   ./scripts/run-qwen-serve.sh tee-off        stop piping (file kept)
#   ./scripts/run-qwen-serve.sh stop           graceful: Ctrl-c to serve, waits ~10s
#   ./scripts/run-qwen-serve.sh kill           force: kill the session + the server
#   ./scripts/run-qwen-serve.sh restart        stop (fall back to kill), then start
#   ./scripts/run-qwen-serve.sh status         tmux version, session env, pane pid/cmd
#   ./scripts/run-qwen-serve.sh help           show usage (-h / --help also work)
#
# Environment:
#   TS_ADDR              Tailscale IP to bind (start/restart only, required)
#   QWEN_SERVE_SESSION   session name    (default: qwen-serve)
#   QWEN_SERVE_PORT      web origin port (default: 4170)
#
# Env-var plumbing: the tmux server snapshots its global environment once at
# first launch, and every pane inherits that snapshot — NOT your current shell.
# `start` therefore does both: (a) expands TS_ADDR itself while building the
# command string (double quotes, so it works regardless of tmux), and (b) passes
# it into the session via `tmux new -e` (tmux >= 3.2), so panes and interactive
# shells inside the session also see it. Verify with
# `tmux show-environment -t qwen-serve`.
set -euo pipefail

SESSION="${QWEN_SERVE_SESSION:-qwen-serve}"
PORT="${QWEN_SERVE_PORT:-4170}"

usage() {
    cat <<EOF
usage: $(basename "$0") <command> [options]

  start          create the detached server session (requires TS_ADDR)
  attach [-r]    attach to the session (-r read-only); Ctrl-b d detaches
  logs [-n N]    print last N scrollback lines (default 100)
  logs -f        follow the pane (~2s refresh, Ctrl-c to stop)
  logs -o FILE   write full scrollback since launch to FILE
  tee [-f] [FILE]
                 append live pane output to FILE (default /tmp/qwen-serve.log);
                 -f: also follow it live here — Ctrl-c stops the follow only,
                 piping continues until 'tee-off'
  tee-off        stop piping pane output (file kept)
  stop           graceful stop (sends Ctrl-c, waits ~10s)
  kill           force: kill the session and the server with it
  restart        stop (fall back to kill), then start
  status         session alive? env + pane details
  help           show this usage (-h / --help also work)

env: TS_ADDR (start/restart), QWEN_SERVE_SESSION (default qwen-serve),
     QWEN_SERVE_PORT (default 4170)
EOF
}

alive() { tmux has-session -t "$SESSION" 2>/dev/null; }
die() { echo "error: $*" >&2; exit 1; }

cmd_start() {
    if alive; then
        die "session '$SESSION' already exists — try: $0 attach"
    fi
    [ -n "${TS_ADDR:-}" ] || die "TS_ADDR is not set (TS_ADDR=100.x.x.x $0 start)"
    tmux new -d -s "$SESSION" -e TS_ADDR="$TS_ADDR" \
        "qwen serve --web --open --hostname $TS_ADDR --allow-origin http://${TS_ADDR}:${PORT}"
    echo "started '$SESSION'  ->  http://$TS_ADDR:$PORT  (attach: $0 attach)"
}

cmd_attach() {
    alive || die "no session '$SESSION' — try: $0 start"
    local ro=()
    if [ "${1:-}" = "-r" ]; then ro=(-r); fi
    exec tmux attach "${ro[@]}" -t "$SESSION"
}

cmd_logs() {
    alive || die "no session '$SESSION'"
    local n=100 follow=0 out="" opt
    while getopts ":n:fo:" opt; do
        case $opt in
            n) n=$OPTARG ;;
            f) follow=1 ;;
            o) out=$OPTARG ;;
            :) die "logs: option -$OPTARG needs a value" ;;
            \?) die "logs: unknown option -$OPTARG" ;;
        esac
    done
    if [ -n "$out" ]; then
        tmux capture-pane -t "$SESSION" -p -S - >"$out"
        echo "wrote full scrollback to $out"
        return
    fi
    if [ "$follow" = 1 ]; then
        # 2s poll — for a true live view use `attach`
        while alive; do
            clear
            printf '[%s] following %s (last %s lines) — Ctrl-c to stop\n' \
                "$(date +%T)" "$SESSION" "$n"
            tmux capture-pane -t "$SESSION" -p -S -"$n" || break
            sleep 2
        done
        return
    fi
    tmux capture-pane -t "$SESSION" -p -S -"$n"
}

# Continuous pipe: pane output is appended to FILE in real time (from the
# moment this is enabled — existing scrollback is not flushed). pipe-pane -O
# connects output only, so nothing can be typed into the pane through it.
cmd_tee() {
    alive || die "no session '$SESSION'"
    local follow=0
    if [ "${1:-}" = "-f" ]; then follow=1; shift; fi
    local file="${1:-${QWEN_SERVE_LOG:-/tmp/qwen-serve.log}}"
    case "$file" in
        /*) ;;
        *) file="$PWD/$file" ;;
    esac
    : >>"$file" 2>/dev/null || die "cannot write to '$file'"
    tmux pipe-pane -O -t "$SESSION" "cat >> $(printf '%q' "$file")"
    if [ "$follow" = 1 ]; then
        echo "appending live pane output to: $file (Ctrl-c stops the follow only)"
        exec tail -n 100 -F "$file"
    fi
    echo "appending live pane output to: $file"
    echo "true live follow from any terminal:  tail -f '$file'"
    echo "stop piping:  $0 tee-off"
}

cmd_tee_off() {
    alive || die "no session '$SESSION'"
    tmux pipe-pane -t "$SESSION"
    echo "stopped piping pane output (file kept)."
}

cmd_stop() {
    if ! alive; then
        echo "no session '$SESSION' — nothing to stop"
        return 0
    fi
    echo "sending Ctrl-c to '$SESSION', waiting for it to exit..."
    tmux send-keys -t "$SESSION" C-c
    local _
    for _ in $(seq 1 50); do
        alive || { echo "stopped."; return 0; }
        sleep 0.2
    done
    echo "error: still running after ~10s — use '$0 kill' to force" >&2
    return 1
}

cmd_kill() {
    alive || { echo "no session '$SESSION' — nothing to kill"; return 0; }
    tmux kill-session -t "$SESSION"
    echo "killed '$SESSION'."
}

cmd_restart() {
    if alive; then
        cmd_stop || { echo "warning: graceful stop failed; forcing" >&2; cmd_kill; }
    fi
    cmd_start
}

cmd_status() {
    tmux -V
    if alive; then
        echo "session '$SESSION': running"
        tmux list-panes -t "$SESSION" -F '  pane pid=#{pane_pid} cmd=#{pane_current_command}'
        local val
        val="$(tmux show-environment -t "$SESSION" TS_ADDR 2>/dev/null || true)"
        val="${val#TS_ADDR=}"
        [ -n "$val" ] || val="(unset)"
        echo "  session env TS_ADDR: $val"
    else
        echo "session '$SESSION': not running (start: TS_ADDR=100.x.x.x $0 start)"
    fi
}

command -v tmux >/dev/null 2>&1 || die "'tmux' not found on PATH"

case "${1:-}" in
    start) shift; cmd_start "$@" ;;
    attach) shift; cmd_attach "$@" ;;
    logs) shift; cmd_logs "$@" ;;
    tee) shift; cmd_tee "$@" ;;
    tee-off) shift; cmd_tee_off "$@" ;;
    stop) shift; cmd_stop "$@" ;;
    kill) shift; cmd_kill "$@" ;;
    restart) shift; cmd_restart "$@" ;;
    status) shift; cmd_status "$@" ;;
    -h | --help | help | "") usage ;;
    *) echo "error: unknown command: $1" >&2; usage >&2; exit 1 ;;
esac

# Notes:
# - `stop` relies on qwen serve exiting on Ctrl-c, which closes the pane and
#   with it the session.
# - kill-session ends this session only; the tmux server itself keeps running
#   (by design, it hosts all sessions). `tmux kill-server` ends ALL sessions.
