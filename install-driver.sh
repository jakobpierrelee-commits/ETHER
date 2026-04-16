#!/bin/bash
# ─── Ether Driver Installer ───────────────────────────────────────────────
# Copies the built driver to /Library/Audio/Plug-Ins/HAL/ and restarts coreaudiod.
# Requires sudo.

set -e

DRIVER_NAME="EtherDriver.driver"
INSTALL_DIR="/Library/Audio/Plug-Ins/HAL"

# Find the built driver
BUILD_DIR=$(xcodebuild -project Ether.xcodeproj -scheme EtherDriver -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')
DRIVER_PATH="$BUILD_DIR/$DRIVER_NAME"

if [ ! -d "$DRIVER_PATH" ]; then
    echo "Error: Driver not found at $DRIVER_PATH"
    echo "Build it first: xcodebuild -scheme EtherDriver -configuration Debug build"
    exit 1
fi

echo "Installing $DRIVER_NAME to $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
sudo rm -rf "$INSTALL_DIR/$DRIVER_NAME"
sudo cp -R "$DRIVER_PATH" "$INSTALL_DIR/$DRIVER_NAME"
sudo chown -R root:wheel "$INSTALL_DIR/$DRIVER_NAME"

echo "Restarting coreaudiod..."
sudo launchctl kickstart -kp system/com.apple.audio.coreaudiod

echo ""
echo "Done. Ether virtual device should now appear in System Settings → Sound → Output."
echo "You can verify with: system_profiler SPAudioDataType | grep Ether"
