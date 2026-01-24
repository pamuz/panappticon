#!/bin/bash
set -euo pipefail

APP_NAME="Panappticon"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building ${APP_NAME} in release mode..."
swift build -c release

echo "Creating app bundle at ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy the release binary
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist, adding NSAccessibilityUsageDescription if missing
if grep -q "NSAccessibilityUsageDescription" Resources/Info.plist; then
    cp Resources/Info.plist "${CONTENTS_DIR}/Info.plist"
else
    # Insert NSAccessibilityUsageDescription before closing </dict>
    sed '/<\/dict>/i\
\    <key>NSAccessibilityUsageDescription</key>\
\    <string>Panappticon needs Accessibility access to observe window positions and sizes.</string>
' Resources/Info.plist > "${CONTENTS_DIR}/Info.plist"
fi

echo "Code signing..."
codesign -s - --force --deep "${APP_BUNDLE}"

echo ""
echo "Done! Run the app with:"
echo "  open ${APP_BUNDLE}"
