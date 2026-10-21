"""One-time source-name migration on the isolated refresh branch; removed before merge."""
from pathlib import Path

root = Path.cwd()
protected = 'FreewheelMainWindow'
for folder in ('Sources', 'Tests'):
    for path in (root / folder).rglob('*'):
        if not path.is_file() or 'LibarchiveHeaders' in path.parts:
            continue
        old = path.read_text()
        text = old.replace(protected, 'PRESERVED_WINDOW_AUTOSAVE_KEY')
        text = text.replace('Freewheel', 'Lemulip').replace('freewheel', 'lemulip').replace('FREEWHEEL', 'LEMULIP')
        text = text.replace('fw_', 'lemulip_').replace('FW_', 'LEMULIP_')
        text = text.replace('PRESERVED_WINDOW_AUTOSAVE_KEY', protected)
        if text != old:
            path.write_text(text)
    for path in sorted((root / folder).rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if 'Freewheel' in path.name:
            destination = path.with_name(path.name.replace('Freewheel', 'Lemulip'))
            if destination.exists():
                raise SystemExit('Refusing to replace an existing path: ' + str(destination))
            path.rename(destination)
package = root / 'Package.swift'
package.write_text(package.read_text().replace('Freewheel', 'Lemulip'))
for name in ('THIRD_PARTY_NOTICES.md', 'docs/DEVELOPMENT.md'):
    path = root / name
    text = path.read_text().replace('Sources/CFreewheelArchive', 'Sources/CLemulipArchive')
    text = text.replace('Sources/Freewheel', 'Sources/Lemulip').replace('Tests/Freewheel', 'Tests/Lemulip')
    path.write_text(text)
path = root / 'docs/DEVELOPMENT.md'
old = '''`FreewheelCore`, `CFreewheelArchive`, source-folder names, the bundle identifier
`app.freewheel.Freewheel`, preference keys, and saved-window key are retained
for compatibility. They are internal identifiers, not public branding. Renaming
them as a cosmetic change can break imports or existing settings.'''
new = '''Source folders, Swift modules, the C archive bridge, and the test target now
use **Lemulip** names: `LemulipCore`, `CLemulipArchive`, `LemulipCLI`, and
`LemulipCoreTests`. Source clients should import `LemulipCore`.

The bundle identifier `app.freewheel.Freewheel`, existing preference keys, and
`FreewheelMainWindow` autosave key deliberately remain unchanged so an upgrade
keeps the user's settings and window position. Installer checks for the old
process and the historical upgrade instructions also remain. These are narrowly
scoped compatibility identifiers, not unfinished public branding.

Run `python3 script/test_branding.py` to check module/path consistency and these
preserved settings. Do not globally replace the remaining compatibility names.'''
text = path.read_text()
assert old in text, 'Expected compatibility documentation changed; review before applying'
path.write_text(text.replace(old, new))
print('Renamed source modules and test paths; preserved settings and historical upgrade checks.')
