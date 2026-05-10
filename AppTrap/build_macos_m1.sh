#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$root_dir"

xcodebuild \
  -project AppTrap/AppTrap.xcodeproj \
  -scheme AppTrap \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build

xcodebuild \
  -project AppTrapPreferencePane/AppTrapPreferencePane.xcodeproj \
  -scheme AppTrapPreferencePane \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build
