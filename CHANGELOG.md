# Changelog

`Created: 11 October 2026` | `Last updated: 8 November 2026`

<br>

## Release 0.3.0

`Released: not yet`

### Live Activities

- Changed a timer that's done to go from the notch by itself after ten seconds,
  its ringing with it, as **✕** would, rather than ringing for up to five
  minutes. It stays while the pointer is on it.
- Added `Hide macOS's Live Activities` to **Settings > Live Activities**, on at
  first: macOS 27.3's own Live Activities in the menu bar, such as Now Playing,
  are turned off in **System Settings > Menu Bar** as they first show, so they
  show only in the notch, and turned back on when it's turned off.
- Added calls: one coming in shows as tall as the Alarm, with the caller, a red
  button to decline and a green one to accept, in place of macOS's popup; on a
  call, a green phone and its time beside the camera, and a waveform of both
  voices, the other person's green from the left and yours orange from the
  right, each crossing the whole waveform and fading as it goes, yellow where
  they overlap. Opened, a FaceTime or Phone call shows the caller's photo from
  Contacts, or their initial in a purple to teal circle, their name and the
  call's time, and under them buttons for the sound output, video, which is off,
  muting your microphone, going to the call and ending it. A call in another app
  opens to one row: the caller's name, the sound output and, where Glance can
  press the app's own, ending it. Your microphone is unmuted when the call ends,
  if Glance muted it. Opening and closing, what it shows fades out and in, the
  same for every app. With music or anything else going on, whichever started
  second shows in a bubble beside the notch. FaceTime and Phone calls are read
  from macOS's own popup, which needs `Screen & System Audio Recording`; Zoom,
  Discord, WhatsApp and others show once they use the microphone. Turn it off
  with `Calls` in **Settings > Live Activities**.
- Added charging and low battery announcements beside the camera, with the
  battery's level drawn as the iPhone draws it, yellow in Low Power Mode, on
  MacBooks. Low Battery shows at 20%, at 10% and when macOS warns of it, in
  place of macOS's own notification, which is taken away as it shows. As on
  the iPhone, it grows as tall as the Alarm, its level at the left and, at the
  right, the battery in a capsule, a ripple running out of its level every two
  seconds. Clicking the capsule turns on Low Power Mode: it turns yellow, the
  ripple stops, and it says `Low Power Mode enabled`. Clicking it again turns
  it off.
- Added AirPods and Beats announced as they connect, as the iPhone shows them:
  in 3D, from Apple's and Beats' own models, turning as the iPhone turns AirPods,
  beside their battery as a ring. A device with no such model, such as AirPods 1
  and 2 and older Beats, isn't shown, and macOS's own banner stays for it. With the pointer on it, it extends to show its
  name and its level in numbers, the device and its ring growing into place.
  One whose battery runs down past 20% or 10% is announced the same way, its
  ring red with its level in numbers inside, in place of macOS's own banner,
  which is hidden, and AirPods' own notification, which is taken away. With
  `Accessibility` allowed, macOS's banner under the menu bar for AirPods
  connecting or running low is hidden too.
- Added a low battery alert of its own for the charging case of AirPods and
  Beats earbuds: at 20% and again at 10%, the case on its own, closed and turning
  in 3D, from Apple's and Beats' own models, beside its red ring. It starts from
  the front, holding still a moment. It's the only time the case shows, never as
  the earbuds connect.
- Changed everything open or tall in the notch to one set of bottom corners,
  concentric with what's round at its ends, top corners that grow with its
  height, and one padding all around. Closed, the notch keeps the camera housing's
  own corners.
- Changed the volume slider to Apple's own, with its Liquid Glass knob, filled
  with the Mac's accent color in light mode and white in dark mode.
- Changed opening with two live activities showing: the notch or the bubble opens
  once the pointer stops on it, so passing over them opens neither, and a click
  on the bubble follows `Open with`, as one on the notch does. Opened from the
  notch, the bubble first runs back into the notch's end, as on the iPhone, and
  buds off again once the notch has closed; what showed beside the camera slides
  out to its place and back, as it does with no bubble, rather than fading.
- Changed `Hide in full screen` on a Mac with a notch: rather than sliding away,
  the notch folds back to the camera with nothing beside it, and still opens from
  there as usual. On a display with no camera, it hides with the menu bar.
- Changed what's tall in the notch to stand on its glass, as the player does:
  the taller it is, the more glass shows.
- Changed everything open or tall in the notch to the player's type, with one
  size for the title, one for the line under it, and one for a time.
