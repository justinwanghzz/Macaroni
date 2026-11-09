#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || (${1:-} != "" && ${1:-} != "--universal") ]]; then
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 2
fi
Scripts/build.sh release
# Stage outside iCloud: Finder/file-provider attributes can invalidate a strict
# signature check when attached to the generated app folder after signing.
staging="$(mktemp -d "${TMPDIR:-/tmp}/utility-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto --norsrc --noextattr --noqtn build/Macaroni.app "$staging/Macaroni.app"
xattr -cr "$staging/Macaroni.app"
codesign --force --deep --sign - "$staging/Macaroni.app"
codesign --verify --deep --strict "$staging/Macaroni.app"
ditto -c -k --norsrc --noextattr --keepParent "$staging/Macaroni.app" build/Macaroni-macOS.zip
printf 'Packaged build/Macaroni-macOS.zip\n'

if [[ ${1:-} != "--universal" ]]; then
    exit 0
fi

app="$staging/Macaroni.app"
executable="$app/Contents/MacOS/Macaroni"
case "$(lipo -archs "$executable")" in
    arm64) other_arch=x86_64 ;;
    x86_64) other_arch=arm64 ;;
    *) printf 'Expected a single native architecture in %s\n' "$executable" >&2; exit 1 ;;
esac
scratch="$PWD/.build/universal-$other_arch"
export CLANG_MODULE_CACHE_PATH="$scratch/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$scratch/module-cache"
build_args=(--disable-sandbox -c release --triple "$other_arch-apple-macosx14.0"
    --scratch-path "$scratch" --cache-path "$scratch/cache"
    --config-path "$scratch/config" --security-path "$scratch/security")
swift build "${build_args[@]}"
other_bin="$(swift build "${build_args[@]}" --show-bin-path)"
lipo -create "$executable" "$other_bin/UtilityApp" -output "$staging/Macaroni-universal"
mv "$staging/Macaroni-universal" "$executable"
archs="$(lipo -archs "$executable")"
if [[ "$archs" != "x86_64 arm64" && "$archs" != "arm64 x86_64" ]]; then
    printf 'Expected both macOS architectures, got: %s\n' "$archs" >&2
    exit 1
fi

universal="$staging/Macaroni Universal.app"
mv "$app" "$universal"
codesign --force --deep --sign - "$universal"
codesign --verify --deep --strict --all-architectures "$universal"
ditto -c -k --norsrc --noextattr --keepParent "$universal" build/Macaroni-Universal-macOS.zip
printf 'Packaged build/Macaroni-Universal-macOS.zip (%s)\n' "$archs"
