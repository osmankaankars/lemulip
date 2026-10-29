#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Building the Lemulip desktop app requires macOS 13 or later and Xcode Command Line Tools." >&2
  exit 1
fi
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME=Lemulip
GUI_PRODUCT=LemulipApp
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
UNIVERSAL=false
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --universal ) ]]; then echo "Usage: $0 [--universal]" >&2; exit 2; fi
if [[ "${1:-}" == --universal ]]; then UNIVERSAL=true; fi
case "$CONFIGURATION" in debug|release) ;; *) echo "CONFIGURATION must be debug or release." >&2; exit 2 ;; esac
/usr/bin/xcrun --sdk macosx --find swift >/dev/null

# Resolve Swift through the selected macOS SDK and respect DEVELOPER_DIR.
swift_build() { /usr/bin/xcrun --sdk macosx swift build "$@"; }

if [[ "$UNIVERSAL" == true ]]; then
  for architecture in arm64 x86_64; do
    swift_build --configuration "$CONFIGURATION" --arch "$architecture" --scratch-path ".build/$architecture"
  done
  ARM_BIN="$(swift_build --configuration "$CONFIGURATION" --arch arm64 --scratch-path .build/arm64 --show-bin-path)"
  INTEL_BIN="$(swift_build --configuration "$CONFIGURATION" --arch x86_64 --scratch-path .build/x86_64 --show-bin-path)"
else
  swift_build --configuration "$CONFIGURATION"
  NATIVE_BIN="$(swift_build --configuration "$CONFIGURATION" --show-bin-path)"
fi

STAGING="$(mktemp -d "$ROOT_DIR/.build/LemulipBundle.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
CONTENTS="$STAGING/$APP_NAME.app/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$ROOT_DIR/dist"
if [[ "$CONFIGURATION" == release ]]; then
  # Keep original build products and their objects intact for matching dSYMs.
  # Only fresh thin copies are stripped; engine packs use their existing path.
  SYMBOLS="$STAGING/debug-symbols"
  if [[ "$UNIVERSAL" == true ]]; then
    python3 script/prepare_binary_symbols.py prepare \
      --build "arm64=$ARM_BIN" --build "x86_64=$INTEL_BIN" \
      --staging "$STAGING/stripped" --symbols "$SYMBOLS"
    ARM_BIN="$STAGING/stripped/arm64"
    INTEL_BIN="$STAGING/stripped/x86_64"
  else
    NATIVE_ARCH="$(uname -m)"
    python3 script/prepare_binary_symbols.py prepare --build "$NATIVE_ARCH=$NATIVE_BIN" \
      --staging "$STAGING/stripped" --symbols "$SYMBOLS"
    NATIVE_BIN="$STAGING/stripped/$NATIVE_ARCH"
  fi
fi
if [[ "$UNIVERSAL" == true ]]; then
  lipo -create "$ARM_BIN/$GUI_PRODUCT" "$INTEL_BIN/$GUI_PRODUCT" -output "$CONTENTS/MacOS/$APP_NAME"
  lipo -create "$ARM_BIN/lemulip" "$INTEL_BIN/lemulip" -output "$STAGING/lemulip"
else
  cp "$NATIVE_BIN/$GUI_PRODUCT" "$CONTENTS/MacOS/$APP_NAME"
  cp "$NATIVE_BIN/lemulip" "$STAGING/lemulip"
fi
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp LICENSE "$CONTENTS/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"
/usr/bin/xcrun --sdk macosx swift script/make_icon.swift Resources/AppIcon.png "$STAGING/AppIcon.iconset"
iconutil --convert icns "$STAGING/AppIcon.iconset" --output "$CONTENTS/Resources/AppIcon.icns"
chmod +x "$CONTENTS/MacOS/$APP_NAME" "$STAGING/lemulip"
plutil -lint "$CONTENTS/Info.plist"

# Optional maintainer-audited packs are staged before signing the outer bundle.
# The normal lightweight build does not download or bundle third-party engines.
if [[ -n "${LEMULIP_ENGINE_PACKS:-}" ]]; then
  if [[ "$UNIVERSAL" == true ]]; then
    python3 script/bundle_engines.py --packs "$LEMULIP_ENGINE_PACKS" --app "$STAGING/$APP_NAME.app" --architectures arm64 x86_64
  else
    python3 script/bundle_engines.py --packs "$LEMULIP_ENGINE_PACKS" --app "$STAGING/$APP_NAME.app" --architectures "$(uname -m)"
  fi
fi

# An ad-hoc signature makes a local build self-contained. No signing keys are used.
codesign --force --sign - "$STAGING/$APP_NAME.app"
codesign --force --sign - "$STAGING/lemulip"
codesign --verify --all-architectures --strict --verbose=2 "$STAGING/$APP_NAME.app"
codesign --verify --all-architectures --strict --verbose=2 "$STAGING/lemulip"
if [[ "$UNIVERSAL" == true ]]; then
  /usr/bin/lipo "$CONTENTS/MacOS/$APP_NAME" -verify_arch arm64 x86_64
  /usr/bin/lipo "$STAGING/lemulip" -verify_arch arm64 x86_64
fi
if [[ "$CONFIGURATION" == release ]]; then
  python3 script/prepare_binary_symbols.py verify --symbols "$SYMBOLS" \
    --gui "$CONTENTS/MacOS/$APP_NAME" --cli "$STAGING/lemulip"
  # Retained debug artifacts are never copied into the app, ZIP, or DMG.
  if [[ -e "$ROOT_DIR/dist/Lemulip-Debug-Symbols" ]]; then
    SYMBOL_BACKUP="$(mktemp -d "$ROOT_DIR/.build/LemulipPreviousSymbols.XXXXXX")"
    mv "$ROOT_DIR/dist/Lemulip-Debug-Symbols" "$SYMBOL_BACKUP/"
  fi
  mv "$SYMBOLS" "$ROOT_DIR/dist/Lemulip-Debug-Symbols"
fi
if [[ -e "$APP_BUNDLE" ]]; then
  BACKUP="$(mktemp -d "$ROOT_DIR/.build/LemulipPrevious.XXXXXX")"
  mv "$APP_BUNDLE" "$BACKUP/$APP_NAME.app"
fi
mv "$STAGING/$APP_NAME.app" "$APP_BUNDLE"
cp "$STAGING/lemulip" "$ROOT_DIR/dist/lemulip"
echo "Built: $APP_BUNDLE"
echo "CLI:   $ROOT_DIR/dist/lemulip"
