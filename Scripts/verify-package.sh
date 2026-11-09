#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
verification="$(mktemp -d "${TMPDIR:-/tmp}/utility-verify.XXXXXX")"
trap 'rm -rf "$verification"' EXIT
unzip -q build/Macaroni-macOS.zip -d "$verification"
codesign --verify --deep --strict "$verification/Macaroni.app"
export UTILITY_DATA_HOME="$verification/Data"
export UTILITY_FIXTURES="$PWD/Fixtures"
"$verification/Macaroni.app/Contents/MacOS/Macaroni" --smoke-test
cp "$verification/Data/report.json" build/Release-Smoke.json
cat build/Release-Smoke.json
printf '\n'
shasum -a 256 build/Macaroni-macOS.zip
