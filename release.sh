#!/bin/zsh
# Makes a new version of Glance and puts it on GitHub Releases, where Check for Updates… finds it.
# Two steps, with your commit in between; this script never commits or pushes.
#
#   ./release.sh 0.2.0            sets the version, builds Glance, packs it into dist/Glance.dmg,
#                                 signs that for Sparkle and adds it to updater/appcast.xml
#   (check the disk image, then commit and push the changes)
#   ./release.sh 0.2.0 --publish  uploads the disk image and the appcast as release v0.2.0;
#                                 everyone's Glance sees it from then on
#
# Needs the update key in your keychain with its public half in Resources/Info.plist, a
# "## Release 0.2.0" section in CHANGELOG.md for the release notes, and, to publish, gh logged in.
# CONTRIBUTING.md (Releasing) has the details.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
MODE="${2:-}"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ( -n "$MODE" && "$MODE" != "--publish" ) ]]; then
    echo "Usage: ./release.sh <x.y.z> [--publish]" >&2
    exit 64
fi

REPO=imgaty/Glance
TAG="v$VERSION"
PLIST=Resources/Info.plist
APPCAST=updater/appcast.xml
DMG=dist/Glance.dmg
fail() { echo "$1" >&2; exit 1; }

[[ -f CHANGELOG.md ]] || fail "There's no CHANGELOG.md."
# The release notes: the version's section of the changelog, without its date.
NOTES=$(awk -v heading="## Release $VERSION" '$0 == heading { on = 1; next } on && /^## / { exit } on && !/^`Released/ && $0 != "<br>"' CHANGELOG.md)
[[ -n "${NOTES//[[:space:]]/}" ]] || fail "CHANGELOG.md has no \"## Release $VERSION\" section."

# MARK: Publish

if [[ "$MODE" == "--publish" ]]; then
    command -v gh >/dev/null || fail "gh isn't installed: brew install gh"
    gh auth status >/dev/null 2>&1 || fail "gh isn't logged in: gh auth login"
    ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 || fail "$TAG is already released."
    [[ -f "$DMG" ]] && grep -q "<sparkle:shortVersionString>$VERSION<" "$APPCAST" \
        || fail "Run ./release.sh $VERSION first."
    # The release is tagged at what's on GitHub, so that has to be this version.
    [[ -z "$(git status --porcelain -- "$PLIST" "$APPCAST" CHANGELOG.md)" ]] \
        || fail "Commit $PLIST, $APPCAST and CHANGELOG.md first."
    git fetch --quiet origin main
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "Push to GitHub first."
    gh release create "$TAG" "$DMG" "$APPCAST" --repo "$REPO" --target "$(git rev-parse HEAD)" \
        --title "Glance $VERSION" --notes "$NOTES"
    echo "Released Glance $VERSION: https://github.com/$REPO/releases/tag/$TAG"
    exit 0
fi

# MARK: Prepare

/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST" >/dev/null 2>&1 \
    || fail "$PLIST has no SUPublicEDKey: see CONTRIBUTING.md, Releasing."

# Sparkle compares build numbers, so a new version gets the next one. Running this again for the
# same version keeps it.
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
if [[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")" != "$VERSION" ]]; then
    BUILD=$((BUILD + 1))
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$PLIST"

# The changelog's section is dated today, and so is the changelog.
python3 -I - "$VERSION" "$(LC_ALL=C date '+%-d %B %Y')" <<'PYTHON'
import re, sys

version, today = sys.argv[1:]
text = open("CHANGELOG.md", encoding="utf-8").read()
start = text.index(f"## Release {version}\n")
end = text.find("\n## ", start + 1)
end = len(text) if end < 0 else end
section = re.sub(r"`Released: [^`]*`", f"`Released: {today}`", text[start:end], count=1)
text = re.sub(r"`Last updated: [^`]*`", f"`Last updated: {today}`", text[:start] + section + text[end:], count=1)
open("CHANGELOG.md", "w", encoding="utf-8").write(text)
PYTHON

./build.sh --release

# The disk image: Glance and a link to Applications to drag it onto.
rm -rf dist/stage
mkdir -p dist/stage
ditto build/Glance.app dist/stage/Glance.app
ln -s /Applications dist/stage/Applications
rm -f "$DMG"
diskutil image create from --format ULFO --volumeName Glance dist/stage "$DMG" >/dev/null
rm -rf dist/stage

# Sparkle installs it only if this signature, made with the key in your keychain, checks out.
SIGNATURE=$(.build/artifacts/sparkle/Sparkle/bin/sign_update "$DMG")

python3 -I - "$APPCAST" "$VERSION" "$BUILD" "$SIGNATURE" "$NOTES" \
    "https://github.com/$REPO/releases/download/$TAG/Glance.dmg" \
    "$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST")" <<'PYTHON'
import html, re, sys
from email.utils import formatdate

appcast, version, build, signature, notes, url, minimum = sys.argv[1:]

def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)

# The changelog's section as simple HTML: its headings, paragraphs and lists.
blocks = []
for line in notes.splitlines():
    line = line.rstrip()
    if line.startswith("`Released") or line.strip() in ("", "<br>"):
        blocks.append(None)
    elif line.startswith("### "):
        blocks.append(["h3", line[4:]])
    elif line.startswith("- "):
        blocks.append(["li", line[2:]])
    elif blocks and blocks[-1] and blocks[-1][0] in ("li", "p"):
        blocks[-1][1] += " " + line.strip()
    else:
        blocks.append(["p", line.strip()])
parts, in_list = [], False
for block in blocks:
    if in_list and (block is None or block[0] != "li"):
        parts.append("</ul>")
        in_list = False
    if block is None:
        continue
    if block[0] == "li" and not in_list:
        parts.append("<ul>")
        in_list = True
    parts.append(f"<{block[0]}>{inline(block[1])}</{block[0]}>")
if in_list:
    parts.append("</ul>")

item = f"""    <item>
      <title>Glance {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minimum}</sparkle:minimumSystemVersion>
      <description><![CDATA[{"".join(parts)}]]></description>
      <enclosure url="{url}" {signature} type="application/octet-stream"/>
    </item>
"""

text = open(appcast, encoding="utf-8").read()
# Made again for the same version: the old entry goes.
text = re.sub(
    r"    <item>\n(?:(?!    </item>).*\n)*?\s*<sparkle:shortVersionString>"
    + re.escape(version)
    + r"</sparkle:shortVersionString>\n(?:.*\n)*?    </item>\n",
    "",
    text,
)
marker = "-->\n"
at = text.index(marker, text.index("<!-- Releases")) + len(marker)
open(appcast, "w", encoding="utf-8").write(text[:at] + item + text[at:])
PYTHON

echo
echo "Glance $VERSION (build $BUILD) is ready: $DMG"
echo "Open it to check, commit and push the changes, then run: ./release.sh $VERSION --publish"
