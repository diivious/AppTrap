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
    cat <<'EOF'
Usage:
  ./build.sh             Build/analyze production targets and build test bundles
  ./build.sh --release   Build an unsigned AppTrap.prefPane, installer package, and DMG
  ./build.sh --dist      Build, sign, notarize, and verify the release DMG

--dist requires:
  APPTRAP_APP_SIGN_IDENTITY
  APPTRAP_INSTALLER_SIGN_IDENTITY
  APPTRAP_NOTARY_PROFILE

Example:
  export APPTRAP_APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
  export APPTRAP_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)"
  export APPTRAP_NOTARY_PROFILE="AppTrap-notary"
  ./build.sh --dist
EOF
}

plist_value() {
    local plist="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist"
}

verify_release_versions() {
    local product="$1"
    local embedded_app="$2"

    local pane_version pane_build app_version app_build

    pane_version="$(plist_value "$product/Contents/Info.plist" CFBundleShortVersionString)"
    pane_build="$(plist_value "$product/Contents/Info.plist" CFBundleVersion)"
    app_version="$(plist_value "$embedded_app/Contents/Info.plist" CFBundleShortVersionString)"
    app_build="$(plist_value "$embedded_app/Contents/Info.plist" CFBundleVersion)"

    [[ -n "$pane_version" && -n "$pane_build" ]] || {
        echo "ERROR: Could not read preference pane version."
        exit 5
    }

    if [[ "$pane_version" != "$app_version" || "$pane_build" != "$app_build" ]]; then
        echo "ERROR: Release versions do not match."
        echo "Preference pane: $pane_version ($pane_build)"
        echo "Embedded app:    $app_version ($app_build)"
        exit 6
    fi

    echo "$pane_version"
}

write_preinstall_script() {
    local scripts_dir="$1"

    cat > "$scripts_dir/preinstall" <<'EOF'
#!/bin/zsh
set -u

/usr/bin/killall "System Settings" >/dev/null 2>&1 || true
/usr/bin/killall "System Preferences" >/dev/null 2>&1 || true
/usr/bin/killall AppTrap >/dev/null 2>&1 || true

/bin/rm -rf "/Library/PreferencePanes/AppTrap.prefPane"

console_user=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)
if [[ -n "$console_user" && "$console_user" != "root" && "$console_user" != "loginwindow" ]]; then
    user_home=$(/usr/bin/dscl . -read "/Users/$console_user" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')
    if [[ -n "$user_home" ]]; then
        /bin/rm -rf "$user_home/Library/PreferencePanes/AppTrap.prefPane"
    fi
fi

exit 0
EOF

    chmod +x "$scripts_dir/preinstall"
}

sign_release_bundles() {
    local product="$1"
    local embedded_app="$2"
    local app_identity="$3"

    local relaunch="$embedded_app/Contents/Resources/RelaunchObjC"

    if [[ -f "$relaunch" ]]; then
        /usr/bin/codesign \
          --force \
          --options runtime \
          --timestamp \
          --sign "$app_identity" \
          "$relaunch"
    fi

    /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$app_identity" \
      "$embedded_app"

    /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$app_identity" \
      "$product"

    /usr/bin/codesign --verify --deep --strict --verbose=2 "$product"
}

