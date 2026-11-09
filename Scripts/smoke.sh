#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/build.sh
scratch="$(mktemp -d "${TMPDIR:-/tmp}/utility-smoke.XXXXXX")"
export UTILITY_DATA_HOME="$scratch/Data"
export UTILITY_FIXTURES="$PWD/Fixtures"
build/Macaroni.app/Contents/MacOS/Macaroni --smoke-test
mkdir -p build/Smoke
cp -R "$scratch/Data/." build/Smoke/
cat build/Smoke/report.json
rm -rf "$scratch"