- Added every live activity coming and going as the Dynamic Island's do:
  announcements, music's cover and waveform, a new song's name and the timer.
  The notch widens and folds with its springs, its wings' ends round as the
  island's do, and what it shows rides in and out with them, fading in out of a
  blur and away into one, under the notch at rest, which stays sharp over it. An
  announcement shows as long as the iPhone shows AirPods arriving. Between two,
  it folds to rest before opening for the next, and the pointer on it folds it
  away at once, the notch opening once it has. Opening and closing are the same
  for the player, the tray, the lyrics, every live activity and an announcement
  as tall as the Alarm: the notch grows with a touch of bounce as what it shows
  grows out of a blur, and folds without one. With Reduce Motion on, the notch
  widens without bouncing and nothing blurs.
- Added every language macOS comes in, 36 in all: Glance follows the language
  macOS shows it in, and its words for macOS's own settings are macOS's.
- Added right to left in Arabic and Hebrew: the notch, Settings, the welcome tour and
  the tray's row mirror, and so do the arrows, swipes and scrolling that move through
  them. Playback stays left to right: the progress bar, previous and next, and the
  swipe between songs.
- Added each language and region's own digits to times and percentages.
- Added the keyboard to live activities, lyrics and the sound: with the notch
  opened from its shortcut, the up and down arrows go from the player to a timer's,
  the stopwatch's, AirDrop's or AirPlay's own view and back, where Tab and Space
  work its buttons; Tab reaches the lyrics, the arrows go from line to line and
  Space or Return plays from there; and on `Sound Output` the arrows turn the
  playing app's sound up or down.
- Changed the names in the tray to a stronger shadow, so they read over light
  windows.
- Changed the welcome tour to open on Glance's own icon, with every symbol drawn
  alike, page dots easier to click, and `Announce new audio` and
  `Keep what you copy` dimmed while what they need is off, as Settings has them.
- Changed everything else that moves to follow Reduce Motion: the notch's swell,
  press and swipes, the bubbles, the buttons and the cover settle without
  bouncing, the star glows without swelling, the skip arrows stay where they are,
  Customize Controls fades rather than scales, and the welcome tour's pages fade
  rather than slide.
- Changed every live activity, closed or opened, to keep the notch only as wide
  as the wider side needs, both sides alike, with nothing under the camera. Each
  side sits at its own end, as far in from it as from the top and bottom, so it
  follows the end's roundness, and on the taller views both ends alike; any
  room to spare is beside the camera. The notch widens or narrows as a timer
  or the stopwatch gains or loses a digit, as from hours to minutes.
- Changed a new song's cover to come in the same way as the last one goes.
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
  and the ring around a button to stop it. Files you send show the same way,
  once they're accepted. `AirDrop` in **Settings > Live Activities** turns it
  off.
- Added sound going to AirPlay as the iPhone shows Screen Mirroring, for as
  long as it plays there: AirPlay's symbol in blue at the notch's left end, and
  the speaker or TV at its right. Opened, it shows the speaker's name, with
  **Stop AirPlay** to send the sound back to where it played before.
- Added swiping up with two fingers on the closed notch to swipe its live
  activity away, as on the iPhone, until it changes: music until the next song
  or until it plays again, a timer until it's started, paused or ended, AirDrop
  until the next file, AirPlay until the next speaker. An announcement folds
  away, and a timer that's ringing stops. A call or a recording stays, as
  something you're doing, and on the open notch a swipe up only closes it. The
  notch's right-click menu does the same with **Hide** and what it shows, such
  as **Hide Music**, and hides a call or a recording too.
- Added two activities at once, as the Dynamic Island shows them: the first
  keeps the left of the notch alone, and the second goes in a round bubble as
  tall as the notch off its right end. They take their turns in the order they
  started, whatever they are, and a third waits its turn. The bubble buds
  off the notch's end and runs back into it, and into it while a new song's name
  shows. Clicking it opens its own activity. VoiceOver reads it as a button that
  opens it. With Reduce Motion on, it fades in and out where it rests.
- Added Clock's buttons for its timer and stopwatch to the notch and its
  right-click menu, which work as Clock's own do, at once, with Clock opened
  hidden and quit half a minute after the last press. Without `Accessibility`,
  they're dimmed, and pressing one asks for it. `Timers` and `Stopwatch` in
  **Settings > Live Activities** turn each off, beside **Open Clock**. With
  `Hide in menu bar` there, off at first, macOS's own timer is taken out of the
  menu bar while a timer shows; a link under it to Menu Bar settings brings it
  back, as macOS keeps it out even once the switch is off.
