#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"
if [[ "$(uname -s)" != Darwin ]]; then echo "Lemulip requires macOS."; exit 1; fi
if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Run xcode-select --install, then open this file again."
  read -r -p "Press Return to close." _answer
  exit 1
fi
./script/build_app.sh
DESTINATION="$HOME/Applications/Lemulip.app"
mkdir -p "$HOME/Applications"
if [[ -e "$DESTINATION" ]]; then
  echo "Lemulip already exists at $DESTINATION. Your current installation was preserved."
  echo "The new build is at $PROJECT_DIR/dist/Lemulip.app. Quit the current app before replacing it."
  /usr/bin/open "$PROJECT_DIR/dist"
else
  cp -R dist/Lemulip.app "$DESTINATION"
  if pgrep -x Lemulip >/dev/null || pgrep -x Freewheel >/dev/null; then
    echo "Lemulip was installed at $DESTINATION."
    echo "Let the running Lemulip or previous Freewheel app finish its jobs, then quit it before opening Lemulip."
  else
    /usr/bin/open -n "$DESTINATION"
  fi
fi
echo "Done."
