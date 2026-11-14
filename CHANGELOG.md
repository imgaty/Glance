# Changelog

`Created: 11 October 2026` | `Last updated: 14 November 2026`

<br>

## Release 0.3.0

`Released: not yet`

### Live Activities

- Fixed long recording destination names overlapping the button that opens
  the saved file.

- Fixed the call's Sound Output menu relying on the pointer position to open.
  It now opens from its button for mouse, keyboard and accessibility actions.

- Fixed the recording countdown being announced as a button even though it
  has no controls to open.

- Added isolated previews for unavailable call controls and lyric loading and
  error states.

- Fixed the Hide command naming a different activity from the one it hid,
  and fixed Hide Music only closing the expanded player.

- Fixed hidden player, lyrics and tray controls remaining available to
  VoiceOver behind another activity.
  Closed music exposes one action to open the player.

- Fixed test activity controls requesting Clock permission or answering real
  timer alerts. Test calls now connect after answering a dismissed ringing
  alert, and test recordings keep their controls available.
- Fixed Shuffle and Repeat in the made-up player and kept its commands from
  reaching a real playing app.

- Changed activity opening, closing and switching to fold smoothly to the camera
  housing, then expand with a small bounce into the open or inline view.
  Only the expansion bounces. The contents and detached bubble follow the same
  motion. Hover and click feedback do not add a separate rebound.
  Returning to the inline activity has a much smaller rebound than opening.
  Hover keeps the compact footprint fixed, so opening begins with the collapse.
  Releasing a held click or swipe during opening keeps the final size steady.
  Fixed a downward bulge and a detached activity stepping sideways at the start
  of the collapse.
  With `Haptic feedback` on, opening gives one tap at the housing before expanding.
  Canceling before the housing prevents the tap; automatic updates stay silent.
  Removed an extra pulse and pause at the housing that made the movement stutter.
  This includes detached activities and announcements.
  New input replaces an unfinished transition, and routine time
  and progress updates keep their place. Reduce Motion skips the housing excursion.
  Controls become available as their content appears. Hover keeps its intended
  target during a fold, and detached activities return after leaving full screen.
  Releasing a hold early cancels its pending opening, including during a fold.
  Entering full screen folds directly to the housing without briefly widening.

- Added pressed feedback to timer, incoming-call and low-battery alert
  buttons. Dragging away cancels the click, and a new alert cannot inherit it.

- Fixed keyboard commands reaching controls in activities that were hidden
  behind the opened one. Unavailable controls no longer keep keyboard focus.

- Added calls, with incoming-call controls, elapsed time, a voice waveform,
  sound output selection and controls for supported calling apps.
  The caller's source app is reachable from the keyboard in each call layout;
  unavailable source links are omitted.
  Hovering and pressing the caller gives feedback without moving the name.
  The keyboard focus ring stays clear of caller text when there is no avatar.
- Added Clock timers and the stopwatch, with their time beside the camera
  and controls in the opened notch. A ringing timer stops after ten seconds
  unless the pointer is on it. Repeat keeps the warning visible when
  Accessibility permission is unavailable.
  A stopped stopwatch shows a pause mark inside its dimmed ring.
  Clock commands stop when an earlier step fails instead of continuing with
  the next action.
- Added AirDrop progress for incoming and accepted outgoing files, with a
  preview and a button to stop the transfer when cancellation is available.
  Completed transfers and those without a reachable control show progress alone.
  Incoming transfers keep their arrival order as progress changes.
  Switching to the next visible transfer uses the same housing transition;
  progress on the current transfer stays in place.
  Outgoing progress no longer claims success before macOS confirms delivery.
  With Reduce Motion, the progress ring updates without sweeping.
- Added AirPlay destinations, with **Stop AirPlay** to return sound to its
  previous output.
  Stop checks that the same AirPlay route is still selected and is unavailable
  when no local output can receive the sound.
  A failed change keeps the destination visible and offers **Try Again**.
  When there is no return destination, **No Local Output** stays readable.