- Added a Live Activities page to Settings, to turn each one off, music's cover
  and waveform among them.
- Added the screen being recorded with macOS's Screenshot, as the iPhone shows
  it: a red dot beside the camera, pulsing faintly while it records, after
  macOS's countdown in a ring, which has nothing to open. Opened, it shows the
  dot and the recording's time, pulsing the same way, over `Screen Recording`,
  and a button to stop it. It opens by itself once you stop, with
  `Saving Recording…` and the ring around the button going round, until the
  square in it grows into the recording's first picture, which opens it, and it
  says where it went, such as `Recording Saved to Desktop`. `Screen recording`
  in **Settings > Live Activities** turns it off.
- Added Voice Memos recording, as the iPhone shows it: a red waveform of the
  sound beside the camera, gliding along as it comes, and the recording's time,
  both still while it's paused. Opened, gray dots for what's still to come move
  along with the waveform and turn red as they reach it, beside the time and a
  button to stop it, as Voice Memos' **Done** does. The waveform comes from the
  Mac's microphone once it's allowed, and nothing is recorded or kept.
  `Voice Memos` in **Settings > Live Activities** turns it off.
- Fixed AirPlay's symbols jittering on their way back beside the camera as the
  notch closed.
- Fixed the timer's ring and the stopwatch's symbol staying in the opened notch,
  behind the pause button.
- Changed the song's progress bar to be one bar, its played part cut straight
  where it ends, rather than a second, rounded bar laid over the gray one.
- Fixed the volume slider in the sound menu not moving, and its played part
  showing gray, while Glance wasn't the app in front.
- Fixed a screen recording disappearing from the notch and from the menu bar,
  with nothing left to stop it, when `Hide macOS's Live Activities` hid
  macOS's own as it started. A recording going on keeps it until it ends.
- Fixed `Hide macOS's Live Activities` not working behind a full-screen app or
  with System Settings open on another Space, and opening System Settings again
  every few seconds when it couldn't. It now uses a System Settings of its own,
  waits longer for it, and tries again when you switch Spaces.
- Fixed the order of two activities changing when Glance opened again: what was
  still going on takes its place back as it's found, first come, first served.
- Fixed a call in the bubble beside the notch showing nothing. It shows the
  call's time, as large as fits, and the phone while it rings or goes out.
- Fixed the bubble vanishing as the notch opened from its own end. It runs into
  the notch's end and rides out on it as the notch opens, until the end takes it
  in, as on the iPhone.
- Fixed the notch's end rounding at the top as the bubble ran into it or budded
  off. It meets the top of the screen there as the notch's other end does.
- Fixed the notch's end beside the bubble showing the camera housing's own
  corner, which is cut sharper than the other end's. It now reaches just past
  the housing, its corner as round as the other end's.
- Fixed the opened Voice Memos waveform rising under the camera housing, where
  it couldn't be seen. The notch opens wider, so the bars recorded so far end
  beside the camera.
- Fixed a voice memo's time starting again from zero when it was resumed after
  a pause. It now carries on from where it stopped.
- Fixed a screen recording made with Screenshot not showing in the notch at
  all.
- Fixed a Discord call's time going back a second or two, every other second,
  while a full-screen app was in front. It now counts on from the call's start.
- Fixed the screen recording's stop button opening macOS 27.3's own Live
  Activity under the menu bar rather than stopping the recording.

### Touch

- Changed three fingers on the open notch, and Shift and a scroll, to stretch the notch
  and what's in it, as pulling it down does, springing into place as you let go.
- Changed the notch to stretch after two fingers whichever way they go, down
  and sideways at once at a slant, and less far, with what's in it stretching
  half as much.
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

- Fixed Glance freezing, and the whole Mac with it, as the volume slider in the
  sound output menu was dragged. Should Glance ever stop answering for ten
  seconds, it now quits by itself.
- Fixed the volume slider doing nothing for an app such as Safari once turning
  it down had once failed, until Glance was opened again.
- Changed the `Spotlight` background to travel slowly round the cover, in the
  cover's own colors, turning, rather than staying in the bottom left corner.
  Passing the camera, it goes behind the cover, so the camera never cuts it off.
  It holds still while paused, and with Reduce Motion on.
- Changed `Background` to start as `None` on a new install. If you had Glance
  before, it stays as it was, whether or not you ever chose it.
