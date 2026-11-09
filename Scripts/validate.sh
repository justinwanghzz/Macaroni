#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/test.sh > .test-log 2>&1
Scripts/smoke.sh > .smoke-log 2>&1
Scripts/package.sh > .package-log 2>&1
printf 'Tests, app integration, and packaging passed.\n'
