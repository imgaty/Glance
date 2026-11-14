# Features

`Created: 11 October 2026` | `Last updated: 14 November 2026`

Glance's current, planned, and rejected features.

<br>

## Current features

### Now Playing

Whatever is playing, in almost any app, with its cover, a progress bar to drag
through the song, and buttons to play, pause and skip. You choose in Settings
which apps show. Click the cover to go where it plays from: its browser tab, or
the playlist it plays from in Spotify or Music. While Spotify's DJ chooses the
music, its symbol takes a button's place, moving as the DJ talks. See the
[User Manual](USER-MANUAL.md#the-player).

### Tray

Drag files onto the notch to keep them close, and find what you copied and your
screenshots and screen recordings, newest first. Click something to select it,
double-click to paste it, drag it out, or send it with AirDrop. Copies stay for
30 minutes, 8 hours or 7 days, unless you keep them, and passwords never do.
Open items with any app, add things from any app's Share or Services menu, and
choose apps whose copies stay out. ⌥⇧2 opens it, or three fingers on the open
notch, and it grows wider with what it keeps. See the [User
Manual](USER-MANUAL.md#the-tray).

### Opening the notch

Hover over it, click it, or either, with an optional delay. Swipe down with two
fingers to open it, up to close it, and sideways to change songs. From any app,
⌥⇧1 opens it with the player and ⌥⇧2 with the tray, or shortcuts of your
choice, and the keyboard works it until it closes. On a MacBook Pro with Touch,
or an iPad over Sidecar, tap it, drag it the same ways with a finger, and touch
and hold it for its menu. See the
[User Manual](USER-MANUAL.md#opening-and-closing).

### Layouts and backgrounds

Two layouts and three backgrounds for the player, on Liquid Glass or a blur, in
the cover's colors or your Mac's accent color, pulsing on the music's biggest
hits.

### Live Activities

While something plays, the closed notch shows its cover and a waveform that
moves with the music. When a new song starts, its name slides out for a moment.
As on the iPhone, it also shows the battery charging or running low, AirPods
and Beats connecting, and files coming in or going out over AirDrop and sound
playing over AirPlay, both with a button to stop them. It counts Clock's timer
down and its stopwatch up, with their buttons, and shows the screen or a voice
memo being recorded, with a button to stop it. With several at once, the first
keeps the left of the notch and the second goes in a bubble of its own off the
right, as on the iPhone.
Clock alarms appear when an identifiable ringing alert is available, with the
actions that alert actually offers. Printing shows your active local print
jobs. Focus changes appear as short announcements. Choose **Recognize Music**
from Glance's menu to start a ShazamKit session, or **Run Shortcut** to run a
shortcut and keep its state and result beside the camera.
See the [User Manual](USER-MANUAL.md#live-activities).

### Timed lyrics

Click the waveform to see the words beside the player, lit line by line as
they're sung. They come from [LRCLIB](https://lrclib.net), and only show when
they match the song.

### Animated covers

Apple Music's animated album covers, whichever app is playing the song.

### Displays without a notch

Macs without a notch get one, and so do external displays, which can be left
out in Settings.

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

**Clock's alarms.** Glance observes identifiable ringing notifications and the
menu-bar alarm through Accessibility. Menu-bar alarms offer Open Clock; only
notifications with advertised actions offer Stop or Snooze. Glance cannot
read the scheduled alarm list or infer a snoozed
countdown. Native Clock alerts remain available when observation or controls
are unavailable.

**Printing.** Only your active jobs reported by the local CUPS spooler appear.
Page progress depends on what the printer reports; no percentage is invented.

**Music recognition.** Recognition starts only when requested and requires
microphone permission, a network connection and ShazamKit service availability.
It does not observe sessions started in Control Center.

**Running shortcuts.** Glance tracks only shortcuts started from its own menu.
It cannot observe runs started elsewhere. Stopping requests interruption; the
activity waits for the process to finish before reporting its outcome.

**Other system activities.** SharePlay, Screen Sharing, Journal recording,
automatic AirPods routing offers and forwarded iPhone activities remain with
macOS. Their cross-app state or actions are not available through a verified
integration. Glance does not hide them.

<br>

## Roadmap

- [x] `Animated covers`: Apple Music's animated album covers.
- [x] `More Live Activities`: battery, devices, Clock's timer and stopwatch, recordings.
- [x] `Displays without a notch`: a notch on any display.
- [x] `Now Playing`: whatever is playing, in any app, with its controls.
- [x] `Shortcuts`: shortcuts to open the player and the tray.
- [x] `Timed lyrics`: the words beside the player, line by line.
- [x] `Tray`: files you drop and what you copy, on the notch.
- [x] `Updates`: check for updates, and install them automatically.
- [x] `Calls`: FaceTime and iPhone calls beside the camera, in place of macOS's
  popup.
- [ ] `AI overview`: AI usage and a chat box on the notch.
- [ ] `Homebrew`: install with `brew install --cask glance`.
- [ ] `Notarized releases`: open the first time without the extra step.

<br>

## Rejected

### Connectivity announcements

The iPhone's Dynamic Island shows nothing when Wi-Fi or a Personal Hotspot
connects or drops, so Glance doesn't either. The menu bar already shows the
connection.

### Other devices connecting

Keyboards, mice, trackpads, game controllers and other makers' headphones and
speakers aren't announced. Of the devices connecting, Apple is only known to
show AirPods on the Dynamic Island, so Glance keeps to AirPods and Beats.

### Spotify favorites

Spotify's AppleScript commands can't like a song the way Music's can. Its Web
API can, but only after you sign in to Spotify inside Glance, with Glance
registered as a Spotify developer app. That's a lot of setup, and a lot of
access to your account, for one heart button.
