#!/usr/bin/env bash
# ─── Ether Driver Installer ───────────────────────────────────────────────
# Builds the driver Release + signs with Developer ID + installs to HAL path
# + kickstarts coreaudiod + verifies the device appears.
#
# Requires sudo (prompts interactively).
set -euo pipefail

cd "$(dirname "$0")"

DEV_ID="Developer ID Application: Black Team, LLC (WDH3LXHAAD)"
DRIVER_NAME="EtherDriver.driver"
INSTALL_DIR="/Library/Audio/Plug-Ins/HAL"

# ── Regenerate Xcode project in case project.yml changed ──────────────
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

# ── Build Release ─────────────────────────────────────────────────────
echo "→ Building EtherDriver (Release, signed with Developer ID)…"
rm -rf build/DriverBuild
xcodebuild \
  -project Ether.xcodeproj \
  -scheme EtherDriver \
  -configuration Release \
  -derivedDataPath build/DriverBuild \
  CODE_SIGN_IDENTITY="${DEV_ID}" \
  CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  DEVELOPMENT_TEAM=WDH3LXHAAD \
  clean build \
  >/dev/null

BUILT_DRIVER="build/DriverBuild/Build/Products/Release/${DRIVER_NAME}"
if [ ! -d "$BUILT_DRIVER" ]; then
    echo "✗ Driver build product missing at $BUILT_DRIVER"
    exit 1
fi

# ── Force re-sign (Xcode's signing sometimes skips nested mach-o) ─────
echo "→ Re-signing driver bundle…"
codesign --force --sign "${DEV_ID}" --timestamp --options=runtime "$BUILT_DRIVER"

# ── Verify signature ──────────────────────────────────────────────────
echo "→ Verifying signature…"
codesign --verify --deep --strict --verbose=1 "$BUILT_DRIVER"
codesign -dvvv "$BUILT_DRIVER" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier|flags" | head -6

# ── Install to HAL path ───────────────────────────────────────────────
echo "→ Installing to ${INSTALL_DIR}/${DRIVER_NAME}…"
sudo mkdir -p "$INSTALL_DIR"
sudo rm -rf "$INSTALL_DIR/$DRIVER_NAME"
sudo cp -R "$BUILT_DRIVER" "$INSTALL_DIR/$DRIVER_NAME"
sudo chown -R root:wheel "$INSTALL_DIR/$DRIVER_NAME"

# ── Restart coreaudiod (launchctl kickstart is SIP-blocked, killall works) ──
echo "→ Restarting coreaudiod…"
sudo killall coreaudiod

# ── Give it a beat, then probe ────────────────────────────────────────
sleep 2
echo ""
echo "→ Probing system_profiler for the Ether device…"
if system_profiler SPAudioDataType 2>/dev/null | grep -A1 -E "^\s+Ether:" >/dev/null; then
    echo "✓ Ether device is live and registered."
    system_profiler SPAudioDataType 2>/dev/null | grep -A8 -E "^\s+Ether:" | head -15
else
    echo "✗ Ether device NOT visible yet. Check logs:"
    echo "  log show --last 1m --predicate 'subsystem == \"audio.ether.driver\"'"
    echo "  log show --last 1m --predicate 'process == \"coreaudiod\"' | grep -i ether"
    exit 2
fi
