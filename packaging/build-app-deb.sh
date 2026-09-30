#!/bin/bash
# Builds the Pantry app as a rootless (iphoneos-arm64) .deb.
# Needs macOS with Xcode, plus: brew install xcodegen ldid dpkg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
STAGE="$OUT/app-stage"
VERSION="0.1.0"

rm -rf "$STAGE" "$OUT/dd"
mkdir -p "$STAGE/var/jb/Applications" "$STAGE/DEBIAN"

cd "$ROOT"
xcodegen generate
xcodebuild -project Pantry.xcodeproj -scheme Pantry -sdk iphoneos -configuration Release \
    -derivedDataPath "$OUT/dd" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

APP="$OUT/dd/Build/Products/Release-iphoneos/Pantry.app"
cp -R "$APP" "$STAGE/var/jb/Applications/Pantry.app"
ldid -S"$ROOT/App/entitlements.plist" "$STAGE/var/jb/Applications/Pantry.app/Pantry"

cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: com.foobtech.pantry
Name: Pantry
Version: $VERSION
Architecture: iphoneos-arm64
Section: Package Managers
Depends: com.foobtech.pantry-helper
Maintainer: foobtech
Description: The adapting iOS APT front-end
CONTROL

cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
/var/jb/usr/bin/uicache -p /var/jb/Applications/Pantry.app || true
exit 0
POSTINST
chmod 755 "$STAGE/DEBIAN/postinst"

dpkg-deb -Zgzip --root-owner-group -b "$STAGE" "$OUT/com.foobtech.pantry_${VERSION}_iphoneos-arm64.deb"
echo "Built: $OUT/com.foobtech.pantry_${VERSION}_iphoneos-arm64.deb"
