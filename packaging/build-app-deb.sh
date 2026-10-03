#!/bin/bash
# Builds the Pantry app once, then packages it for both jailbreak layouts (see build-helper-deb.sh).
# Needs macOS with Xcode, plus: brew install xcodegen ldid dpkg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
VERSION="0.1.0"
mkdir -p "$OUT"
rm -rf "$OUT/dd"

cd "$ROOT"
xcodegen generate
xcodebuild -project Pantry.xcodeproj -scheme Pantry -sdk iphoneos -configuration Release \
    -derivedDataPath "$OUT/dd" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
APP="$OUT/dd/Build/Products/Release-iphoneos/Pantry.app"

package_for() {
    local scheme="$1" prefix arch
    case "$scheme" in
        rootless) prefix="/var/jb"; arch="iphoneos-arm64" ;;
        rootful)  prefix="";        arch="iphoneos-arm" ;;
        *) echo "unknown scheme $scheme"; exit 1 ;;
    esac
    local stage="$OUT/app-stage-$scheme"
    local dest="$stage$prefix/Applications/Pantry.app"

    rm -rf "$stage"
    mkdir -p "$stage$prefix/Applications" "$stage/DEBIAN"
    cp -R "$APP" "$dest"
    ldid -S"$ROOT/App/entitlements.plist" "$dest/Pantry"
    # iOS 12.0-12.1 have no system Swift runtime, so Xcode bundles the dylibs; they need fake-signing too.
    if [ -d "$dest/Frameworks" ]; then
        find "$dest/Frameworks" -name '*.dylib' -exec ldid -S {} \;
    fi

    cat > "$stage/DEBIAN/control" <<CONTROL
Package: com.foobtech.pantry
Name: Pantry
Version: $VERSION
Architecture: $arch
Section: Package Managers
Depends: com.foobtech.pantry-helper
Maintainer: foobtech
Description: The adapting iOS APT front-end
CONTROL

    cat > "$stage/DEBIAN/postinst" <<POSTINST
#!/bin/sh
$prefix/usr/bin/uicache -p $prefix/Applications/Pantry.app || true
exit 0
POSTINST
    chmod 755 "$stage/DEBIAN/postinst"

    dpkg-deb -Zgzip --root-owner-group -b "$stage" "$OUT/com.foobtech.pantry_${VERSION}_${arch}.deb"
    echo "Built: $OUT/com.foobtech.pantry_${VERSION}_${arch}.deb"
}

for s in ${SCHEMES:-rootless rootful}; do package_for "$s"; done
