#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Cytisus-Trading"
EXECUTABLE_NAME="CytisusTrading"
DMG_NAME="Cytisus-Trading-1.1.7-universal.dmg"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_ROOT="$BUILD_DIR/dmg-root"
DIST_DIR="$PROJECT_DIR/dist"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
MODULE_CACHE="$BUILD_DIR/module-cache"
SIGNING_IDENTITY=${DEVELOPER_ID_APPLICATION_IDENTITY:--}
NOTARY_KEYCHAIN_PROFILE=${NOTARY_PROFILE:-}
SOURCE_FILES=("$PROJECT_DIR"/Sources/**/*.swift(N))

if (( ${#SOURCE_FILES[@]} == 0 )); then
  print -u2 "No Swift source files were found"
  exit 2
fi

mkdir -p "$BUILD_DIR" "$DIST_DIR"
rm -rf "$APP_BUNDLE" "$DMG_ROOT" "$MODULE_CACHE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$DMG_ROOT"
mkdir -p "$MODULE_CACHE"

swiftc -parse-as-library -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE/arm64" \
  -framework SwiftUI -framework AppKit -framework Security \
  "${SOURCE_FILES[@]}" \
  -o "$BUILD_DIR/$EXECUTABLE_NAME-arm64"

swiftc -parse-as-library -O \
  -target x86_64-apple-macosx14.0 \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE/x86_64" \
  -framework SwiftUI -framework AppKit -framework Security \
  "${SOURCE_FILES[@]}" \
  -o "$BUILD_DIR/$EXECUTABLE_NAME-x86_64"

lipo -create "$BUILD_DIR/$EXECUTABLE_NAME-arm64" "$BUILD_DIR/$EXECUTABLE_NAME-x86_64" \
  -output "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

sips -Z 896 "$PROJECT_DIR/Resources/ProductLogo.png" \
  --out "$BUILD_DIR/icon_scaled.png" >/dev/null
sips -p 1024 1024 --padColor 020617 "$BUILD_DIR/icon_scaled.png" \
  --out "$BUILD_DIR/icon_1024.png" >/dev/null
cp "$BUILD_DIR/icon_1024.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
cp "$PROJECT_DIR/Resources/ProductLogo.png" "$APP_BUNDLE/Contents/Resources/ProductLogo.png"

cp "$PROJECT_DIR/PRIVACY.md" "$APP_BUNDLE/Contents/Resources/PRIVACY.md"
cp "$PROJECT_DIR/SANITIZATION.json" "$APP_BUNDLE/Contents/Resources/SANITIZATION.json"
mkdir -p "$APP_BUNDLE/Contents/Resources/fixtures"
cp -R "$PROJECT_DIR/fixtures/." "$APP_BUNDLE/Contents/Resources/fixtures/"
chmod 755 "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  codesign --force --deep --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
fi

cp -R "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$PROJECT_DIR/INSTALL.txt" "$DMG_ROOT/INSTALL.txt"

rm -f "$DIST_DIR/$DMG_NAME"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov "$DIST_DIR/$DMG_NAME"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" \
    "$DIST_DIR/$DMG_NAME"
fi

if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    print -u2 "NOTARY_PROFILE requires a Developer ID Application identity"
    exit 2
  fi
  xcrun notarytool submit "$DIST_DIR/$DMG_NAME" \
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait
  xcrun stapler staple "$DIST_DIR/$DMG_NAME"
  xcrun stapler validate "$DIST_DIR/$DMG_NAME"
fi

shasum -a 256 "$DIST_DIR/$DMG_NAME"
