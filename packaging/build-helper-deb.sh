#!/bin/bash
# Builds com.foobtech.pantry-helper for both jailbreak layouts:
#   rootless (iOS 15+, Dopamine etc.)  -> iphoneos-arm64, files under /var/jb
#   rootful  (iOS 12-14 era)           -> iphoneos-arm,   files under /
# Needs macOS with Xcode command line tools, plus: brew install dpkg ldid
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
VERSION="0.1.0"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$OUT"

build_for() {
    local scheme="$1" prefix arch
    case "$scheme" in
        rootless) prefix="/var/jb"; arch="iphoneos-arm64" ;;
        rootful)  prefix="";        arch="iphoneos-arm" ;;
        *) echo "unknown scheme $scheme"; exit 1 ;;
    esac
    local stage="$OUT/helper-stage-$scheme"
    local bin="$stage$prefix/usr/libexec/pantry/pantry-helper"

    rm -rf "$stage"
    mkdir -p "$stage$prefix/usr/libexec/pantry" "$stage/DEBIAN"

    xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=11.0 -isysroot "$SDK" \
        -O2 -Wall -Wextra -DJBROOT="\"$prefix\"" -o "$bin" "$ROOT/helper/pantry-helper.c"
    ldid -S"$ROOT/helper/entitlements.plist" "$bin"
    chmod 4755 "$bin"

    cat > "$stage/DEBIAN/control" <<CONTROL
Package: com.foobtech.pantry-helper
Name: Pantry Helper
Version: $VERSION
Architecture: $arch
Section: System
Maintainer: foobtech
Description: Setuid-root helper used by Pantry to run dpkg
CONTROL

    cat > "$stage/DEBIAN/postinst" <<POSTINST
#!/bin/sh
chown root:wheel $prefix/usr/libexec/pantry/pantry-helper || true
chmod 4755 $prefix/usr/libexec/pantry/pantry-helper || true
mkdir -p /var/mobile/Library/Caches/com.foobtech.pantry || true
chown mobile:mobile /var/mobile/Library/Caches/com.foobtech.pantry || true
exit 0
POSTINST
    chmod 755 "$stage/DEBIAN/postinst"

    dpkg-deb -Zgzip --root-owner-group -b "$stage" "$OUT/com.foobtech.pantry-helper_${VERSION}_${arch}.deb"
    echo "Built: $OUT/com.foobtech.pantry-helper_${VERSION}_${arch}.deb"
}

for s in ${SCHEMES:-rootless rootful}; do build_for "$s"; done
