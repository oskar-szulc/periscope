#!/bin/sh
# Rewrite Sources and Tests in the repo's style (.swift-format).
set -eu
cd "$(dirname "$0")/.."
swift format -i -r Sources Tests
