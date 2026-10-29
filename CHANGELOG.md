# Changelog

`Created: 11 October 2026` | `Last updated: 29 October 2026`

<br>

## Release 0.3.0

`Released: not yet`

### Live Activities

- Added charging and low battery announcements beside the camera, with the
  battery's level drawn as the iPhone draws it, yellow in Low Power Mode, on
  MacBooks. Low Battery shows at 20%, at 10% and when macOS warns of it, in
  place of macOS's own notification, which is taken away as it shows. As on
  the iPhone, it grows as tall as the Alarm, its level at the left and, at the
  right, the battery in a capsule, a ring pulsing around its level, pulsing
  from a reddish yellow into a soft red as it arrives. Clicking the capsule
  turns on Low Power Mode: it turns green, and it says `Low Power Mode On`.
- Added AirPods, headphones, keyboards, mice, trackpads and game controllers
  announced as they connect, as the iPhone shows AirPods: AirPods and Beats in
  3D, from Apple's and Beats' own models, turning as the iPhone turns AirPods,
  AirPods Max as macOS pictures them, others as their symbol, beside their
  battery as a ring. A device that doesn't tell its battery isn't announced.
  One whose battery runs down past 20% or 10% is announced the same way, its
  ring red with its level in numbers inside, in place of macOS's own banner,
  which is hidden, and AirPods' own notification, which is taken away.
- Added every live activity coming and going as the Dynamic Island's do:
  announcements, music's cover and waveform, a new song's name and the timer.
  The notch widens and folds with its springs, its wings' ends round as the
  island's do, and what it shows rides in and out with them, fading in out of a
  blur and away into one, under the notch at rest, which stays sharp over it. An
  announcement shows as long as the iPhone shows AirPods arriving. Between two,
  it folds to rest before opening for the next, and the pointer on it folds it
  away at once, the notch opening once it has. With Reduce Motion on, the notch
  widens without bouncing and nothing blurs. In full screen, the collapsed
  notch rounds into the Dynamic Island's capsule, outlined just inside its edge
  by a thin line in the activity's color, which fades out toward the top of the
  screen and as the notch expands.
- Changed every live activity, closed or opened, to keep the notch only as wide
  as the wider side needs, both sides alike, with nothing under the camera. Each
  side sits at its own end, as far in from it as from the top and bottom, so it
  follows the end's roundness, and on the taller views both ends alike; any
  room to spare is beside the camera. The notch widens or narrows as a timer
  or the stopwatch gains or loses a digit, as from hours to minutes.
- Changed the player, the tray and the lyrics to come and go with the same
  fade and blur as the notch opens, closes or turns its page, and a new song's
  cover to come in the same way as the last one goes.
- Added Clock's timer, from the Clock app, Control Center or Siri, counting down
  beside the camera as the iPhone's Timer does: a ring emptying beside the time
  left, in minutes from ten minutes up and in minutes and seconds under ten,
  with a pause symbol while paused, by the label it was given in Clock. Opened,
  it's as tall as the iPhone's expanded Timer, with buttons to pause and cancel
  it left of the camera, the time right of it and its name under the camera, at
  least as far in from the notch's ends as the player is. When it rings, the
  notch says so as the iPhone's Timer does, its name beside buttons to start it
  again or stop it, and rings with the timer's sound from Clock in place of
  macOS's own alert, which is taken away. Without `Accessibility`, macOS's
  alert chimes beside it, and the notch's buttons answer it. VoiceOver reads it
  as its name and the time left in words, and opens it.
- Added Clock's stopwatch, counting up beside the camera as the iPhone's does:
  its symbol with a hand going round once a minute, its hundredths small after
  the seconds. Opened, it shows its time alone, to the hundredth, with buttons
  to stop it and start it over from 0:00, or to start it again and reset it.
- Added files coming in over AirDrop as the iPhone shows them, from when one
  starts coming until it's in: AirDrop's symbol beside the camera and a ring
  filling as it comes. Opened, it shows a picture of the file, who it's from,
  and the ring around a button to stop it. `AirDrop` in
  **Settings > Live Activities** turns it off.
