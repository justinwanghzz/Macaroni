#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/build.sh
review_dir="$(mktemp -d "${TMPDIR:-/tmp}/utility-review-ui.XXXXXX")"
ditto --norsrc --noextattr --noqtn build/Macaroni.app "$review_dir/Review.app"
plutil -replace CFBundleIdentifier -string org.local.UtilityApp.Review "$review_dir/Review.app/Contents/Info.plist"
xattr -cr "$review_dir/Review.app"
codesign --force --deep --sign - "$review_dir/Review.app"
printf '%s' "$review_dir" > /private/tmp/utility-review-ui-current
printf 'Isolated review folder: %s\n' "$review_dir"
export UTILITY_REVIEW_HOLD=1
export UTILITY_DATA_HOME="$review_dir/Data"
export UTILITY_FIXTURES="$PWD/Fixtures"
"$review_dir/Review.app/Contents/MacOS/Macaroni" --smoke-test
