#!/bin/bash
# Symphony Conductor — start/stop daemon
# Usage: ./conductor.sh start [workflow-path] | stop | status
#
# Examples:
#   ./conductor.sh start                              # uses elixir/WORKFLOW.md
#   ./conductor.sh start ~/configs/project-a.md       # uses custom workflow
#   ./conductor.sh stop
#   ./conductor.sh status

CONDUCTOR_DIR="$(cd "$(dirname "$0")" && pwd)"
ELIXIR_DIR="$CONDUCTOR_DIR/elixir"
PID_FILE="$CONDUCTOR_DIR/.conductor.pid"
CAFE_PID_FILE="$CONDUCTOR_DIR/.caffeinate.pid"
LOG_FILE="$CONDUCTOR_DIR/conductor.log"

# Load shell profile for env vars (LINEAR_API_KEY, GITHUB_TOKEN, etc.)
[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc" 2>/dev/null

# mise-installed Elixir
export PATH="$HOME/.local/share/mise/installs/elixir/1.19.5-otp-28/bin:$HOME/.local/share/mise/installs/erlang/28.4.1/bin:$PATH"

start() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Conductor is already running (PID $(cat "$PID_FILE"))"
    exit 1
  fi

  WORKFLOW_PATH="${1:-}"

  echo "Starting Conductor at $(date)..."
  if [ -n "$WORKFLOW_PATH" ]; then
    WORKFLOW_PATH="$(cd "$(dirname "$WORKFLOW_PATH")" && pwd)/$(basename "$WORKFLOW_PATH")"
    echo "Using workflow: $WORKFLOW_PATH"
    if [ ! -f "$WORKFLOW_PATH" ]; then
      echo "Error: workflow file not found: $WORKFLOW_PATH"
      exit 1
    fi
  fi

  cd "$ELIXIR_DIR" || exit 1

  # Keep Mac awake for 7 hours (11pm-6am), even with lid closed (requires AC power)
  caffeinate -s -t 25200 &
  echo $! > "$CAFE_PID_FILE"

  if [ -n "$WORKFLOW_PATH" ]; then
    SYMPHONY_WORKFLOW_PATH="$WORKFLOW_PATH" nohup mix run --no-halt >> "$LOG_FILE" 2>&1 &
  else
    nohup mix run --no-halt >> "$LOG_FILE" 2>&1 &
  fi
  echo $! > "$PID_FILE"
  echo "Conductor started (PID $!, caffeinate keeping Mac awake, logging to $LOG_FILE)"
}

stop() {
  if [ ! -f "$PID_FILE" ]; then
    echo "Conductor is not running (no PID file)"
    exit 0
  fi

  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    echo "Stopping Conductor (PID $PID)..."
    kill "$PID"
    # Wait up to 10 seconds for graceful shutdown
    for i in $(seq 1 10); do
      if ! kill -0 "$PID" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    # Force kill if still running
    if kill -0 "$PID" 2>/dev/null; then
      kill -9 "$PID"
    fi
    echo "Conductor stopped at $(date)"
  else
    echo "Conductor was not running (stale PID file)"
  fi
  rm -f "$PID_FILE"

  # Also stop caffeinate
  if [ -f "$CAFE_PID_FILE" ]; then
    kill "$(cat "$CAFE_PID_FILE")" 2>/dev/null
    rm -f "$CAFE_PID_FILE"
  fi
}

status() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Conductor is running (PID $(cat "$PID_FILE"))"
    echo "Log: $LOG_FILE"
    echo "Last 5 log lines:"
    tail -5 "$LOG_FILE" 2>/dev/null
  else
    echo "Conductor is not running"
    rm -f "$PID_FILE" 2>/dev/null
  fi
}

case "${1:-}" in
  start)  start "$2" ;;
  stop)   stop ;;
  status) status ;;
  *)
    echo "Usage: $0 {start [workflow-path]|stop|status}"
    exit 1
    ;;
esac
