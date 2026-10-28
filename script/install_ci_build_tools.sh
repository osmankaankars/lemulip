#!/usr/bin/env bash
# Build tools only. Never copy package-manager libraries into engine packs.
set -euo pipefail
export HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_AUTO_UPDATE=1
missing=()
for pair in cmake:cmake nasm:nasm pkgconf:pkg-config autoconf:autoreconf automake:automake libtool:glibtoolize; do
  if ! command -v "${pair#*:}" >/dev/null 2>&1; then missing+=("${pair%:*}"); fi
done
if [ ${#missing[@]} -gt 0 ]; then
  brew update
  brew install "${missing[@]}"
fi
for tool in cmake nasm pkg-config autoreconf automake glibtoolize; do
  command -v "$tool"
done