- Changed `Tint progress bar` to start off and `Show app icon on cover` to start
  on, on a new install. If you had Glance before, both stay as they were.
- Changed the player with Increase Contrast on to keep the cover's colors behind
  it, darker, in place of plain black, so its words still read on any cover.
- Fixed Spotify's DJ not showing in the player: while the DJ chooses the music,
  its symbol takes the left button's place, drawn as Spotify draws it, its
  corner moving as the DJ talks. Clicking it gets different picks, as Spotify's
  own button does.
- Fixed shuffle and repeat looking available while Spotify's DJ or a podcast
  plays, when Spotify doesn't offer them.
- Added the DJ's own cover while it talks: its green ring on blue, following the same
  sound as the waveform, with the colors behind the player turning blue and `--:--`
  for the times.
- Added `Spotify DJ` to Customize Controls, to keep the left button as it is while
  the DJ plays.
- Fixed clicking the cover, or the app's icon on it, not going where the music
  plays from: it opens the browser tab playing it, the playlist or album Spotify
  plays it from, or the song in the playlist Music plays it from.
- Fixed the cover giving no sign it can be clicked: it lifts gently under the
  pointer, with a soft shadow, squashes as it's pressed, and springs back as
  it's let go.
- Fixed the lyrics saying a song has none when LRCLIB can't be reached. They
  say so instead, and ask again by themselves.
- Changed the sound output menu to look like the Mac's Sound menu: Sound above
  the playing app's volume, each output in a circle, the one playing in the
  accent color, with the Mac's own speakers first, and **Sound Settings…** at
  the bottom. AirPods show each earbud's battery and the case's, and other
  headphones their one battery.
- Changed every device's picture to the one macOS gives that model, so each
  MacBook, AirPods and Beats generation shows as itself, along with a newer
  model than Glance knows of. Other makers' devices show as what they are.
- Changed the cover's colors behind the player to flow as the iPhone's do: the
  cover's own colors drawn out into long ribbons that bend slowly through one
  another.
- Changed the progress bar and the colors behind the player to share one
  palette: the cover's strongest colors, each one it really has.
- Changed the waveform to work and look exactly as macOS's own does in the menu
  bar: six bands of the sound, bass at the left and treble at the right, read
  about twelve times a second, each new reading easing in; round bars, a little
  wider the taller they are; the cover itself showing through them, blurred,
  more saturated and washed with white when it's dark, and dimmed when it's
  bright. While the music is paused, the bars settle into six still dots.
- Changed `Replace glass` to show all of the cover's colors, more strongly, just
  where the glass shows, so a white cover looks white and its red shows too. The
  times and side buttons turn lighter over a light cover.
- Removed the `Fullscreen` background. If it was chosen, the notch goes back to
  `Replace glass`.
- Added the cover's colors pulsing gently on the music's biggest hits, as you
  hear them: only a beat that takes the waveform nearly to its full height
  shows, so with most songs they hardly ever pulse.
- Changed the lyrics to fade at their top as they do at their bottom, above the
  line being sung, so its first words are never dimmed.
- Changed the cover, the colors behind the player and the lyrics to dim by the
  same amount while the song is paused. The dots in a pause in the singing stop
  breathing too.
- Changed lyrics to be found as each song starts, so they're there the moment
  you ask for them.
- Fixed lyrics taking a very long time to show when LRCLIB was slow: they're now
  looked for several ways at once, for a few seconds at most.
- Fixed the lyrics jumping back as a song paused, and the dots in a pause in the
  singing disappearing with them.
- Changed the lyrics, with Reduce Motion on, to fade from one line to the next
  where they rest, rather than gliding up, and the dots and Spotify's note to
  hold still.
- Changed the waveform to take far less of the Mac's power while music plays.
- Fixed the dots before a song's first line coming and going, and the first line
  jumping up and down, while the song loaded.
- Fixed the waveform moving ahead of the music on AirPods and other wireless
  headphones, which play a moment late: it now waits for the sound, as the
  colors' pulse does.
- Fixed the star for songs streamed from `Music`: it stays lit while `Music`
  saves the song, it removes the song from favorites, and it follows changes
  made in `Music`.
- Fixed the waveform going gray and faint on a dark cover: its bars are washed
  with white, as macOS's own are, so they read on black.
- Fixed the waveform in the welcome tour and the test scenes jumping and
  jittering, most of all in the open player. The made-up song's bars now move
  exactly as music's do: rising quickly on each beat and falling away slowly, as
  smoothly.

