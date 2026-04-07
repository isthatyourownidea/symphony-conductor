#!/bin/bash
# Symphony Conductor — start/stop daemon
# Usage: ./conductor.sh start | stop | status

CONDUCTOR_DIR="$(cd "$(dirname "$0")" && pwd)"
ELIXIR_DIR="$CONDUCTOR_DIR/elixir"
PID_FILE="$CONDUCTOR_DIR/.conductor.pid"
LOG_FILE="$CONDUCTOR_DIR/conductor.log"

# mise-installed Elixir
export PATH="$HOME/.local/share/mise/installs/elixir/1.19.5-otp-28/bin:$HOME/.local/share/mise/installs/erlang/28.4.1/bin:$PATH"

start() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Conductor is already running (PID $(cat "$PID_FILE"))"
    exit 1
  fi

  echo "Starting Conductor at $(date)..."
  cd "$ELIXIR_DIR" || exit 1
  nohup mix run --no-halt >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "Conductor started (PID $!, logging to $LOG_FILE)"
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
  start)  start ;;
  stop)   stop ;;
  status) status ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