- Added sound going to AirPlay as the iPhone shows Screen Mirroring, for as
  long as it plays there: AirPlay's symbol in blue at the notch's left end, and
  the speaker or TV at its right. Opened, it shows the speaker's name, with
  **Stop AirPlay** to send the sound back to where it played before.
- Added swiping up with two fingers on the closed notch to swipe its live
  activity away, as on the iPhone, until it changes: music until the next song
  or until it plays again, a timer until it's started, paused or ended, AirDrop
  until the next file, AirPlay until the next speaker. An announcement folds
  away, and a timer that's ringing stops.
- Added the activities after the first in bubbles of their own beside the
  notch, as the Dynamic Island shows them: music keeps the notch, the next
  activity goes in a round bubble as tall as the notch off its right end, and
  the one after off its left. Each buds off the notch's end and runs back into
  it, and into it while a new song's name shows. Clicking a bubble opens its
  own activity. VoiceOver reads each as a button that opens it. With Reduce
  Motion on, bubbles fade in and out where they rest.
- Added Clock's buttons for its timer and stopwatch to the notch and its
  right-click menu, which work as Clock's own do, at once, with Clock opened
  hidden and quit half a minute after the last press. Without `Accessibility`,
  they're dimmed, and pressing one asks for it. While a timer shows, macOS's own
  is taken out of the menu bar. `Timers`, `Stopwatch` and `Hide in menu bar` in
  **Settings > Live Activities** turn each off, beside **Open Clock** and a way
  to Menu Bar settings to bring macOS's own timer back.
- Added a Live Activities page to Settings, to turn each one off, with a way to
  Music's own.
- Changed Music's Live Activities setting to Cover and waveform, so it isn't
  mistaken for the Live Activities page.

### Touch

- Added the notch on a MacBook Pro with Touch, and on an iPad's display over
  Sidecar. Tap the notch to open it, whatever `Open with` is set to, or a
  bubble to open its activity. Drag down to open it, up to close it, and
  sideways to change songs or scroll the tray, which glides on as you let go.
  Two fingers sideways on the open notch switch between the player and the
  tray. Opened with a finger, the notch stays open until you swipe it up, tap
  just outside it, switch to another app, or move the pointer onto it and away.
- Added the notch's menu, and each tray item's menu, on touch and hold.
- Changed the volume slider in the sound output menu to show its knob while a
  finger drags it.

### Player

- Changed the sound output menu to look like the Mac's Sound menu: the playing
  app's name and icon beside its volume, and each output in a circle, the one
  playing in the accent color, with the Mac's own speakers first. AirPods show
  each earbud's battery and the case's, and other headphones their one battery.
- Changed the cover's colors behind the player to move as the iPhone's do:
  softer patches of color, a little more vivid, drifting slowly through one
  another, two turning in place and two circling as they turn.
- Changed the waveform to show a gradient made from the cover's colors, as the
  iPhone's waveform does, each part of the cover's color in its part of the
  gradient, lighter and softer, in place of one color fading to gray.
- Added the cover's colors pulsing gently on the music's beat, as you hear it.
- Changed the waveform to move more softly, as the iPhone's does: each bar
  eases toward its level over a tenth of a second or so, rather than leaping
  to every hit.
- Fixed the waveform moving ahead of the music on AirPods and other wireless
  headphones, which play a moment late: it now waits for the sound, as the
  colors' pulse does.

### Opening

- Fixed the closed notch swelling under the pointer twice as much at its ends
  as at its bottom, with music's cover and waveform crowding its ends. It now
  swells as much all round, and they keep the same padding on every side.
- Fixed the player's words and buttons, the tray and the opened activities
  being cut off by the notch's edges, or pressed against them, while it opened
  and closed. They show only once the notch has room for them and their
  padding, as the cover and the waveform fly in.

<br>

## Release 0.2.0

`Released: 16 October 2026`

### Tray

- Added the tray: files dropped on the notch, and what you copy, newest first.
- Added clipboard history, kept for 30 minutes, 8 hours or 7 days, never
  keeping passwords.
- Added screenshots to the tray, as soon as each is saved.
- Added AirDrop beside the tray while something's dragged onto the notch.
- Added link previews to the tray, with each site's icon, fetched from the
  site's home page rather than the link itself.
