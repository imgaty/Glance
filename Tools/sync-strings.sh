#!/bin/zsh
# Brings Resources/Localizable.xcstrings up to date with the words in the code, as Xcode does when it
# builds: the compiler lists what's localizable, and new words join the catalog to be translated.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swift build --scratch-path "$WORK/build" --product Glance \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK/strings" >/dev/null
find "$WORK/strings" -name '*.stringsdata' -print0 | xargs -0 xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata
echo "Synced. The tests name anything still to translate."