### Opening

- Changed the closed notch not to swell under the pointer while it's as tall as
  the Alarm already, as for a call coming in or a ringing timer. Whatever shows
  beside the camera still swells, a screen recording's countdown included,
  though it has nothing to open to.
- Fixed the closed notch swelling under the pointer twice as much at its ends
  as at its bottom, with music's cover and waveform crowding its ends. It now
  swells as much all round, and they keep the same padding on every side.
- Fixed the cover swinging out under the camera as the notch closed, its middle
  rushing back with the notch's end ahead of its size. It flies straight back
  to its place now, inside the notch all the way.
- Fixed the notch shrinking past the camera housing as it closed just after
  opening, its edge showing under the camera for a moment.
- Changed quitting Glance to close the notch away first, as turning it off does,
  however Glance is quit: its menus, Command-Q, Activity Monitor's `Quit`, a
  script, or Terminal. `Force Quit` still stops it at once.
- Fixed the notch opening, turning between the player and the tray, and widening
  for the lyrics without the Dynamic Island's bounce: it grows past its size and
  settles back, as the island does. With Reduce Motion on, it goes straight to
  its size.
- Fixed what's behind the notch flickering sharp as it opened with `Blur` set
  in **Settings > Appearance**, the blur only taking hold once it had stopped
  growing. It's blurred all the way now.

### Displays

- Changed every display to show the notch. The Dynamic Island style is gone.
- Changed `Show on displays without a notch` to `Show on external displays`:
  the Mac's own display always has a notch.
- Fixed `Hide in full screen` doing nothing on a Mac with a notch: apps in full
  screen sit below the camera there, so the notch never noticed them. It now
  hides whenever an app is in full screen, and comes back as the app leaves it.
- Fixed the notch disappearing at once as an app went full screen, rather than
  folding back to the camera: it now folds once macOS has finished moving to the
  app, as it already grew out on leaving.

### Settings

- Changed Settings to open on the page you last used.
- Added a **View** menu while Settings is open, with **Back**, **Forward**,
  **Search** and every page, and a **Help** menu with the user manual.
- Added a picture of the notch to the Live Activities page, showing what's
  turned on there, made up, one after another. Turning a switch on shows it at
  once.
- Fixed Glance quitting when `Stopwatch` was turned on in
  **Settings > Live Activities**, and `Calls`, `AirDrop` and `Timers` showing
  the wrong activity in the page's picture as each was turned on.
- Changed the app lists on the Player and Tray pages to work alike: what the
  list is for and **Add App…** at the top, each app under it, and
  **Remove from List** in its menu.
- Fixed search in Settings not finding `AirDrop`, timers, the stopwatch, Clock,
  Beats or updates on their pages.
- Added a message for when a search in Settings finds nothing.
- Added a few words on how it works, beside its icon, at the top of the Player,
  Tray and Live Activities pages.
- Added a picture of a file being dragged to the tray on the Tray page. With the
  pointer over it, the drag gives way and the tray is there to touch: slide its
  row with two fingers or a mouse's wheel.
- Added a preview of `Announce new audio`: turning it on announces what's playing
  in the picture of the notch. With nothing playing, the pictures play a song of
  their own.
- Changed the Music page's name to Player.
- Changed `Switch to the tray` to `Swipe between tools`.
- Removed `Reverse direction`: Shift and a scroll now go the way your Mac
  scrolls.
- Changed `Background` to sit beside its name, as `Layout` does.
- Changed the Displays page to show the display first, with `Hide in full screen`
  and, on an external display, `Show the notch` for that display alone.
- Moved `Cover and waveform` and `Announce new audio` to
  **Settings > Live Activities**.
- Changed the welcome tour's `Live Activities` switch to `Cover and waveform`,
  its name in Settings, and its list to say what else shows beside the camera.
- Changed the pages to fade as they scroll under the picture of the notch,
  rather than being cut off at its edge.
- Fixed the player's size in the Tray page's picture with the tray off, and the
  tray and the player not sliding as the tray is turned on and off.
- Fixed the − on a control in **Customize Controls** being smaller than macOS's
  smallest control: it now takes a click a little around it.
- Changed the permission buttons in the welcome tour and in
  **Settings > General > Permissions** from **Allow** to **Request…**, as they
  only bring up macOS's own question, and `Accessibility` to say everything
  it's used for.
- Fixed toggles and the `Layout` choice lagging on the Settings pages with the
  notch's preview.