- Added selecting items as Finder does: a click, ⌘-click for more, and
  Shift-click for a run.
- Added Quick Look and Share, with AirDrop in it, to each item's menu in the
  tray.
- Added the tray fitting its items on the player's padding, growing wider with
  what's in it from three items up to six with the next one peeking in, then
  scrolling, with two fingers or a mouse's wheel.
- Added a page of its first words for copied text, and where a link goes under
  its site's name, so no two items look alike.
- Added ⌘Z to bring back what was removed from the tray, for a minute.
- Added holding what's copied while the pointer is on the tray, so the row never
  moves under it.
- Added Keep to an item's menu, so a copy or screenshot stays until removed,
  marked with a pin.
- Added Open With to an item's menu, listing the apps that open it.
- Added Paste and Match Style to an item's menu, with Option held, to paste
  text without its style.
- Added typing an item's name to select it, as in Finder.
- Added a list in Settings of apps whose copies the tray never keeps.
- Added Glance Tray to the Services menu, in Finder and every other app.
- Added Glance Tray to the Share menu, for pictures, links, text and
  files from Safari, Photos, Finder and every other app that shares.
- Added a Tray page to Settings, and a step for the tray to the welcome tour.

### Opening

- Added ⇧⌘1 to open and close the player from any app, ahead of the app's
  own shortcuts.
- Added ⇧⌘2 to open and close the tray the same way.
- Added three fingers on the open notch, or Shift and a scroll, to switch
  between the player and the tray, either way round.
- Added opening the tray when something is dragged near the notch and held
  there a moment.
- Added keyboard shortcut settings in **Settings > Opening** to change them.
- Added the keyboard to the notch opened with a shortcut, or after a click in
  the tray: Escape, the arrows, Space and Return, and ⌘C, ⌘A, ⌘Delete and ⌘Z
  on the tray.

### Accessibility

- Made the notch opaque while Increase Contrast is on, with the player on
  plain black.
- Made covers and their colors hold still, and long titles stop scrolling,
  while Reduce Motion is on.
- Added names for VoiceOver and Voice Control to the player's buttons and
  progress bar, and actions to the tray's items.
- Dimmed clear glass by a third, so the player's times and buttons read over
  light windows.
- Made a new song's name, in the cover's color, light enough to read on the
  black notch.
- Dimmed the glass further on the tray, so the items' names read over light
  windows.
- Made the tray's items fade in and out, and the player and the tray swap with
  a fade, while Reduce Motion is on.

### Additional

- Added Undo, Redo, Delete, Zoom, Bring All to Front and Services to the menu
  bar, and moved Close to a File menu.
- Added two scenes to the welcome tour's pictures: the player turning between
  its two layouts until you choose one, and a photo dragged to the notch and
  dropped in the tray.

<br>

## Release 0.1.0

`Released: 11 October 2026`

### Player

- Added Now Playing in the notch, with customizable controls.
- Added two layouts, `Cover on top` and `Cover on the side`, and four
  backgrounds behind the player: `Replace glass`, `Fullscreen`, `Spotlight`, and
  `None`.
- Added Liquid Glass with adjustable darkness and blur, or the style set in
  System Settings, tinted by the cover or by the Mac's accent color.
- Added animated album covers from Apple Music, for songs playing in any app.

### Live Activities

- Added the cover and a waveform around the closed notch while something plays.
- Added a short announcement when something starts playing.

### Lyrics

- Added timed lyrics from LRCLIB beside the player.

### Opening

- Added opening by hover, click, or either, each with an optional delay.
- Added two-finger swipes to open and close the notch and to change songs.
- Added an optional haptic tap when the notch opens.

### Displays

- Added a notch or a Dynamic Island on displays without one.
- Added settings for where the notch shows, and for hiding it in full screen.
- Made the notch stay over the camera while swiping between desktops and
  full-screen apps.

### Additional

- Added a Settings window.
- Added a welcome tour on first launch.
- Added `Check for Updates…` and automatic updates from Glance's GitHub
  releases, through Sparkle.
