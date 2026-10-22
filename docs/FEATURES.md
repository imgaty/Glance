# Features

`Created: 11 October 2026` | `Last updated: 24 October 2026`

Glance's current, planned, and rejected features.

<br>

## Current features

### Now Playing

Whatever is playing, in almost any app, with its cover, a progress bar to drag
through the song, and buttons to play, pause and skip. You choose in Settings
which apps show. While Spotify's DJ chooses the music, its symbol takes a
button's place, moving as the DJ talks. See the
[User Manual](USER-MANUAL.md#the-player).

### Tray

Drag files onto the notch to keep them close, and find what you copied and
your screenshots, newest first. Click something to select it, double-click to
paste it, drag it out, or send it with AirDrop. Copies stay for 30 minutes,
8 hours or 7 days, unless you keep them, and passwords never do. Open items
with any app, add things from any app's Share or Services menu, and choose apps
whose copies stay out. ⇧⌘2 opens it, or three fingers on the open notch, and it
grows wider with what it keeps. See the
[User Manual](USER-MANUAL.md#the-tray).

### Opening the notch

Hover over it, click it, or either, with an optional delay. Swipe down with two
fingers to open it, up to close it, and sideways to change songs. From any app,
⇧⌘1 opens it with the player and ⇧⌘2 with the tray, or shortcuts of your
choice, and the keyboard works it until it closes. See the
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
(favorites in `Music` only); for other apps, and in `Spotify` while its DJ or a
podcast plays, the buttons show dimmed.

**Copies from other devices.** What you copy on an iPhone or iPad, through
Universal Clipboard, isn't kept in the tray.

<br>

## Roadmap

- [x] `Animated covers`: Apple Music's animated album covers.
- [x] `Displays without a notch`: a notch or a Dynamic Island on any display.
- [x] `Now Playing`: whatever is playing, in any app, with its controls.
- [x] `Shortcuts`: shortcuts to open the player and the tray.
- [x] `Timed lyrics`: the words beside the player, line by line.
- [x] `Tray`: files you drop and what you copy, on the notch.
- [x] `Updates`: check for updates, and install them automatically.
- [ ] `AI overview`: AI usage and a chat box on the notch.
- [ ] `Homebrew`: install with `brew install --cask glance`.
- [ ] `More Live Activities`: connectivity, battery, calls, timers and more.
- [ ] `Notarized releases`: open the first time without the extra step.

<br>

## Rejected

### Spotify favorites

Spotify's AppleScript commands can't like a song the way Music's can. Its Web
API can, but only after you sign in to Spotify inside Glance, with Glance
registered as a Spotify developer app. That's a lot of setup, and a lot of
access to your account, for one heart button.
