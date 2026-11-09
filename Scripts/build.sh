#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
configuration="${1:-debug}"
swift build --disable-sandbox -c "$configuration" --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security
bin="$(swift build --disable-sandbox -c "$configuration" --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security --show-bin-path)"
staging="$(mktemp -d "${TMPDIR:-/tmp}/utility-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Macaroni.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/UtilityApp" "$app/Contents/MacOS/Macaroni"
# SwiftPM's bundle accessor checks the executable's containing bundle.
for resource in "$bin"/*.bundle; do
    [ -d "$resource" ] || continue
    ditto --norsrc --noextattr --noqtn "$resource" "$app/Contents/Resources/$(basename "$resource")"
done
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp Config/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Config/Info.plist "$app/Contents/Info.plist"
xattr -cr "$app"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
mkdir -p build
rm -rf build/Macaroni.app
ditto --norsrc --noextattr --noqtn "$app" build/Macaroni.app
printf 'Built %s\n' "$PWD/build/Macaroni.app"