build_release() {
    local mode="${1:-release}"
    local signed_dist=0

    if [[ "$mode" == "dist" ]]; then
        signed_dist=1
    fi

    local release_dir="$root_dir/release"
    local product="$release_dir/Build/Products/Release/AppTrap.prefPane"
    local embedded_app="$product/Contents/Resources/AppTrap.app"

    echo
    if (( signed_dist )); then
        echo "== Building signed AppTrap distribution =="
    else
        echo "== Building AppTrap release =="
    fi
    echo

    rm -rf "$release_dir"

    xcodebuild \
      -workspace AppTrap.xcworkspace \
      -scheme AppTrapPreferencePane \
      -configuration Release \
      -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "$release_dir" \
      clean build

    [[ -d "$product" ]] || {
        echo "ERROR: Missing $product"
        exit 3
    }

    [[ -d "$embedded_app" ]] || {
        echo "ERROR: Missing embedded AppTrap.app"
        exit 4
    }

    local version
    version="$(verify_release_versions "$product" "$embedded_app")"

    local app_identity=""
    local installer_identity=""
    local notary_profile=""

    if (( signed_dist )); then
        app_identity="${APPTRAP_APP_SIGN_IDENTITY:-}"
        installer_identity="${APPTRAP_INSTALLER_SIGN_IDENTITY:-}"
        notary_profile="${APPTRAP_NOTARY_PROFILE:-}"

        [[ -n "$app_identity" ]] || {
            echo "ERROR: APPTRAP_APP_SIGN_IDENTITY is not set."
            exit 10
        }

        [[ -n "$installer_identity" ]] || {
            echo "ERROR: APPTRAP_INSTALLER_SIGN_IDENTITY is not set."
            exit 11
        }

        [[ -n "$notary_profile" ]] || {
            echo "ERROR: APPTRAP_NOTARY_PROFILE is not set."
            exit 12
        }

        echo
        echo "== Signing AppTrap bundles =="
        sign_release_bundles "$product" "$embedded_app" "$app_identity"
    fi

    local dist_dir="$release_dir/dist"
    local pkg_root="$dist_dir/pkgroot"
    local scripts_dir="$dist_dir/scripts"
    local dmg_root="$dist_dir/dmg"
    local package="$dmg_root/Install AppTrap.pkg"
    local dmg="$release_dir/AppTrap-${version}.dmg"

    mkdir -p "$pkg_root/Library/PreferencePanes" "$scripts_dir" "$dmg_root"
    ditto "$product" "$pkg_root/Library/PreferencePanes/AppTrap.prefPane"

    write_preinstall_script "$scripts_dir"

    local pkg_args=(
      --root "$pkg_root"
      --scripts "$scripts_dir"
      --identifier "se.diivious.AppTrap.installer"
      --version "$version"
      --ownership recommended
    )

    if (( signed_dist )); then
        pkg_args+=(--sign "$installer_identity")
    fi

    pkgbuild "${pkg_args[@]}" "$package"

    if (( signed_dist )); then
        /usr/sbin/pkgutil --check-signature "$package"
    fi

    cat > "$dmg_root/README.txt" <<EOF
AppTrap $version

Double-click "Install AppTrap.pkg" to install or upgrade AppTrap.

The installer closes System Settings and stops AppTrap before replacing the
preference pane. This prevents System Settings from continuing to display a
copy of the old pane that was already loaded before the upgrade.

After installation, open System Settings and select AppTrap.

Support:
https://github.com/diivious/AppTrap
EOF

    hdiutil create \
      -volname "AppTrap $version" \
      -srcfolder "$dmg_root" \
      -ov \
      -format UDZO \
      "$dmg" >/dev/null

    [[ -f "$dmg" ]] || {
        echo "ERROR: DMG was not created."
        exit 7
    }

    if (( signed_dist )); then
        echo
        echo "== Signing DMG =="

        /usr/bin/codesign \
          --force \
          --timestamp \
          --sign "$app_identity" \
          "$dmg"

        /usr/bin/codesign --verify --verbose=2 "$dmg"

        echo
        echo "== Notarizing DMG =="

        xcrun notarytool submit \
          "$dmg" \
          --keychain-profile "$notary_profile" \
          --wait

        echo
        echo "== Stapling notarization ticket =="

        xcrun stapler staple "$dmg"
        xcrun stapler validate "$dmg"

        echo
        echo "== Gatekeeper verification =="

        spctl \
          --assess \
          --type open \
          --context context:primary-signature \
          --verbose=2 \
          "$dmg"
    fi

    echo
    if (( signed_dist )); then
        echo "== Distribution build succeeded =="
    else
        echo "== Release build succeeded =="
    fi

    echo "Version:"
    echo "  $version"
    echo
    echo "Preference pane:"
    echo "  $product"
    echo
    echo "Installer package:"
    echo "  $package"
    echo
    echo "GitHub release asset:"
    echo "  $dmg"

    if (( ! signed_dist )); then
        echo
        echo "NOTE: This release is not Developer ID signed or notarized."
        echo "Use ./build.sh --dist for a public release."
    fi

    echo
    echo "Open with:"
    echo "  open \"$dmg\""
}

case "${1:-}" in
    --release)
        (( $# == 1 )) || { usage; exit 64; }
        build_release release
        exit 0
        ;;
    --dist)
        (( $# == 1 )) || { usage; exit 64; }
        build_release dist
        exit 0
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    "") ;;
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
