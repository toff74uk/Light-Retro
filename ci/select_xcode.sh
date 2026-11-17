#!/bin/bash
set -euo pipefail
xcode_path=$(find /Applications -maxdepth 1 -name 'Xcode_26*.app' | sort -V | tail -1)
if [ -z "$xcode_path" ]; then echo 'Xcode 26 is required on this build runner.' >&2; exit 1; fi
sudo xcode-select -s "$xcode_path/Contents/Developer"
xcodebuild -version
