# Changelog

## 2.0

AppTrap 2.0 is the first release of the current Apple Silicon version.

Changes from the older Intel release:

- added Apple Silicon arm64 support
- updated the project for current macOS and Xcode
- kept the production target at macOS 13.0 or newer
- removed the old Intel-only Sparkle framework
- replaced OCUnit/SenTestingKit tests with XCTest
- updated deprecated macOS APIs
- updated Start on Login to use a LaunchAgent
- added migration support for older AppTrap identifiers
- added GitHub-based update checks
- added the installer package and DMG release build
- added Developer ID signing and notarization support through `./build.sh --dist`
- fixed the AppTrap and preference-pane build dependencies
- cleaned up the old duplicated project and generated documentation
- kept the original project credits and license
