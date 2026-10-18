#!/usr/bin/env bash
set -euo pipefail

# Opt-in validation only. The regular build continues to ship AppIcon.icns.
# Compiled Icon Composer output is temporary and never installed or committed.
if [[ $# -ne 1 || "${1:-}" != --verify ]]; then
  echo "Usage: $0 --verify" >&2
  exit 2
fi
if [[ "$(/usr/bin/uname -s)" != Darwin ]]; then
  echo "Icon Composer verification requires macOS and Xcode 26 or later." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ICON_SOURCE="$ROOT_DIR/Resources/Lemulip.icon"
RIBBON="$ICON_SOURCE/Assets/01-Ribbon.png"
if [[ ! -d "$ICON_SOURCE" || -L "$ICON_SOURCE" ||
      ! -f "$ICON_SOURCE/icon.json" || -L "$ICON_SOURCE/icon.json" ||
      ! -d "$ICON_SOURCE/Assets" || -L "$ICON_SOURCE/Assets" ||
      ! -f "$RIBBON" || -L "$RIBBON" ]]; then
  echo "The reviewed Lemulip.icon source and Assets/01-Ribbon.png must be present as regular files." >&2
  exit 1
fi

# Keep the reviewed 1254px foreground unchanged. Its layer position in icon.json
# uses a 1024/1254 scale for the 1024px composition, with no image-file resizing.
# This metadata check supplements visual review; it does not inspect every pixel.
IMAGE_PROPERTIES="$(/usr/bin/sips -g format -g pixelWidth -g pixelHeight -g hasAlpha "$RIBBON")"
IMAGE_FORMAT="$(printf '%s\n' "$IMAGE_PROPERTIES" | /usr/bin/awk '$1 == "format:" { print $2 }')"
IMAGE_WIDTH="$(printf '%s\n' "$IMAGE_PROPERTIES" | /usr/bin/awk '$1 == "pixelWidth:" { print $2 }')"
IMAGE_HEIGHT="$(printf '%s\n' "$IMAGE_PROPERTIES" | /usr/bin/awk '$1 == "pixelHeight:" { print $2 }')"
IMAGE_ALPHA="$(printf '%s\n' "$IMAGE_PROPERTIES" | /usr/bin/awk '$1 == "hasAlpha:" { print $2 }')"
if [[ "$IMAGE_FORMAT" != png || "$IMAGE_WIDTH" != 1254 ||
      "$IMAGE_HEIGHT" != 1254 || "$IMAGE_ALPHA" != yes ]]; then
  echo "The reviewed Lemulip foreground must be a 1254 × 1254 PNG with an alpha channel." >&2
  exit 1
fi

# Resolve through the selected SDK; never change xcode-select or DEVELOPER_DIR.
/usr/bin/xcrun --sdk macosx --find actool >/dev/null
TOOL_DETAILS="$(/usr/bin/xcrun --sdk macosx actool --version --output-format human-readable-text)"
TOOL_VERSION="$(printf '%s\n' "$TOOL_DETAILS" | /usr/bin/awk '$1 == "short-bundle-version:" { print $2 }')"
if [[ ! "$TOOL_VERSION" =~ ^([0-9]{1,3})(\.[0-9]+){0,2}$ ]]; then
  echo "Could not verify the selected actool version." >&2
  exit 1
fi
TOOL_MAJOR="${BASH_REMATCH[1]}"
if (( 10#$TOOL_MAJOR < 26 )); then
  echo "The selected actool must be version 26 or later." >&2
  exit 1
fi

ICON_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lemulip-icon.XXXXXX")"
trap 'rm -rf "$ICON_STAGE"' EXIT
ICON_PLIST="$ICON_STAGE/partial-info.plist"
/usr/bin/xcrun --sdk macosx actool "$ICON_SOURCE" \
  --compile "$ICON_STAGE" \
  --output-format human-readable-text \
  --notices --warnings --errors \
  --app-icon Lemulip \
  --output-partial-info-plist "$ICON_PLIST" \
  --include-all-app-icons \
  --target-device mac \
  --minimum-deployment-target 13.0 \
  --platform macosx

if [[ ! -f "$ICON_STAGE/Assets.car" || -L "$ICON_STAGE/Assets.car" ||
      ! -s "$ICON_STAGE/Assets.car" || ! -f "$ICON_PLIST" ||
      -L "$ICON_PLIST" || ! -s "$ICON_PLIST" ]]; then
  echo "actool did not produce the expected compiled icon archive and metadata." >&2
  exit 1
fi
/usr/bin/plutil -lint "$ICON_PLIST"
if ! COMPILED_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$ICON_PLIST")" ||
   [[ "$COMPILED_NAME" != Lemulip ]]; then
  echo "The compiled icon metadata does not identify Lemulip." >&2
  exit 1
fi

printf 'Icon Composer source compiled and verified with actool %s.\n' "$TOOL_VERSION"
echo "Temporary artifacts will be removed. The app still uses its regular ICNS icon."
echo "Finder, Dock, and appearance review on a Mac remains a separate check."
