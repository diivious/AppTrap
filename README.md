# AppTrap 2.0

AppTrap is a small macOS utility that cleans up the files applications leave behind when you throw the application in the Trash.

The original AppTrap project goes back quite a few years. Version 2.0 updates that code so it builds and runs on current macOS and Apple Silicon Macs.

I did not rewrite AppTrap or change what it is supposed to do. The goal was to get the existing project working cleanly again on current hardware and current versions of Xcode while preserving the original project history and credits.

## What does AppTrap do?

AppTrap runs in the background.

When you move an application to the Trash, AppTrap looks for files related to that application, such as:

- preferences
- caches
- Application Support files
- containers
- startup items

If AppTrap finds related files, it asks if you want to move those files to the Trash too.

It does not permanently delete them. They go to the Trash along with the application, so you can still recover them until the Trash is emptied.

The application you install is the AppTrap preference pane. The background AppTrap application is included inside it.

## What changed in 2.0?

The older AppTrap code was built around Intel Macs and much older versions of macOS and Xcode.

Version 2.0 includes the work needed to build and run it on current Apple Silicon systems.

The main changes are:

- Apple Silicon arm64 support
- current Xcode project settings
- current macOS API updates
- removal of the old Intel-only Sparkle dependency
- XCTest support in place of the old OCUnit/SenTestingKit tests
- updated Start on Login support using LaunchAgents
- fixes to the Xcode target dependencies
- support for upgrading from older AppTrap identifiers
- command-line build and release scripts

The production application and preference pane currently target macOS 13.0 or newer.

The test targets require macOS 14.0 or newer because of the XCTest libraries included with current Xcode.

## Requirements

To run AppTrap 2.0:

- Apple Silicon Mac
- macOS 13.0 or newer

To build AppTrap 2.0:

- Apple Silicon Mac
- Xcode
- Xcode command-line tools configured to use the full Xcode installation
- zsh

## Getting the source

Clone the repo:

```bash
git clone https://github.com/diivious/AppTrap.git
cd AppTrap
```

Or download the source ZIP from GitHub and extract it.

## Building AppTrap

There are three build modes.

### Build and validate everything

Run:

```bash
./build.sh
```

This builds and analyzes the main AppTrap application and preference pane, then builds both test targets.

If everything is good, the script ends with:

```text
AppTrap arm64 production targets, analysis, and XCTest bundles built successfully.
```

### Build the installable preference pane

Run:

```bash
./build.sh --release
```

This creates the preference pane, installer package, and DMG without Developer ID signing or notarization. I use this for local testing.

For a public release, use `./build.sh --dist` instead.

The preference pane is here:

```text
release/Build/Products/Release/AppTrap.prefPane
```

The file to publish on GitHub is:

```text
release/AppTrap-<version>.dmg
```

The DMG contains `Install AppTrap.pkg`. That is the normal install and upgrade path.

You do not install `AppTrap.app` separately. It is already inside the preference pane:

```text
AppTrap.prefPane/
└── Contents/
    └── Resources/
        └── AppTrap.app
```

## If xcodebuild cannot find Xcode

Check which developer directory is active:

```bash
xcode-select -p
```

If Xcode is installed at the normal location, set it with:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Then check it:

```bash
xcodebuild -version
```

If you keep Xcode somewhere else, use the actual path to `Xcode.app`.

## Installing AppTrap

After building the release:

```bash
./build.sh --release
```

open the DMG:

```bash
open release/AppTrap-2.0.dmg
```

Then double-click **Install AppTrap.pkg**.

The installer stops AppTrap and closes System Settings before replacing the preference pane. I added this because macOS can keep an old preference pane loaded even after the files on disk have been replaced. Closing System Settings first makes the next launch load the new pane.

After it is installed:

1. Open the AppTrap preference pane.
2. Click **Start AppTrap**.
3. Turn on **Start on Login** if you want AppTrap to start automatically when you log in.

## Upgrading from an older AppTrap version

