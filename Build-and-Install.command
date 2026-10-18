#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"
if [[ "$(uname -s)" != Darwin ]]; then echo "Freewheel requires macOS."; exit 1; fi
if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Run xcode-select --install, then open this file again."
  read -r -p "Press Return to close." _answer
  exit 1
fi
./script/build_app.sh
DESTINATION="$HOME/Applications/Freewheel.app"
mkdir -p "$HOME/Applications"
if [[ -e "$DESTINATION" ]]; then
  echo "Freewheel already exists at $DESTINATION. Your current installation was preserved."
  echo "The new build is at $PROJECT_DIR/dist/Freewheel.app. Quit the current app before replacing it."
  /usr/bin/open "$PROJECT_DIR/dist"
else
  cp -R dist/Freewheel.app "$DESTINATION"
  /usr/bin/open -n "$DESTINATION"
fi
echo "Done."
