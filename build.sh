#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$root_dir"

app_project="$root_dir/AppTrap/AppTrap.xcodeproj/project.pbxproj"
pref_project="$root_dir/AppTrapPreferencePane/AppTrapPreferencePane.xcodeproj/project.pbxproj"

if grep -q 'MACOSX_DEPLOYMENT_TARGET = 26\.0;' "$app_project" "$pref_project"; then
    echo "ERROR: A deployment target was changed to macOS 26.0."
    echo "Production targets should remain compatible with macOS 13.0."
    exit 2
fi

usage() {
    echo "Usage:"
    echo "  ./build.sh             Build/analyze production targets and build test bundles"
    echo "  ./build.sh --release   Build distributable Release AppTrap.prefPane"
}

build_release() {
    local release_dir="$root_dir/release"
    local product="$release_dir/Build/Products/Release/AppTrap.prefPane"
    local embedded_app="$product/Contents/Resources/AppTrap.app"

    echo
    echo "== Building distributable AppTrap.prefPane =="
    echo "Output: $product"
    echo

    rm -rf "$release_dir"

    xcodebuild \
      -workspace AppTrap.xcworkspace \
      -scheme AppTrapPreferencePane \
      -configuration Release \
      -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "$release_dir" \
      clean build

    if [[ ! -d "$product" ]]; then
        echo "ERROR: Release build succeeded but AppTrap.prefPane was not found:"
        echo "  $product"
        exit 3
    fi

    if [[ ! -d "$embedded_app" ]]; then
        echo "ERROR: AppTrap.prefPane is missing its embedded AppTrap.app:"
        echo "  $embedded_app"
        exit 4
    fi

    echo
    echo "== Release build succeeded =="
    echo "Preference pane:"
    echo "  $product"
    echo
    echo "Embedded application:"
    echo "  $embedded_app"
    echo
    echo "Install/test with:"
    echo "  open \"$product\""
}

case "${1:-}" in
    --release)
        if (( $# != 1 )); then
            usage
            exit 64
        fi
        build_release
        exit 0
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    "")
        ;;
    *)
        echo "ERROR: Unknown option: $1"
        usage
        exit 64
        ;;
esac

derived_data="${TMPDIR:-/tmp}/AppTrapDerivedData"
rm -rf "$derived_data"

common=(
  -workspace AppTrap.xcworkspace
  -configuration Release
  -destination 'platform=macOS,arch=arm64'
  -derivedDataPath "$derived_data"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)

echo
echo "== Building AppTrap =="
xcodebuild "${common[@]}" -scheme AppTrap clean build analyze

echo
echo "== Building AppTrapPreferencePane =="
xcodebuild "${common[@]}" -scheme AppTrapPreferencePane build analyze

echo
echo "== Building AppTrapTests =="
xcodebuild \
  -workspace AppTrap.xcworkspace \
  -scheme AppTrapTests \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build-for-testing

echo
echo "== Building PrefPaneTests =="
# -derivedDataPath cannot be used with -target in Xcode 26.
# Use SYMROOT/OBJROOT instead so the target-only build remains isolated.
xcodebuild \
  -project AppTrapPreferencePane/AppTrapPreferencePane.xcodeproj \
  -target PrefPaneTests \
  -configuration Debug \
  -sdk macosx \
  -arch arm64 \
  SYMROOT="$derived_data/PrefPaneTests/Build/Products" \
  OBJROOT="$derived_data/PrefPaneTests/Build/Intermediates.noindex" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

echo
echo "AppTrap arm64 production targets, analysis, and XCTest bundles built successfully."
