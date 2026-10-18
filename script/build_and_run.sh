#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in
  --verify-bundle)
    if [[ $# -ne 2 ]]; then echo "Usage: $0 --verify-bundle /path/to/Lemulip.app" >&2; exit 2; fi
    APP_BUNDLE="$2"
    ;;
  run|--verify|--debug|--logs|--telemetry)
    if [[ $# -gt 1 ]]; then echo "Unexpected extra arguments." >&2; exit 2; fi
    APP_BUNDLE="$ROOT_DIR/dist/Lemulip.app"
    ;;
  *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry|--verify-bundle PATH]" >&2; exit 2;;
esac
if [[ "$(uname -s)" != Darwin ]]; then echo "This command requires macOS." >&2; exit 1; fi
# Ask any existing instance to quit normally. Do not interrupt an active conversion.
if pgrep -x Lemulip >/dev/null || pgrep -x Freewheel >/dev/null; then
  echo "Please quit the running Lemulip or previous Freewheel app after its jobs finish, then run this script again." >&2
  exit 1
fi
if [[ "$MODE" != --verify-bundle ]]; then CONFIGURATION=debug ./script/build_app.sh; fi
case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify|--verify-bundle)
    /usr/bin/codesign --verify --all-architectures --strict "$APP_BUNDLE"
    "$APP_BUNDLE/Contents/MacOS/Lemulip" &
    APP_PID=$!
    # Track and close only this launch, never another user's running instance.
    trap 'kill -TERM "$APP_PID" 2>/dev/null || true; wait "$APP_PID" 2>/dev/null || true' EXIT
    for attempt in 1 2 3; do
      sleep 1
      if ! kill -0 "$APP_PID" 2>/dev/null; then
        echo "Lemulip exited during its launch check." >&2; exit 1
      fi
    done
    echo "Lemulip stayed running across three launch checks. This does not verify drag-and-drop behavior."
    ;;
  --debug) /usr/bin/lldb -- "$APP_BUNDLE/Contents/MacOS/Lemulip" ;;
  --logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "Lemulip"'
    ;;
  --telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.freewheel.Freewheel"'
    ;;
esac