- Changed **Settings > General > Permissions > Review…** to open over the
  Settings window, as **Customize Controls** does, rather than in a window of
  its own, and without `Open at login`, which is on the General page itself.
- Fixed the permissions showing **Request…** for a moment as they were opened,
  before showing which are allowed: Glance reads them as it starts, and again
  whenever it comes forward.
- Fixed the picture of the notch in Settings freezing for up to half a second
  as the lyrics opened or closed, and as it turned between the player and the
  tray with the lyrics open.
- Fixed the waveform in the pictures of the notch, in Settings and the welcome
  tour, stepping about twelve times a second: each reading now eases in, as in
  the notch itself.
- Fixed Settings, opened from the menu bar, sometimes coming up a second or more
  late, behind other apps, or drawn gray as if behind them while in use.
- Fixed clicking the waveform in the picture of the notch in Settings doing
  nothing: it shows the lyrics of the song playing, as the notch does, and the
  picture draws back to make room for them.
- Changed the picture of the notch in Settings and in the welcome tour to open,
  fold, and turn between the player and the tray with the notch's own motion
  as you move between pages, bounce included.
- Changed `Hide macOS's Live Activities` to `Hide native Live Activities`.
- Removed **Open Clock…** from **Settings > Live Activities**.
- Changed **Settings > Live Activities** to one switch for each kind of live
  activity, each in a section of its own: `Now Playing` for the cover, the
  waveform and the announcement of what starts playing, `Battery` for charging
  and low battery, `Recordings` for screen recordings and voice memos, and
  `Clock` for timers and the stopwatch, beside `Devices`, `Calls` and `AirDrop`.
- Fixed the link to Menu Bar settings under `Hide in menu bar` showing as
  plain text, with its address in brackets.
- Changed `Open and close`, `Change songs` and `Swipe between tools` in
  **Settings > Opening** to one switch, `Gestures`, saying what each swipe does.

### Tray

- Changed the tray to be only as tall as its items' names need, so that it's as far
  below them as beside them.
- Added `When dragged out` in **Settings > Tray**, to keep an item in the tray
  or take it out once something takes it.
- Added screen recordings to the tray, which join as soon as they're saved, as
  screenshots do.
- Fixed the photo in the tray's demo being enlarged from a smaller picture.
- Fixed the tray's glass adding a blur and a darker tint of its own: it looks as
  it's set in **Settings > Appearance**, as the player's does.
- Fixed a mouse's wheel with Shift held never leaving a tray with more than
  fits: scrolled on past the row's end, it goes back to the player.

### Additional

- Added Glance's icon in the Dock and in Finder, in layers, so it takes on each
  icon style chosen in Appearance settings, clear included.
- Changed the menu bar icon and the app icon to one drawing, nearly square, its
  outline as heavy as the icons beside it in the menu bar, the top a point inside
  it.
- Fixed the menu bar icon being wider than macOS's own, with a wider pill behind
  it while its menu is open.
- Added the keyboard to the player opened with a shortcut: Tab and Shift-Tab go
  from control to control, with a ring around the one they're on, Space or
  Return presses it, and on the progress bar the arrows move ten seconds through
  the song. The sound menu opens under its button.
- Fixed the buttons at the ends of the player's row, such as `Favorite` and
  `Sound Output`, fading on light covers and on glass over light windows:
  they're white there now.
- Changed the buttons that open a window or an app, such as
  **Customize Controls…** and **Open Clock…**, to end in an ellipsis.
- Changed `Use artwork colors`, `Animated art` and `Show app icon on artwork` to
  say cover, as everything else in Glance does.
- Changed the delay sliders on the Opening page to end at `1 s` rather than
  `Slow`, in the same units as the middle.
- Changed the question **Clear…** asks to say that files stay where they are.
- Changed batteries to one green, one red and one yellow, wherever a battery
  shows.
- Changed the timer's orange to the stopwatch's, so both show in one orange.
- Added the keyboard to **Customize Controls**: Tab goes between the player's
  two buttons and the controls under them, Space selects a button or puts a
  control in the selected one, and Delete takes a control out of a button.
- Added the keyboard to the menu bar menu, as it works in any menu: the up and
  down arrows go from row to row, the switch among them, Return or Space chooses
  the one lit, a letter goes to the next row starting with it, and VoiceOver
  says where you are.

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

- Added ⌥⇧1 to open and close the player from any app, ahead of the app's
  own shortcuts.
- Added ⌥⇧2 to open and close the tray the same way.
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
