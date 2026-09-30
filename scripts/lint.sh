#!/bin/sh
# Formatting and lint check (CI runs this). Fix with scripts/format.sh.
set -eu
cd "$(dirname "$0")/.."
swift format lint --strict -r Sources Tests
