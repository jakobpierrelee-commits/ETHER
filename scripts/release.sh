#!/usr/bin/env bash
# Builds, signs, notarizes, and staples a Developer ID DMG for distribution.
# Usage:
#   scripts/release.sh              # rebuild current version
#   scripts/release.sh 1.1.0        # bump version, rebuild
set -euo pipefail

cd "$(dirname "$0")/.."

# ── Config ────────────────────────────────────────────────────────────
DEV_ID="Developer ID Application: Black Team, LLC (WDH3LXHAAD)"
NOTARY_PROFILE="ether-notary"   # xcrun notarytool store-credentials name
BUNDLE_ID="audio.ether.app"

# ── Version bump (optional) ───────────────────────────────────────────
NEW_VERSION="${1:-}"
if [[ -n "$NEW_VERSION" ]]; then
  /usr/bin/sed -i '' -E "s/MARKETING_VERSION: \"[^\"]+\"/MARKETING_VERSION: \"${NEW_VERSION}\"/" project.yml
  CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION' project.yml | head -1 | sed -E 's/.*"([0-9]+)".*/\1/')
  NEXT_BUILD=$((CURRENT_BUILD + 1))
  /usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[0-9]+\"/CURRENT_PROJECT_VERSION: \"${NEXT_BUILD}\"/" project.yml
  xcodegen generate >/dev/null
  echo "→ Bumped to v${NEW_VERSION} (build ${NEXT_BUILD})"
fi

# ── Build (hardened runtime + Developer ID) ───────────────────────────
echo "→ Building Release with hardened runtime…"
rm -rf build/DerivedData build/dmg-staging
xcodebuild \
  -project Ether.xcodeproj \
  -scheme Ether \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="${DEV_ID}" \
  CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  DEVELOPMENT_TEAM=WDH3LXHAAD \
  clean build \
  >/dev/null

APP="build/DerivedData/Build/Products/Release/Ether.app"
VERSION=$(defaults read "$PWD/${APP}/Contents/Info" CFBundleShortVersionString)

# ── Re-sign Sparkle internals inside-out (Xcode doesn't reach nested XPC/helper binaries) ──
echo "→ Re-signing Sparkle framework internals…"
SPARKLE="${APP}/Contents/Frameworks/Sparkle.framework/Versions/B"
for binary in \
  "${SPARKLE}/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
  "${SPARKLE}/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
  "${SPARKLE}/Autoupdate" \
  "${SPARKLE}/Updater.app/Contents/MacOS/Updater"; do
  codesign --force --sign "${DEV_ID}" --timestamp --options=runtime "$binary"
done
for bundle in \
  "${SPARKLE}/XPCServices/Downloader.xpc" \
  "${SPARKLE}/XPCServices/Installer.xpc" \
  "${SPARKLE}/Updater.app" \
  "${APP}/Contents/Frameworks/Sparkle.framework"; do
  codesign --force --sign "${DEV_ID}" --timestamp --options=runtime "$bundle"
done
codesign --force --sign "${DEV_ID}" --timestamp --options=runtime "$APP"

# ── Verify app signature ──────────────────────────────────────────────
echo "→ Verifying app signature…"
codesign --verify --deep --strict --verbose=1 "$APP"

# ── Stage DMG ─────────────────────────────────────────────────────────
DMG="build/Ether-${VERSION}.dmg"
echo "→ Staging DMG…"
mkdir -p build/dmg-staging
cp -R "$APP" build/dmg-staging/
ln -s /Applications build/dmg-staging/Applications

rm -f "$DMG"
hdiutil create \
  -volname "Ether ${VERSION}" \
  -srcfolder build/dmg-staging \
  -ov -format UDZO \
  "$DMG" >/dev/null

# ── Sign the DMG ──────────────────────────────────────────────────────
echo "→ Signing DMG…"
codesign --sign "${DEV_ID}" --timestamp "$DMG"

# ── Notarize ──────────────────────────────────────────────────────────
echo "→ Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$DMG" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

# ── Staple ticket into the DMG ────────────────────────────────────────
echo "→ Stapling…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

SIZE=$(du -h "$DMG" | cut -f1)

# ── Update appcast.xml ─────────────────────────────────────────────────
echo "→ Updating appcast.xml…"
BUILD=$(defaults read "$PWD/${APP}/Contents/Info" CFBundleVersion)
TODAY=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
SIG_LINE=$(scripts/sparkle-tools/sign_update "$DMG")
DMG_SIZE=$(stat -f%z "$DMG")
ED_SIG=$(echo "$SIG_LINE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)

NEW_ITEM="        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${TODAY}</pubDate>
            <sparkle:releaseNotesLink>https://github.com/jakobpierrelee-commits/ETHER/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url=\"https://github.com/jakobpierrelee-commits/ETHER/releases/download/v${VERSION}/Ether-${VERSION}.dmg\"
                sparkle:edSignature=\"${ED_SIG}\"
                length=\"${DMG_SIZE}\"
                type=\"application/octet-stream\"/>
        </item>"

# Inject new item after <language>en</language> line
python3 -c "
import sys
content = open('appcast.xml').read()
marker = '</language>'
idx = content.find(marker)
if idx == -1:
    print('ERROR: marker not found', file=sys.stderr)
    sys.exit(1)
insert_at = idx + len(marker)
print(content[:insert_at] + '\n\n' + sys.argv[1] + '\n' + content[insert_at:], end='')
" "$NEW_ITEM" > appcast.xml.tmp && mv appcast.xml.tmp appcast.xml

echo ""
echo "✓ Done — $DMG ($SIZE)"
echo "  appcast.xml updated. Next steps:"
echo "  1. Upload $DMG to GitHub Releases as v${VERSION}"
echo "  2. Commit and push appcast.xml"
