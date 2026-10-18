#!/usr/bin/env bash
set -euo pipefail

# CI-only engine setup. The application never invokes this download script.
if [[ "$(uname -s)" != Darwin || -z "${GITHUB_PATH:-}" ]]; then
  echo "This helper is for the macOS GitHub Actions job. Use Pandoc's official installer on a personal Mac." >&2
  exit 1
fi

VERSION=3.12.1
case "$(uname -m)" in
  arm64)
    ARCH=arm64
    SHA256=c2146cf33a583f3ac93eccddf1bb662371d5cfcce1aad1c87ad860cca1435d46
    ;;
  x86_64)
    ARCH=x86_64
    SHA256=81ed3e2cfecf096df15d407152f89a684fd65221082b919963f738e977fad3bc
    ;;
  *) echo "Unsupported runner architecture." >&2; exit 1 ;;
esac

# Digests are from https://api.github.com/repos/jgm/pandoc/releases/tags/3.12.1.
# Keep the official embedded-data build: package-manager variants may not work
# with the file sandbox used for EPUB/DOCX/ODT conversions.
PANDOC_STAGE="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lemulip-pandoc.XXXXXX")"
ARCHIVE="$PANDOC_STAGE/pandoc.zip"
curl --proto '=https' --tlsv1.2 --fail --location --retry 3 \
  "https://github.com/jgm/pandoc/releases/download/$VERSION/pandoc-$VERSION-$ARCH-macOS.zip" \
  --output "$ARCHIVE"
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum -a 256 --check
unzip -q "$ARCHIVE" -d "$PANDOC_STAGE/unpacked"

PANDOC_BIN=""
for candidate in "$PANDOC_STAGE"/unpacked/*/bin/pandoc "$PANDOC_STAGE"/unpacked/bin/pandoc; do
  if [[ -f "$candidate" && -x "$candidate" ]]; then
    PANDOC_BIN="$candidate"
    break
  fi
done
if [[ -z "$PANDOC_BIN" ]]; then
  echo "The verified Pandoc package has an unexpected layout." >&2
  exit 1
fi
"$PANDOC_BIN" --version
printf '%s\n' "$(dirname "$PANDOC_BIN")" >> "$GITHUB_PATH"
