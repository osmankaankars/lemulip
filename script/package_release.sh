#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ "$(uname -s)" != Darwin ]]; then echo "macOS release packaging requires macOS." >&2; exit 1; fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "Invalid release version." >&2; exit 1; fi
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$VERSION" ]]; then
  echo "The release tag must match the version in Resources/Info.plist." >&2; exit 1
fi
PACKAGE_NAME="Lemulip-$VERSION-macOS-universal"
SOURCE_NAME="Lemulip-$VERSION-Source.zip"

verify_binary() {
  /usr/bin/lipo "$1" -verify_arch arm64 x86_64
  /usr/bin/codesign --verify --all-architectures --strict --verbose=2 "$1"
  # Release binaries must not depend on a CI machine's optional engine installs.
  local linked_libraries
  linked_libraries="$(/usr/bin/otool -L "$1")"
  if printf '%s\n' "$linked_libraries" | /usr/bin/awk '/^[[:space:]]/ {print $1}' | /usr/bin/grep -E '/(opt/homebrew|usr/local|Users|home)/'; then
    echo "A release binary depends on a non-system library." >&2; exit 1
  fi
}

verify_bundle() {
  /usr/bin/plutil -lint "$1/Contents/Info.plist"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$1/Contents/Info.plist")" == "$VERSION" ]]
  /usr/bin/codesign --verify --all-architectures --strict --verbose=2 "$1"
  verify_binary "$1/Contents/MacOS/Lemulip"
  cmp LICENSE "$1/Contents/Resources/LICENSE"
  cmp THIRD_PARTY_NOTICES.md "$1/Contents/Resources/THIRD_PARTY_NOTICES.md"
  python3 script/verify_bundled_engines.py --app "$1" --architectures arm64 x86_64
}

copy_public_guides() {
  local destination="$1"
  mkdir -p "$destination/docs"
  cp LICENSE THIRD_PARTY_NOTICES.md CONTRIBUTING.md SECURITY.md "$destination/"
  for guide in INSTALL.md USER_GUIDE.md FORMATS.md DEVELOPMENT.md OFFICE_REVIEW.md RELEASE_NOTES.md; do
    cp "docs/$guide" "$destination/docs/"
  done
  cat > "$destination/README.md" <<'README'
# Lemulip

[Installation](docs/INSTALL.md) · [User Guide](docs/USER_GUIDE.md) · [Formats](docs/FORMATS.md) · [Release Notes](docs/RELEASE_NOTES.md)

The ZIP also includes the `lemulip` command-line tool.

[License](LICENSE) · [Third-Party Notices](THIRD_PARTY_NOTICES.md) · [Security](SECURITY.md)
README
}

verify_public_guides() {
  local destination="$1"
  for guide in INSTALL.md USER_GUIDE.md FORMATS.md DEVELOPMENT.md OFFICE_REVIEW.md RELEASE_NOTES.md; do
    cmp "docs/$guide" "$destination/docs/$guide"
  done
  for notice in LICENSE THIRD_PARTY_NOTICES.md CONTRIBUTING.md SECURITY.md; do
    cmp "$notice" "$destination/$notice"
  done
}

if [[ "${1:-}" == --verify ]]; then
  if [[ $# -ne 2 ]]; then echo "Usage: $0 --verify /path/to/release-files" >&2; exit 2; fi
  RELEASE_DIRECTORY="$(cd "$2" && pwd)"
  # Check exact filenames and bytes before extracting or opening the package.
  python3 - "$RELEASE_DIRECTORY" "$PACKAGE_NAME" "$SOURCE_NAME" <<'PY'
import hashlib, pathlib, re, stat, sys, zipfile
directory, package, source = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
expected = {package + '.zip', package + '.dmg', source}
seen = set()
for line in (directory / 'SHA256SUMS.txt').read_text().splitlines():
    match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9.-]+)', line)
    if not match or match[2] not in expected or match[2] in seen:
        raise SystemExit('Unexpected checksum entry')
    path = directory / match[2]
    if path.is_symlink() or not path.is_file(): raise SystemExit('Invalid release file')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''): digest.update(chunk)
    if digest.hexdigest() != match[1]: raise SystemExit('Release checksum mismatch')
    seen.add(match[2])
if seen != expected: raise SystemExit('Missing release checksum')
for filename, prefix in [(package + '.zip', package), (source, 'Lemulip')]:
    with zipfile.ZipFile(directory / filename) as archive:
        if archive.testzip(): raise SystemExit('Corrupt release ZIP')
        names = set()
        for entry in archive.infolist():
            parts = pathlib.PurePosixPath(entry.filename).parts
            if (not parts or parts[0] != prefix or '..' in parts or '\\' in entry.filename
                    or any(ord(c) < 32 for c in entry.filename) or entry.filename in names
                    or stat.S_ISLNK(entry.external_attr >> 16)):
                raise SystemExit('Unsafe release ZIP entry')
            names.add(entry.filename)