- Added screen recordings and Voice Memos, with elapsed time and a stop
  button. A saved screen recording opens from its preview and joins the tray.
  Hiding native Live Activities no longer disables screen recording's native
  indicator and Stop button. If Glance previously turned Screenshot off,
  it restores that setting; settings Glance did not change stay unchanged.
  Losing Accessibility access keeps the last known recording visible and
  explains the missing permission instead of claiming it finished.
  Saved previews explain missing files and failed opening, with retry when
  the file is still available.
  A new error gets time to be read, and an older preview cannot dismiss a
  more recent saved recording.
  A saved recording without a thumbnail shows a video symbol.
  With Reduce Motion, the saved preview appears at its final size while the
  saving indicator fades away.
  The Voice Memos Stop button dims and contracts while pressed, keeping its
  hit area fixed. Reduce Motion keeps the dimming without contraction.
- Added charging and low-battery announcements on MacBooks. The low-battery
  alert includes a Low Power Mode button, using power control approved once
  in **Settings > General > Permissions**.
  Its instruction has stronger contrast, and compact accessory percentages
  stay at least 10 points tall.
  The Low Power Mode button explains pending and failed changes and permits
  retry without showing a mode that macOS has not enabled.
- Added connection and low-battery announcements for supported AirPods and
  Beats, showing their model turning beside a battery ring. Earbud charging
  cases have their own low-battery alert.
  Native device banners stay visible when the connected-device report is
  empty or does not match the device named by the banner.
  They also stay until the matching model and battery level are ready to show.
  Reduce Motion keeps the device still as it arrives, as well as afterward.
- Added two activities at once: the first stays beside the camera and the
  second appears in a bubble. Opening either shows its own controls, and
  another activity waits its turn.
  The notch's **Live Activities** menu opens any ongoing activity, including
  those waiting behind the first two, without changing their order.
  An announcement waiting behind an open page no longer blocks that menu or
  keyboard navigation between activities.
- Added swiping up to dismiss an activity until it changes, and **Hide** in
  the notch's menu. Calls and recordings stay when swiped away.
- Added **Settings > Live Activities** to choose what appears, including
  `Hide native Live Activities` and the option to hide Clock's timer in the
  menu bar.
- Changed activities to share the notch's opening and closing motion, with
  their pictures and times moving into place. Reduce Motion uses fades.
  Clock digits change without rolling, timer rings update without sweeping,
  and the stopwatch's decorative hand stays still.

### Player

- Fixed the explicit-content badge disappearing from long titles with
  Reduce Motion enabled.

- Added hover feedback and help labels to player buttons. Disabled buttons
  ignore hover and press feedback, and Reduce Motion keeps press feedback still.

- Fixed the detached music bubble keeping the previous cover when the next
  track had no artwork.

- Fixed player keyboard commands remaining active behind another activity or
  inside a preview. Only the visible, enabled player responds.

- Fixed unknown-length streams showing a misleading remaining time. Their
  timeline stays unavailable until the playing app supplies a duration.

- Rebuilt Sound as an independent dropdown with native glass, concentric rounded
  corners and no arrow. It opens at the click or below the button from the
  keyboard, with system opening and closing transitions and animated resizing.
  Newly connected outputs fade in and become clear as the list expands. The
  selected output follows the Mac's accent color and lightens while pressed.
  Its volume slider is white in dark appearance and uses the accent color in
  light appearance, with matching speaker heights
  and divider widths. Sound Settings stays compact, with the same highlight as
  the outputs. The slider stays visible but disabled while idle; calls show
  outputs alone.
- Changed the speaker button's waves to follow the current volume without
  shifting the speaker.
- Added Spotify DJ's current artwork and controls, including `Spotify DJ` in
  **Customize Controls**. Shuffle and repeat follow what Spotify makes
  available for the current audio.
- Fixed clicking the cover opening a stale source. It goes to the current
  browser tab, Spotify source or Music song where supported, with a visible
  hover and press response.
