# Design review: Glance

`Created: 10 November 2026` | `Last updated: 11 November 2026`

The app’s design findings, verification limits, and source coverage.
<br>

## Summary

Glance has a clear identity: one island beside the camera that grows from a
glanceable indicator into a useful control surface. The initial review on
10 November found eight issues. All eight have been addressed and checked in
native views on 11 November. Overall rating after these fixes: **Good**.
Spoken assistive-technology sessions, live action checks, and reference-motion
comparisons remain verification limits, described below.
<br>

## Fix verification

The original findings below describe the source reviewed on 10 November.
Follow-up captures use the same native views and inert fixtures, behind the
wallpaper, on 11 November. Screenshots are kept outside the repository.

- C1: Replaced the flattened rows with directly labeled native sliders
- C2: Hid decorative thumbnails and inactive page layers from accessibility
- C3: Used native disabled Button semantics for status-menu rows
- C4: Exposed selected sound-output state in both output-menu paths
- C5: Kept lyrics status messages at full opacity in both playback states
- H1: Changed empty-Tray instructions to white on clear glass
- H2: Narrowed the clipboard privacy explanation in all 34 translated entries
- M1: Laid out footer controls together, with a stacked fallback, and allowed
  two-line choice captions without shrinking the 11 pt text

Native accessibility inspection confirmed adjustable Appearance controls,
selection-only background buttons, no hidden player actions on the Tray,
disabled Check for Updates, and the selected Speakers output. Captures:
`appearance-light.png`, `tray-dark.png`, `status-light.png`, `sound-light.png`.

Readability captures cover paused unavailable lyrics, a connection error during
playback on white artwork, the paused error with app-owned Increase Contrast
flags, and an empty Tray on clear glass. The Mac's accessibility preferences
were not changed. Nearby sRGB background samples give white text at least
5.25:1 for these lyrics messages and 6.54:1 for the Tray instructions. These
samples do not certify every possible desktop backdrop. Captures:
`lyrics-unavailable-paused-black.png`, `lyrics-error-playing-white.png`,
`lyrics-error-paused-contrast.png`, `tray-empty-clear.png`.

The clipboard explanation was checked in the native Tray form
(`clipboard-privacy-light.png`). All 34 translated entries carry the narrower
claim; the two English regional fallbacks retain their existing behavior.
Translation coverage is structural, without a native-speaker fluency review.

Onboarding was captured at its actual 450 by 600 pt size in French, Ukrainian,
Romanian and Arabic. French choice captions show in full at 11 pt; navigation
buttons and six independent page targets no longer overlap. Ukrainian uses the
stacked footer. Arabic keeps its mirrored layout and left-to-right playback.
All six French pages were captured to check the remaining content and footer.
Captures include `onboarding-welcome-fr.png`, `onboarding-layout-fr.png`,
`onboarding-welcome-uk.png`, `onboarding-welcome-ro.png` and
`onboarding-layout-ar.png`.

<br>

## Motion and Settings follow-up

Two release-build runs used the actual 740 by 700 pt Settings window behind the
wallpaper, a fake playing song, all seven pages, and a display-link callback
trace. First and warm visits held each page for 400 ms; rapid passes made 28
changes at 100 ms intervals. No screenshots were taken during timing.

Before the follow-up, rapid-switch 95th-percentile callback gaps were 29.1 and
29.7 ms. After retaining native pages without resetting their roots, keeping
choice pictures still, deferring last-page persistence, and avoiding unchanged
preview assignments, they were 20.0 and 17.7 ms. Maximum rapid gaps were still
59.7 and 62.8 ms; first-visit maximum gaps were 124.5 and 114.1 ms. This is an
improvement, not a claim of stutter-free first visits. Cold-start ranges overlap
across runs, and callback times do not measure every compositor presentation.

Normal-speed runs before the geometry correction made 24 background and
24 layout changes, 120 ms apart. They
gave 95th-percentile gaps of 14.3 and 10.2 ms, with maxima of 20.8 and 16.7 ms.
Slowed native still frames were inspected separately. They exposed a hard
background edge during the mask morph; frame timing alone did not reveal it.
The color plane had moved away while the soft mask still covered a wider area.
The follow-up pins the field to the notch and aligns its painted area to the
top, then moves and shrinks the mask. It also uses the display's real camera
clearance in previews. Mirrored layouts keep the existing logical coordinates,
which SwiftUI mirrors with the cover.

In a blank six-pixel strip inside the lower player, 21 of 103 before frames had
an adjacent-channel step over 20 sRGB levels; the largest was 58. In 102 after
frames, none exceeded 20 and the largest was 9. Native frames were also checked
visually. This samples that exposed seam, without certifying every pixel or
claiming reference-motion parity. Separate captures confirmed the demo Tray's
page transition, the mirrored cover and glow, and hidden lyrics leaving the
native accessibility tree after being opened and closed.

Lyrics rows now wait until first opened and remain available for a quick return.
Hidden lyrics are excluded from accessibility and pointer navigation. A paused
artwork view receives notification when its first completed background frame
arrives, without needing to poll or animate.

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

**Resolved 11 November 2026.** See [Fix verification](#fix-verification).

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

**Resolved 11 November 2026.** See [Fix verification](#fix-verification).

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

**Resolved 11 November 2026.** See [Fix verification](#fix-verification).

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

**Resolved 11 November 2026.** See [Fix verification](#fix-verification).

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

**Resolved 11 November 2026.** See [Fix verification](#fix-verification).

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

**Resolved 11 November 2026.** See [Fix verification](#fix-verification).

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

**Resolved 11 November 2026.** See [Fix verification](#fix-verification).

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

**Resolved 11 November 2026.** See [Fix verification](#fix-verification).

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

## Remaining verification

- Run a spoken VoiceOver session and a Full Keyboard Access traversal
- Check real playback, sound-output and live-activity actions in normal use
- Compare motion against the agreed real-device references before claiming
  exact parity
