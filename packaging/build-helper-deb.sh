#!/bin/bash
# Builds com.foobtech.pantry-helper as a rootless (iphoneos-arm64) .deb.
# Needs macOS with Xcode command line tools, plus: brew install dpkg ldid
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
STAGE="$OUT/stage"
VERSION="0.1.0"
BIN_DIR="$STAGE/var/jb/usr/libexec/pantry"

rm -rf "$OUT"
mkdir -p "$BIN_DIR" "$STAGE/DEBIAN"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=11.0 -isysroot "$SDK" \
    -O2 -Wall -Wextra -o "$BIN_DIR/pantry-helper" "$ROOT/helper/pantry-helper.c"

ldid -S"$ROOT/helper/entitlements.plist" "$BIN_DIR/pantry-helper"
chmod 4755 "$BIN_DIR/pantry-helper"

cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: com.foobtech.pantry-helper
Name: Pantry Helper
Version: $VERSION
Architecture: iphoneos-arm64
Section: System
Maintainer: foobtech
Description: Setuid-root helper used by Pantry to run dpkg
CONTROL

cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
chown root:wheel /var/jb/usr/libexec/pantry/pantry-helper || true
chmod 4755 /var/jb/usr/libexec/pantry/pantry-helper || true
mkdir -p /var/mobile/Library/Caches/com.foobtech.pantry || true
chown mobile:mobile /var/mobile/Library/Caches/com.foobtech.pantry || true
exit 0
POSTINST
chmod 755 "$STAGE/DEBIAN/postinst"

dpkg-deb -Zgzip --root-owner-group -b "$STAGE" "$OUT/com.foobtech.pantry-helper_${VERSION}_iphoneos-arm64.deb"
echo "Built: $OUT/com.foobtech.pantry-helper_${VERSION}_iphoneos-arm64.deb"
