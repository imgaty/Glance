# Changelog

`Created: 11 October 2026` | `Last updated: 24 October 2026`

<br>

## Release 0.2.1

`Released: not yet`

### Player

- Fixed Spotify's DJ not showing in the player: while the DJ chooses the music,
  its symbol takes the left button's place, drawn as Spotify draws it, its
  corner moving as the DJ talks. Clicking it switches to Spotify.
- Fixed shuffle and repeat looking available while Spotify's DJ or a podcast
  plays, when Spotify doesn't offer them.
- Fixed the waveform not keeping the song's time: its color rises to the top of
  its bars on each beat, and its bars fall back at the song's pace.
- Fixed the cover's colors behind the player standing still through the song:
  they pulse with the beat, as in Apple Music.

### Tray

- Fixed the photo in the tray's demo being enlarged from a smaller picture.

### Settings

- Fixed toggles and the `Layout` choice lagging on the Settings pages with the
  notch's preview.

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
