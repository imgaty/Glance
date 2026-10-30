# Contributing

`Created: 11 October 2026` | `Last updated: 30 October 2026`

A guide to contributing to the Glance project.

<br>

## Project scope

Glance turns the notch into a place for anything worth a glance, starting with
what's playing. It should feel like Apple made it: native SwiftUI and AppKit,
Liquid Glass, SF Symbols, and Apple's spacing and wording.

A feature fits when it's worth seeing at a glance or reaching from the notch,
would look at home in macOS, and works without an account or a server of
Glance's own. Check [Features](docs/FEATURES.md) first, in case it's already
planned or rejected. Glance's only dependency is
[Sparkle](https://sparkle-project.org), for updates; anything else should come
from macOS.

<br>

## Project structure

```text
├── assets/screenshots/       # Documentation screenshots
├── docs/                     # Features and user manual
├── Resources/
│   ├── AppIcon.icon/         # The app icon's layers, for Icon Composer
│   ├── Info.plist            # Info.plist, with the update feed and key
│   └── GlanceShare-*         # The Share extension's Info.plist and sandbox
├── Sources/
│   ├── Glance/
│   │   ├── App/              # Entry point, settings, menu bar, updates
│   │   ├── Media/            # Now Playing, scripting, lyrics, audio
│   │   ├── Notch/            # The notch's window and view
│   │   ├── Onboarding/       # The welcome tour and the permissions
│   │   ├── Player/           # The player and its controls
│   │   ├── Settings/         # The Settings window and pages
│   │   └── Tray/             # The tray: files dropped and what's copied
│   ├── GlanceShare/          # Glance Tray, in the Share menu
│   └── NowPlayingHelper/     # Reads Now Playing inside perl
├── Tests/GlanceTests/        # Unit tests
├── updater/appcast.xml       # Every release, for Check for Updates…
├── build.sh                  # Builds and signs Glance.app
└── release.sh                # Makes and publishes a release
```

<br>

## Running Glance

Building needs Xcode 26 or later, on an Apple silicon Mac with macOS 26 or
later. This builds `build/Glance.app` and opens it with the welcome tour:

```sh
./build.sh --run
```

`Package.swift` also opens in Xcode.

### Why the Share extension hands over on a pasteboard

Every app extension runs in a sandbox, so `GlanceShare` can't reach the tray
itself. It leaves what's shared on a pasteboard of Glance's own, tells Glance
with a distributed notification, and waits for Glance's answer before it
finishes, so a file the sharing app made only for the moment is kept first.

### Why NowPlayingHelper runs inside perl

Since macOS 15.4, MediaRemote, the private framework behind Control Center's
media controls, only answers processes signed by Apple. `/usr/bin/perl` is one,
and can load a library, so Glance runs its Now Playing reader inside it.

<br>

## Before a pull request

1. Run the tests with `swift test`, or `Cmd U` in Xcode.
2. Format the code:

   ```sh
   xcrun swift-format format --in-place --recursive \
       --configuration .swift-format Sources Tests
   ```

3. Keep the look Apple's: SF Symbols, system controls, and Apple's spacing and
   wording.
4. Don't rename a key in `Preferences` without moving its old value over, or
   everyone loses that setting.
5. Record your changes in `CHANGELOG.md`, under the next version.

For anything larger than a bug fix, open an
[issue](https://github.com/imgaty/Glance/issues) first.

<br>

## Releasing

Releases are disk images on
[GitHub Releases](https://github.com/imgaty/Glance/releases), each with the
`appcast.xml` that Glance reads through Sparkle to find new versions.

### The update key, once

Sparkle only installs updates signed with Glance's key. Create it, and copy the
public key it prints into `Resources/Info.plist` as `SUPublicEDKey`:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

The private key stays in your keychain. Back it up somewhere safe: without it,
no copy of Glance out there can be updated again.

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x glance-update-key
```

### Each release

1. Add a `## Release x.y.z` section to `CHANGELOG.md`. It becomes the release
   notes.
2. Run `./release.sh x.y.z`. It sets the version, builds Glance, packs and signs
   `dist/Glance.dmg`, and adds it to `updater/appcast.xml`.
3. Open `dist/Glance.dmg` and check that Glance works.
4. Commit and push.
5. Run `./release.sh x.y.z --publish` to put it on GitHub. Every copy of Glance
   finds it from then on.
