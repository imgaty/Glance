# Features

`Created: 11 October 2026` | `Last updated: 11 October 2026`

Glance's current, planned, and rejected features.

<br>

## Current features

### Now Playing

Whatever is playing, in almost any app, with its cover, a progress bar to drag
through the song, and buttons to play, pause and skip. You choose in Settings
which apps show. See the [User Manual](USER-MANUAL.md#the-player).

### Opening the notch

Hover over it, click it, or either, with an optional delay. Swipe down with two
fingers to open it, up to close it, and sideways to change songs. See the
[User Manual](USER-MANUAL.md#opening-and-closing).

### Layouts and backgrounds

Two layouts and four backgrounds for the player, on Liquid Glass or a blur, in
the cover's colors or your Mac's accent color.

### Live Activities

While something plays, the closed notch shows its cover and a waveform that
moves with the music. When a new song starts, its name slides out for a moment.

### Timed lyrics

Click the waveform to see the words beside the player, lit line by line as
they're sung. They come from [LRCLIB](https://lrclib.net), and only show when
they match the song.

### Animated covers

Apple Music's animated album covers, whichever app is playing the song.

### Displays without a notch

External displays and Macs without a notch get a notch or a Dynamic Island.

### Updates

Glance checks for a new version once a day and installs it on its own. See the
[User Manual](USER-MANUAL.md#updates).

<br>

## Known limitations

**Apple silicon only.** Glance needs an Apple silicon Mac with macOS 26 or
later.

**Shuffle, repeat and favorites.** They work in `Music` and `Spotify`
(favorites in `Music` only); for other apps the buttons show dimmed.

<br>

## Roadmap

- [x] `Animated covers`: Apple Music's animated album covers.
- [x] `Displays without a notch`: a notch or a Dynamic Island on any display.
- [x] `Now Playing`: whatever is playing, in any app, with its controls.
- [x] `Timed lyrics`: the words beside the player, line by line.
- [x] `Updates`: check for updates, and install them automatically.
- [ ] `AI overview`: AI usage and a chat box on the notch.
- [ ] `Homebrew`: install with `brew install --cask glance`.
- [ ] `More Live Activities`: connectivity, battery, calls, timers and more.
- [ ] `Notarized releases`: open the first time without the extra step.
- [ ] `Shortcuts`: shortcuts to switch between notch tools.
- [ ] `Tray`: a clipboard tray on the notch.

<br>

## Rejected

### Spotify favorites

Spotify's AppleScript commands can't like a song the way Music's can. Its Web
API can, but only after you sign in to Spotify inside Glance, with Glance
registered as a Spotify developer app. That's a lot of setup, and a lot of
access to your account, for one heart button.