If you already have an older version installed:

1. Download or build the new AppTrap DMG.
2. Open the DMG.
3. Run **Install AppTrap.pkg**.
4. Open System Settings and select AppTrap.
5. Start AppTrap again.
6. Check **Start on Login** if you use it.

The installer removes the previous preference pane before installing the new one and closes System Settings first. This handles the stale preference-pane problem during an upgrade.

AppTrap 2.0 knows about the older AppTrap bundle and LaunchAgent identifiers so an upgrade does not require starting completely from scratch.

The current identifiers are:

```text
se.diivious.AppTrap
se.diivious.AppTrap.prefpanel
```

## Uninstalling AppTrap

First:

1. Open the AppTrap preference pane.
2. Turn off **Start on Login**.
3. Stop AppTrap.

Then remove the AppTrap preference pane.

Depending on how it was installed, it will normally be in one of these locations:

```text
~/Library/PreferencePanes/AppTrap.prefPane
/Library/PreferencePanes/AppTrap.prefPane
```

AppTrap 2.0 stores its preferences here:

```text
~/Library/Preferences/se.diivious.AppTrap.plist
~/Library/Preferences/se.diivious.AppTrap.prefpanel.plist
```

The Start on Login LaunchAgent is:

```text
~/Library/LaunchAgents/se.diivious.AppTrap.plist
```

If you want a completely clean uninstall, those files can be removed after AppTrap has been stopped.

## Support for this version

AppTrap 2.0 is maintained here:

https://github.com/diivious/AppTrap

For bugs, build problems, or feature requests, use GitHub Issues:

https://github.com/diivious/AppTrap/issues

If you report a problem, please include:

- macOS version
- Mac model
- Xcode version if it is a build problem
- the error output
- what you were doing when the problem happened

AppTrap 2.0 checks the GitHub Releases page for updates. **Check for Update** checks immediately. **Automatically check for updates** remembers your setting and checks at most once every 24 hours when the preference pane is loaded.

If a newer release is available, AppTrap offers to download the release DMG to Downloads and open it. If System Settings cannot save directly to Downloads, AppTrap opens the download in your browser instead.

## Building for distribution

For a public release, use:

```bash
./build.sh --dist
```

This does the normal release build, then:

- signs the helper, embedded AppTrap application, and preference pane with Developer ID Application
- signs the installer package with Developer ID Installer
- signs the DMG
- sends the DMG to Apple's notarization service
- staples the notarization ticket
- runs Gatekeeper verification

Set these before running it:

```bash
export APPTRAP_APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPTRAP_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)"
export APPTRAP_NOTARY_PROFILE="AppTrap-notary"
```

The notary profile is a `notarytool` keychain profile. Create it once with Apple's `xcrun notarytool store-credentials` command.

The finished GitHub asset is:

```text
release/AppTrap-<version>.dmg
```

The GitHub release tag should match the version, for example `v2.0`, and the DMG should be named `AppTrap-2.0.dmg`.

`./build.sh --release` is still available when I only want an unsigned local test build.

## Project layout

```text
AppTrap/
├── AppTrap/                         background application
├── AppTrapPreferencePane/          preference pane
├── AppTrap.xcworkspace             Xcode workspace
├── build.sh                        build and release script
├── CHANGELOG.md                    release history
├── LICENSE                         original AppTrap license
└── README.md                       this file
```

## Credits

### Creator

Markus Amalthea Magnuson

### Current Developer

**Donnie Savage (@diivious)**

### Intel Version Developer

Kumaran Vijayan

### Additional code

- Håkan Waara
- M. Uli Kusterer, UKKqueue
- Unsanity, Smart Crash Reports

### Localization

- Alexander Henket, Dutch
- Ronald Leroux, French
- Vasco Patrício, Português

The original authorship, contributor credits, copyright, and license are being kept with the project.

## License

AppTrap is distributed under the original license included in [`LICENSE`](LICENSE).

Keep the original license with the source.
