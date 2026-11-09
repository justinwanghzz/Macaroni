#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
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