print('All three release archives match SHA256SUMS.txt; ZIP paths and CRCs are valid.')
PY
  VERIFY_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lemulip-release-check.XXXXXX")"
  MOUNTED=false
  cleanup_verify() {
    if [[ "$MOUNTED" == true ]]; then
      if ! /usr/bin/hdiutil detach "$VERIFY_STAGE/volume" >/dev/null; then
        echo "The read-only verification volume could not be detached; its temporary directory was preserved." >&2
        return 1
      fi
    fi
    rm -rf "$VERIFY_STAGE"
  }
  trap cleanup_verify EXIT
  /usr/bin/ditto -x -k "$RELEASE_DIRECTORY/$PACKAGE_NAME.zip" "$VERIFY_STAGE/unpacked"
  PACKAGE_DIRECTORY="$VERIFY_STAGE/unpacked/$PACKAGE_NAME"
  verify_bundle "$PACKAGE_DIRECTORY/Lemulip.app"
  verify_binary "$PACKAGE_DIRECTORY/lemulip"
  verify_public_guides "$PACKAGE_DIRECTORY"
  "$PACKAGE_DIRECTORY/lemulip" --help
  python3 script/smoke_bundled_engines.py --package "$PACKAGE_DIRECTORY"
  mkdir "$VERIFY_STAGE/output" "$VERIFY_STAGE/volume"
  printf '1\n00:00:00,000 --> 00:00:01,000\nRelease smoke check\n' > "$VERIFY_STAGE/sample.srt"
  "$PACKAGE_DIRECTORY/lemulip" convert vtt "$VERIFY_STAGE/sample.srt" --output "$VERIFY_STAGE/output"
  /usr/bin/grep -q '^WEBVTT' "$VERIFY_STAGE/output/"*.vtt
  /usr/bin/grep -q 'Release smoke check' "$VERIFY_STAGE/output/"*.vtt
  /usr/bin/hdiutil verify "$RELEASE_DIRECTORY/$PACKAGE_NAME.dmg"
  /usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$VERIFY_STAGE/volume" "$RELEASE_DIRECTORY/$PACKAGE_NAME.dmg" >/dev/null
  MOUNTED=true
  verify_bundle "$VERIFY_STAGE/volume/Lemulip.app"
  verify_public_guides "$VERIFY_STAGE/volume"
  diff -qr "$PACKAGE_DIRECTORY/Lemulip.app" "$VERIFY_STAGE/volume/Lemulip.app"
  [[ "$(readlink "$VERIFY_STAGE/volume/Applications")" == /Applications ]]
  ./script/build_and_run.sh --verify-bundle "$PACKAGE_DIRECTORY/Lemulip.app"
  echo "Verified release archives, both architectures, signatures, licenses, CLI conversion, and native launch."
  exit 0
fi
if [[ $# -ne 0 ]]; then echo "Usage: $0 [--verify /path/to/release-files]" >&2; exit 2; fi

# Preserve previous downloads rather than silently replacing a released version.
for filename in "$PACKAGE_NAME.zip" "$PACKAGE_NAME.dmg" "$SOURCE_NAME" SHA256SUMS.txt RELEASE_NOTES.md; do
  if [[ -e "dist/$filename" ]]; then
    echo "dist/$filename already exists. Move previous release files before packaging again." >&2; exit 1
  fi
done
# An extracted source ZIP has no Git index. A checkout keeps the stronger index
# check; a failed check in an existing repository never falls back to files.
if [[ -e .git ]] || /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    /usr/bin/git -c core.hooksPath=/dev/null -c core.fsmonitor=false \
    rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  python3 script/privacy_check.py --staged
else
  python3 script/privacy_check.py
fi
CONFIGURATION=release ./script/build_app.sh --universal
verify_bundle dist/Lemulip.app
verify_binary dist/lemulip
STAGING="$(mktemp -d "$ROOT_DIR/.build/LemulipRelease.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/$PACKAGE_NAME" "$STAGING/dmg"
cp -R dist/Lemulip.app "$STAGING/$PACKAGE_NAME/"
cp dist/lemulip "$STAGING/$PACKAGE_NAME/"
copy_public_guides "$STAGING/$PACKAGE_NAME"
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$STAGING/$PACKAGE_NAME" "$STAGING/$PACKAGE_NAME.zip"
cp -R dist/Lemulip.app "$STAGING/dmg/"
copy_public_guides "$STAGING/dmg"
ln -s /Applications "$STAGING/dmg/Applications"
/usr/bin/hdiutil create -volname Lemulip -srcfolder "$STAGING/dmg" -format UDZO "$STAGING/$PACKAGE_NAME.dmg"
python3 script/package_source.py
mv "$STAGING/$PACKAGE_NAME.zip" "$STAGING/$PACKAGE_NAME.dmg" dist/
cp docs/RELEASE_NOTES.md dist/RELEASE_NOTES.md
(cd dist && shasum -a 256 "$PACKAGE_NAME.zip" "$PACKAGE_NAME.dmg" "$SOURCE_NAME" > SHA256SUMS.txt)
echo "Release archives and checksums are in $ROOT_DIR/dist. Verify these exact files before publication."
