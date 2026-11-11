# Design review: Glance

`Created: 10 November 2026` | `Last updated: 11 November 2026`

The app’s design findings, verification limits, and source coverage.
<br>

## Summary

Glance has a clear identity: one island beside the camera that grows from a
glanceable indicator into a useful control surface. Its native Settings
structure and shared visual rules are strong. Overall rating: **Critical
issues**, because five accessibility findings were identified on 10 November. Readability, privacy
wording and localized onboarding were also flagged. Fixes are recorded below.
<br>

## Fix verification

The original findings below describe the source reviewed on 10 November.
Follow-up captures use the same native views and inert fixtures, behind the
wallpaper, on 11 November. Screenshots are kept outside the repository.

- C1: Replaced the flattened rows with directly labeled native sliders
- C2: Hid decorative thumbnails and inactive page layers from accessibility
- C3: Used native disabled Button semantics for status-menu rows
- C4: Exposed selected sound-output state in both output-menu paths

Native accessibility inspection confirmed adjustable Appearance controls,
selection-only background buttons, no hidden player actions on the Tray,
disabled Check for Updates, and the selected Speakers output. Captures:
`appearance-light.png`, `tray-dark.png`, `status-light.png`, `sound-light.png`.

<br>

## Scope and method

The inventory covers 130 tracked app files: 96 Swift sources and 34 resource and
packaging files. Native localized captures cover English, French and Arabic,
with a separate right-to-left player capture. All six onboarding pages and all
seven Settings pages are represented.

Reviewed production source at `86493b9` on `live-activities-implementation`:
all 96 tracked Swift files (32,333 lines) received a scan for design relevance.
Rendering, interaction, accessibility, window, color and motion paths received
focused code review. This is not a claim that every line of nonvisual
implementation received a general correctness review.

Also inspected the layered icon, both string catalogs, permission descriptions,
Share extension declarations, package and build configuration. All 24 bundled
device movies decoded successfully; a quarter-turn frame of each was visually
inspected. Translation coverage was checked structurally; this is not a fluency
review of every language.

Screenshots are unmodified captures of native Glance views in windows behind the
wallpaper. Fixtures use made-up people, lyrics and media, inert volume callbacks
and app-owned preview state. The desktop around the notch is Glance’s own
preview scene. The captures verify appearance and accessibility exposure in
those states; they do not prove that a real call, recording, AirDrop transfer or
playback command works end to end. Inactive title bars and gray window controls
are expected in these hidden test windows.

Native accessibility trees were inspected from outside Glance. No mouse or
keyboard events were synthesized, no playback or volume command was issued, and
no real recording or call was started. Screenshots show the affected surfaces;
accessibility diagnoses also rely on the native tree and source. A spoken
VoiceOver session, Full Keyboard Access traversal, Switch Control, external
monitor hardware, live action reliability and current frame pacing were not
tested in this pass. No claim of 1:1 the reference player motion parity is made.
<br>

## Critical

### C1: Critical: Appearance sliders are missing from accessibility

- **What:** Both visible sliders were absent from the native accessibility tree.
  Sound and Opening sliders were exposed by the same inspection.