- Rebuilt the waveform with the cover's colors, settling into dots while
  paused and waiting for wireless audio so it moves with what is heard.
  Fixed uneven readings and slow movement when playback resumes. The bars
  follow fresh audio in order, with independent rounded ends, and delayed
  readings no longer disturb the background's beat. Reduce Motion holds
  the bars still while playing and shows dots while paused.
- Changed the flowing artwork background and `Spotlight` to move in the
  cover's colors and hold still while paused. The background and progress
  bar share the same colors, which pulse on stronger beats.
- Changed paused covers to shrink and dim with the background and lyrics.
  Player buttons use native symbol transitions as their state changes.
- Changed new installs to start with `Background` set to `None`,
  `Tint progress bar` off and `Show app icon on cover` on. Existing choices
  stay as they were. Removed `Fullscreen`, replacing it with `Replace glass`.
- Fixed background reads reopening Music or Spotify after they were quit,
  and improved Music favorites and volume control for other apps.

### Lyrics

- Changed sung lines to stay above the current line, softly blurred as they
  scroll away, with spacing that follows the type. Reduce Motion uses fades.
- Changed lyrics to load as each song starts, with shorter waits and retries
  when the service is unavailable. Pausing keeps the current line in place.
- Added keyboard navigation between lyric lines and Space or Return to play
  from the selected line.

### Opening and displays

- Added touch on supported MacBook displays and Sidecar: tap to open, drag to
  open or close, swipe to change songs or move through the tray, and touch
  and hold for menus.
- Changed gestures to stretch the notch with the movement and settle into
  place when released. **Settings > Opening > Gestures** controls them.
- Changed opening, closing and page changes to share one motion and consistent
  corners. Reduce Motion removes bounce, blur and extra movement.
- Changed every display to use the notch style, with a separate switch for
  each external display. The Dynamic Island display style was removed.
- Changed `Hide in full screen` to fold back to the camera on a notched
  display and hide with the menu bar on other displays. New external displays
  start with it enabled; existing choices are preserved.
- Changed quitting or turning Glance off to close the notch before it leaves.

### Tray

- Added `When dragged out` in **Settings > Tray**, to keep an item or remove
  it after another app takes it.
- Added saved screen recordings alongside screenshots.
- Changed the tray's height, glass and text contrast to follow its contents
  and appearance settings. Scrolling past its end with Shift returns to the
  player.
- Clarified clipboard privacy: Glance skips copies marked private and copies
  from known password managers.

### Settings

- Changed Settings to remember the last page and keep visited pages ready.
  Added **View** menu navigation and **Help > Glance Help**.
- Added interactive previews for Live Activities, the tray and new audio.
  The shared preview keeps its state as pages, displays and appearance change;
  small choice pictures stay still.
- Changed permission review to grouped forms with visible actions and status.
  Confirmed Music and Spotify permission stays remembered while those apps
  are closed, and power control can be removed without changing its mode.
- Updated display controls, appearance sliders, app lists and search, and
  renamed the Music page to Player.
- Added keyboard selection and removal to **Customize Controls**, alongside
  dragging controls between buttons or out of the player.
- Updated the welcome tour's navigation, captions, permission controls and
  previews to follow Settings.

### Accessibility and languages

- Added all 36 languages supported by macOS, with local digits and mirrored
  layouts in Arabic and Hebrew. Playback progress stays left to right.
- Added keyboard navigation to player controls, Live Activities and the menu
  bar menu, with visible focus and selected-state announcements.
- Improved VoiceOver labels, permission and slider access, disabled states
  and the visibility of text over light covers and glass. Decorative
  pictures and hidden pages no longer expose playback actions.
- Extended Reduce Motion throughout the notch, settings and welcome tour,
  and kept artwork colors readable with Increase Contrast.
- Added a layered app icon for macOS appearance styles, a black glass pane
  lit from a notch at its top, and matched the menu bar icon's proportions to
  its neighbors.

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