- **Why:**
  [voiceover.md › Descriptions](https://developer.apple.com/design/human-interface-guidelines/voiceover)
: “Provide alternative labels for all key interface elements.”
- **Fix:** Give each Slider its own localized label and preserve it as an
  adjustable element instead of flattening it into LabeledContent.
- **Source:**
  [Sources/Glance/Settings/Pages/AppearancePage.swift:86](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Settings/Pages/AppearancePage.swift#L86)
- **Screenshot:** `settings-appearance-light.png`.

### C2: Critical: Decorative and hidden player layers expose playback actions

- **What:** The three background-choice buttons expose Increment, Decrement,
  Favorite, Previous, Play, Next, Sound Output and Show Where It's Playing as
  secondary actions. With the Tray open, invisible Show Where It's Playing and
  Show Lyrics buttons also remain in the native accessibility tree.
- **Why:**
  [voiceover.md › Descriptions](https://developer.apple.com/design/human-interface-guidelines/voiceover)
: “Exclude purely decorative images from VoiceOver.”
- **Fix:** Hide the decorative NotchThumbnail subtree from accessibility; retain
  the outer selection button label and selected trait. Explicitly hide the hero
  artwork and waveform accessibility elements while the Tray is shown; pointer
  hit-testing and opacity do not remove these actions.
- **Source:**
  [Sources/Glance/Settings/Preview/NotchPreview.swift:320](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Settings/Preview/NotchPreview.swift#L320)
,
  [Sources/Glance/Notch/NotchView.swift:880](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Notch/NotchView.swift#L880)
,
  [Sources/Glance/Notch/NotchView.swift:1377](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Notch/NotchView.swift#L1377)
- **Screenshot:** `settings-appearance-light.png`, plus `tray-items-dark.png`
  and `tray-empty-dark.png`.

### C3: Critical: Unavailable status-menu action is exposed as enabled

- **What:** Check for Updates… is visibly dimmed but its accessibility element
  is an enabled button. The callback checks a Boolean; the element itself is
  never disabled.
- **Why:**
  [menus.md › Labels](https://developer.apple.com/design/human-interface-guidelines/menus)
: “Show people when a menu item is unavailable.”
- **Fix:** Use a Button with `.disabled(!row.enabled)`, keeping the present menu
  styling and keyboard navigation.
- **Source:**
  [Sources/Glance/App/StatusBar.swift:609](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/App/StatusBar.swift#L609)
- **Screenshot:** `status-light.png`.

### C4: Critical: Current sound output is conveyed only by color

- **What:** MacBook Pro Speakers is the current fixture output and has a blue
  circle. Accessibility reports two ordinary device buttons with no selected
  trait or current-output value.
- **Why:**
  [voiceover.md › Navigation](https://developer.apple.com/design/human-interface-guidelines/voiceover)
: “Specify how elements are grouped, ordered, or linked.”
- **Fix:** Expose the current device as selected with a selected trait;
  set the NSMenuItem state in the outputs-only path too.
- **Source:**
  [Sources/Glance/Media/AudioOutput.swift:405](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Media/AudioOutput.swift#L405)
- **Screenshot:** `sound-light.png`.

### C5: Critical: Lyrics status messages are dimmed twice while paused

- **What:** Unavailable and network-error messages use 40% white, then the
  paused lyrics pane applies another 60% opacity: 24% effective white. On black,
  that is approximately #3D3D3D, 1.93:1, below the 3:1 target for 19 pt bold
  text. There is no Increase Contrast override for these two opacity
  multipliers.
- **Why:**
  [accessibility.md › Vision](https://developer.apple.com/design/human-interface-guidelines/accessibility)
: “Strive to meet color contrast minimum standards.”
- **Fix:** Keep informative status/error messages at full readable opacity
  instead of applying the inactive-line treatment. Apply paused dimming to timed
  lyric content only, and verify at least 3:1 in both playback states and
  Increase Contrast.
- **Source:**
  [Sources/Glance/Media/Lyrics.swift:438](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Media/Lyrics.swift#L438)
,
  [Sources/Glance/Media/Lyrics.swift:449](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Media/Lyrics.swift#L449)
,
  [Sources/Glance/Media/Lyrics.swift:479](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Media/Lyrics.swift#L479)
- **Screenshot:** `lyrics-unavailable-black-cover.png`.
<br>

## Improvements

### H1: High: Empty-Tray instructions become hard to read on clear glass

- **What:** 14 pt regular #9E9EA2 against a nearby sampled #495560 backdrop is
  2.86:1 in the sRGB-converted capture; white would be 7.63:1. Clear glass, zero
  added blur/darkness, Increase Contrast off.
- **Why:**
  [accessibility.md › Vision](https://developer.apple.com/design/human-interface-guidelines/accessibility)
: “Strive to meet color contrast minimum standards.”
- **Fix:** Use white for the empty-state explanation, or add a local darker
  backing that maintains at least 4.5:1. Keep the existing opaque accessibility
  fallback.
- **Source:**
  [Sources/Glance/Tray/TrayView.swift:179](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Tray/TrayView.swift#L179)
- **Screenshot:** `tray-empty-dark.png`.

### H2: High: Clipboard privacy copy promises more than the filters can know

- **What:** The UI says passwords and other private items are never kept.
  TrayCapture rejects marked private types and known password-manager apps;
  arbitrary unmarked text is accepted.
- **Why:**
  [privacy.md › Best practices](https://developer.apple.com/design/human-interface-guidelines/privacy)
: “Be transparent about how your app collects and uses people’s data.”
- **Fix:** Say that Glance skips copies marked private and copies from known
  password managers; keep app exclusions easy to find. The manual can be
  corrected in this audit; app wording remains a follow-up.
- **Source:**
  [Sources/Glance/Settings/Pages/TrayPage.swift:37](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Settings/Pages/TrayPage.swift#L37)
,
  [TrayItem.swift:129](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Tray/TrayItem.swift#L129)
- **Screenshot:** `settings-tray-light.png`.

### M1: Medium: French onboarding crowds navigation and truncates a choice label

- **What:** In the 450 pt French welcome window, Configurer plus tard finishes
  roughly 2.5 pt from the first visible page dot. The layout-choice page
  truncates Pochette sur le côté despite scaling the caption. The footer centers
  the dots independently of the buttons, and captions are limited to one line.
- **Why:**
  [layout.md › Adaptability](https://developer.apple.com/design/human-interface-guidelines/layout)
: “Design a layout that adapts gracefully and consistently.”
- **Fix:** Lay out footer buttons and the page indicator in one space-aware row.
  Allow two caption lines at 11 pt rather than shrinking toward 8.8 pt and
  truncating. Recheck the longest supported translations.
- **Source:**
  [Sources/Glance/Onboarding/OnboardingView.swift:74](https://github.com/imgaty/Glance/blob/86493b97f8155c53863361ddd610d4dab0a4fee8/Sources/Glance/Onboarding/OnboardingView.swift#L74)
- **Screenshot:** `onboarding-welcome-fr.png`.
<br>

## Craft notes

The island is the signature; Settings can stay quiet. System type suits the
utility, cover-derived color belongs to the media, and the rounded forms share a
clear hierarchy. No additional visual accessory needs adding or removing in this
pass. Preserve morphing between layouts instead of replacing the whole player
with a fade. This is design judgment, supported by
[live-activities.md › Adding transitions and animating content updates](https://developer.apple.com/design/human-interface-guidelines/live-activities)
: “Animate layout changes.”
<br>

## What works

- Camera clearance, shared 14 pt insets, 40 pt player hit areas and a consistent
  island shape give the app one recognizable system.
- The sound control is a standard SwiftUI Slider in the current source. The
  native tree exposes its Sound label, adjustable value and end controls. Its
  pressed glass appearance and a real volume drag were not exercised in this
  audit.
- The artist row remains protected by the top shading. In the white-cover
  capture, #9E9EA2 against sampled nearby backdrops reaches 5.73:1–6.09:1. Do
  not darken the entire artwork field to solve unrelated lower-row contrast.
- Settings uses native grouped forms, search, history commands and retained
  panes. The code keeps a shared preview and stable player subviews across
  layout changes; preserve that continuity.
- Lyrics have seeking actions and keyboard support in source, with distinct
  loading, unavailable, network-error and plain-text paths. Reduce Motion paths
  stop background drift, animated artwork, device turns and decorative demo
  movement.
- Tray items expose named actions and preserve originals when removed.
  Empty-state copy explains the next action. Permissions explain each use and
  distinguish Request…, Allowed and Open Settings….
- Compact and expanded timer, call, recording, AirDrop and AirPlay presentations
  reuse the same content and visual vocabulary. No extra outlines are proposed;
  that remains the user’s choice.
<br>

## Platform notes

Glance is a SwiftUI/AppKit utility for macOS 26 and later, inspected on this
Mac’s macOS 27.3 beta. The custom notch panels are not ActivityKit widgets:
iPhone limited-width circles, iPhone Duo adaptations, mobile touch targets and
iOS Dynamic Type are not applied as literal macOS requirements.

Playback controls and timeline intentionally stay left to right when the
surrounding content mirrors. Keep the chosen name “Replace glass,” Layout on the
Player page, the Control Center-style status panel, and the existing no-outline
treatment. The timer bubble’s presentation remains a separate comparison item
requiring the agreed real-device reference.

Motion: the code was reviewed for stable view identity, cancellation and
accessibility alternatives. These still images do not certify smooth rapid
Settings switching or Spotlight timing. A new frame-time trace and dense screen
frames are still needed before calling those behaviors smooth or identical to
the reference player. Native-owned About, update, open-file, sharing and Quick
Look dialogs were source-mapped rather than launched. Share-extension timeout
feedback deserves a separate failure-path check.
<br>

## Source coverage

The [source CSV](design-source-coverage.csv) lists every tracked Swift file, line count, review method and
SHA-256 of the reviewed source. A [resource CSV](design-resource-coverage.csv) records all 34 resource and
packaging files, bringing the app inventory to 130 files. A focused design
review is distinguished from a dependency scan. Screenshots remain outside the
repository.
<br>

## Follow-up order

1. Restore accessibility semantics and hide decorative/invisible playback
  actions.
2. Improve the empty-Tray explanation contrast and narrow the clipboard promise.
3. Verify rapid Settings switching and Spotlight with fresh frame timing, then
  compare motion with the real Apple reference.
