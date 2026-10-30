//
//  OnboardingView.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// A page of the welcome tour.
enum OnboardingPage {
    case welcome
    case step(OnboardingFeature, OnboardingStep)
    case permissions
}

/// The welcome tour, set out as the Mac's own Setup Assistant is: one page at a time, each an icon
/// or a picture, a title that says it all, and the choices; along the bottom, Back at the left,
/// Continue at the right, and the dots between them. The picture of the notch, playing the tour's
/// song, stays put through the feature's steps, as the buttons do, while the pages slide under it;
/// its controls in the Mac's accent color, as every app's are. Opened from Settings, it shows only
/// the permissions.
struct OnboardingView: View {
    @ObservedObject var permissions: Permissions
    let start: OnboardingStart
    let onDone: () -> Void
    @State private var place = 0
    /// Which way the pages slide: on through the tour, or back.
    @State private var forward = true
    @StateObject private var song = NowPlaying.demo(.tour)
    /// One notch for every page's picture, as Settings has one for its pages: it carries on from
    /// page to page rather than starting over.
    @StateObject private var preview = SettingsPreview()

    static let size = CGSize(width: 450, height: 600)

    private var pages: [OnboardingPage] {
        guard start == .welcome else { return [.permissions] }
        let steps = OnboardingFeature.all.flatMap { feature in feature.steps.map { OnboardingPage.step(feature, $0) } }
        return [.welcome] + steps + [.permissions]
    }

    var body: some View {
        let pages = pages
        let last = place >= pages.count - 1
        let page = pages[min(place, pages.count - 1)]
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ZStack {
                    content(page)
                        .id(place)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                // One picture for every step, never made again: from step to step, the notch in it
                // just changes, as it does on screen. It slides in with the first step and out
                // with the last, as the pages do.
                if case .step(_, let step) = page {
                    StepPicture(scene: step.scene)
                        .padding(.top, OnboardingMetrics.top)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
            }
            ZStack {
                if pages.count > 1 {
                    PageDots(count: pages.count, current: place) { go(to: $0) }
                }
                HStack {
                    if pages.count > 1 {
                        Button(place == 0 ? "Set Up Later" : "Back") { place == 0 ? onDone() : go(to: place - 1) }
                            .buttonStyle(.glass)
                    }
                    Spacer()
                    Button(start == .permissions ? "Done" : last ? "Get Started" : "Continue") {
                        last ? onDone() : go(to: place + 1)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
            .padding(OnboardingMetrics.bottom)
        }
        .environmentObject(song)
        .environmentObject(preview)
        .environment(\.tray, .demo)
        .frame(width: Self.size.width, height: Self.size.height)
        // Up under the clear title bar too: the pages leave room for the window buttons.
        .ignoresSafeArea()
        // The arrow keys go through the pages too.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            go(to: place - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            go(to: place + 1)
            return .handled
        }
    }

    @ViewBuilder private func content(_ page: OnboardingPage) -> some View {
        switch page {
        case .welcome: WelcomePage()
        case .step(_, let step): StepPage(step: step)
        case .permissions: PermissionsPage(permissions: permissions)
        }
    }

    /// The direction is set first, so the page leaving slides the right way too, then the page
    /// changes.
    private func go(to target: Int) {
        guard target != place, pages.indices.contains(target) else { return }
        forward = target > place
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 1)) { place = target }
        }
    }
}

/// One set of measures for every page, so they line up as the tour moves through them.
private enum OnboardingMetrics {
    /// The picture, and the groups under it, as wide as each other, as far in from the window's
    /// sides as the buttons along the bottom.
    static let picture = CGSize(width: 410, height: 170)
    static let width = picture.width
    /// Between one group and the next, as System Settings leaves between its sections.
    static let groupGap: CGFloat = 16
    /// The welcome page's list, a little in from the sides, as Apple lists what's new.
    static let listWidth: CGFloat = width - 20
    /// From the top of the window to the icon or picture, clear of the window's buttons.
    static let top: CGFloat = 44
    static let iconSize: CGFloat = 64
    /// The look's pictures: four across a group, as Settings sets out the backgrounds.
    static let lookColumn = (width - GroupMetrics.inset * 2 - 12 * 3) / 4
    /// Between the icon or picture and the title, and between the title and what's under it.
    static let titleGap: CGFloat = 20
    static let contentGap: CGFloat = 20
    /// Around the buttons along the bottom.
    static let bottom: CGFloat = 20
}

/// Every page alike: an icon or a picture at the top, the title, then the page's choices.
private struct PageLayout<Hero: View, Content: View>: View {
    let title: String
    /// The icon's or picture's size.
    var hero = CGSize(width: OnboardingMetrics.iconSize, height: OnboardingMetrics.iconSize)
    @ViewBuilder let picture: Hero
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            picture
                .frame(width: hero.width, height: hero.height)
            Text(title)
                // A title's size for a window this narrow, with room to spare at its sides.
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .padding(.top, OnboardingMetrics.titleGap)
            content
                .frame(width: OnboardingMetrics.width)
                .padding(.top, OnboardingMetrics.contentGap)
        }
        .padding(.top, OnboardingMetrics.top)
    }
}

/// A symbol in place of a picture, at an icon's size, in the accent color.
private struct PageSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 48, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}

/// A dot for each page, the current one filled in, as a page control shows how far along you are.
/// A click on a dot goes to its page.
private struct PageDots: View {
    let count: Int
    let current: Int
    let go: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { page in
                Button {
                    go(page)
                } label: {
                    Circle()
                        .fill(Color.primary.opacity(page == current ? 0.8 : 0.22))
                        .frame(width: 7, height: 7)
                        .frame(width: 16, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(page + 1) of \(count)")
                .accessibilityAddTraits(page == current ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
    }
}

// MARK: - Pages

/// What's in Glance, as Apple welcomes you to an app: its icon, the title, and a line for each
/// highlight of each feature, its symbol in the accent color beside it.
private struct WelcomePage: View {
    var body: some View {
        PageLayout(title: "Welcome to Glance") {
            PageSymbol(name: "rectangle.topthird.inset.filled")
        } content: {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(OnboardingFeature.all.flatMap(\.highlights) + [.personalize]) { highlight in
                    HStack(alignment: .center, spacing: 16) {
                        Image(systemName: highlight.symbol)
                            .font(.system(size: 26, weight: .regular))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(highlight.title)
                                .font(.headline)
                            Text(highlight.text)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(width: OnboardingMetrics.listWidth, alignment: .leading)
        }
    }
}

/// One step of a feature: the notch as it looks, playing, its title, and what to choose.
private struct StepPage: View {
    let step: OnboardingStep
    /// The display the picture shows, whose look the choices change.
    @State private var display = SettingsPreview.defaultDisplay

    var body: some View {
        // Room for the picture, which stays put above the pages (see StepPicture).
        PageLayout(title: step.title, hero: OnboardingMetrics.picture) {
            Color.clear
        } content: {
            VStack(spacing: OnboardingMetrics.groupGap) {
                ForEach(Array(step.settings.enumerated()), id: \.offset) { _, setting in
                    SettingChoice(setting: setting, display: display)
                }
            }
        }
    }
}

/// The choice a step offers: pictures to pick from, or switches.
private struct SettingChoice: View {
    let setting: OnboardingSetting
    let display: String
    @AppStorage(Preferences.openTrigger) private var openTrigger = OpenTrigger.both
    @AppStorage(Preferences.musicLayout) private var layout = PlayerLayout.top
    /// The background of the display pictured.
    @AppStorage private var shownBackground: MusicBackground

    init(setting: OnboardingSetting, display: String) {
        self.setting = setting
        self.display = display
        _shownBackground = AppStorage(wrappedValue: .replaceGlass, Preferences.lookKey(Preferences.musicBackground, display: display))
    }

    var body: some View {
        switch setting {
        case .openTrigger:
            OpenTriggerPicker(selection: $openTrigger)
                .padding(.vertical, GroupMetrics.inset)
                .background(RoundedRectangle(cornerRadius: GroupMetrics.radius, style: .continuous).fill(.quinary))
        case .look:
            // As Settings' Appearance page sets them out: the two layouts beside their name, the
            // four backgrounds across the row under theirs.
            VStack(spacing: 0) {
                CenteredRow(alignment: .top) {
                    // Level with the tops of the pictures, inside their rings.
                    Text("Layout")
                        .padding(.top, 3)
                } trailing: {
                    ThumbnailPicker(
                        selection: $layout, options: PlayerLayout.allCases.map { ($0, $0.title) }, columns: 2,
                        column: OnboardingMetrics.lookColumn
                    ) { layout in
                        NotchThumbnail(layout: layout, display: display)
                            // Still, so the page moves smoothly.
                            .environment(\.notchPaused, true)
                    }
                }
                .padding(GroupMetrics.inset)
                Divider().padding(.horizontal, GroupMetrics.inset)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Background")
                    ThumbnailPicker(
                        selection: background, options: MusicBackground.allCases.map { ($0, $0.title) },
                        column: OnboardingMetrics.lookColumn
                    ) { background in
                        NotchThumbnail(layout: layout, display: display, background: background)
                            .environment(\.notchPaused, true)
                            .id(layout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(GroupMetrics.inset)
            }
            .font(.system(size: 13))
            .background(RoundedRectangle(cornerRadius: GroupMetrics.radius, style: .continuous).fill(.quinary))
        case .switches(let switches):
            SwitchList {
                ForEach(switches) { item in
                    SettingSwitch(item: item)
                }
            }
        }
    }

    /// Chosen here, it's every display's: the shared look and each display's own.
    private var background: Binding<MusicBackground> {
        Binding {
            shownBackground
        } set: { value in
            shownBackground = value
            let defaults = UserDefaults.standard
            defaults.set(value.rawValue, forKey: Preferences.musicBackground)
            for screen in NSScreen.screens {
                defaults.set(value.rawValue, forKey: Preferences.key(Preferences.musicBackground, for: screen.notchID))
            }
        }
    }
}

/// The permissions, before macOS asks for them, each with why it's asked; then whether Glance opens at
/// login.
private struct PermissionsPage: View {
    @ObservedObject var permissions: Permissions
    @ObservedObject private var loginItem = LoginItem.shared

    var body: some View {
        PageLayout(title: "Allow Access") {
            PageSymbol(name: "hand.raised.fill")
        } content: {
            VStack(spacing: OnboardingMetrics.groupGap) {
                permissionList
                SwitchList {
                    SwitchRow(title: "Open at login", isOn: Binding(get: { loginItem.status == .enabled }, set: loginItem.set))
                }
            }
        }
    }

    private var permissionList: some View {
        VStack(spacing: 0) {
            PermissionRow(
                symbol: "waveform", title: "Audio from apps",
                detail: "For the waveform and the volume slider. Nothing is recorded or leaves your Mac.",
                state: permissions.audio, allow: permissions.requestAudio,
                openSettings: { permissions.openSettings(for: \.audio) })
            Divider().padding(.leading, GroupMetrics.inset + PermissionRow.icon + PermissionRow.spacing)
            PermissionRow(
                symbol: "music.note", title: "Control Music",
                detail: "For the shuffle, repeat, favorite and volume controls.",
                state: permissions.musicControl, allow: { permissions.requestControl(of: PlayerScripting.music) },
                openSettings: { permissions.openSettings(for: \.musicControl) })
            Divider().padding(.leading, GroupMetrics.inset + PermissionRow.icon + PermissionRow.spacing)
            PermissionRow(
                symbol: "music.quarternote.3", title: "Control Spotify",
                detail: "For the shuffle, repeat and volume controls. Repeating one song also takes Accessibility.",
                state: permissions.spotify, allow: permissions.requestSpotify,
                openSettings: { permissions.openSettings(for: permissions.spotifyControl == .denied ? \.spotifyControl : \.accessibility) })
            Divider().padding(.leading, GroupMetrics.inset + PermissionRow.icon + PermissionRow.spacing)
            PermissionRow(
                symbol: "accessibility", title: "Accessibility",
                detail: "To paste from the tray with a double-click, and to switch to it with three fingers on the notch.",
                state: permissions.accessibility, allow: permissions.requestAccessibility,
                openSettings: { permissions.openSettings(for: \.accessibility) })
        }
        .background(RoundedRectangle(cornerRadius: GroupMetrics.radius, style: .continuous).fill(.quinary))
    }
}

/// How the notch opens, as round buttons like the notch's own controls: a symbol, and a circle
/// behind it only under the pointer; the one chosen in the accent color. Spread across their group,
/// as far from its sides as from each other.
private struct OpenTriggerPicker: View {
    @Binding var selection: OpenTrigger

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 0)
            ForEach(OpenTrigger.allCases, id: \.self) { trigger in
                TriggerButton(trigger: trigger, selected: selection == trigger) { selection = trigger }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct TriggerButton: View {
    let trigger: OpenTrigger
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: trigger.symbol)
                    .font(.system(size: PlayerLayout.optionGlyph, weight: .medium))
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .hoverCircle(hovering, diameter: NowPlayingView.hitbox + 6)
                Text(trigger.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(width: ThumbnailPicker<OpenTrigger, EmptyView>.column)
            .contentShape(Rectangle())
        }
        .buttonStyle(RoundPress())
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Pressed, the button shrinks a little, as the notch's do.
private struct RoundPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Switches in a rounded group, each with its name and the switch at the end.
private struct SwitchList<Rows: View>: View {
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: rows) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.horizontal, GroupMetrics.inset) }
                    row
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: GroupMetrics.radius, style: .continuous).fill(.quinary))
    }
}

/// A switch for one of the app's settings, by its key.
private struct SettingSwitch: View {
    let item: OnboardingSwitch
    @AppStorage private var isOn: Bool

    init(item: OnboardingSwitch) {
        self.item = item
        _isOn = AppStorage(wrappedValue: true, item.key)
    }

    var body: some View {
        SwitchRow(title: item.title, isOn: $isOn)
    }
}

private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .controlSize(.mini)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, GroupMetrics.inset)
        .frame(height: GroupMetrics.rowHeight)
    }
}

// MARK: - The notch in the pictures

/// The steps' picture: the notch as a step shows it, rounded and outlined.
private struct StepPicture: View {
    let scene: NotchScene

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GroupMetrics.radius, style: .continuous)
        NotchScenePicture(scene: scene)
            .frame(width: OnboardingMetrics.picture.width, height: OnboardingMetrics.picture.height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 1) }
    }
}

/// The real notch, at the top of a picture of the screen, playing the page's song, as a step shows
/// it. On the step to try it, it opens and closes as the notch on the screen does; on the layouts'
/// step, it turns from one layout to the other until one is chosen; on the tray's, a photo is
/// dragged to it and dropped in the tray. The page behind it holds still, so the tour moves
/// smoothly.
private struct NotchScenePicture: View {
    let scene: NotchScene
    @AppStorage(Preferences.musicTrackPop) private var announces = true
    @EnvironmentObject private var nowPlaying: NowPlaying
    @EnvironmentObject private var preview: SettingsPreview
    @AppStorage(Preferences.musicLayout) private var layout = PlayerLayout.top
    /// A layout's been chosen below: the picture shows it, rather than turning between them.
    @State private var chosen = false

    var body: some View {
        NotchPreview(
            model: preview.model, display: preview.display, top: preview.top,
            interactive: scene == .tryOpening || scene == .liveActivity, hintsOpening: scene == .tryOpening, still: true,
            // As large as Settings draws it.
            scaleWidth: PreviewHeader.width, demo: demo
        )
        // A layout chosen below reshapes the notch in place, as on screen.
        .onChange(of: layout) {
            chosen = true
            withAnimation(.spring(response: 0.5, dampingFraction: 1)) { preview.model.use(layout) }
        }
        .task(id: scene) { await play() }
        .task(id: scene == .liveActivity && announces) { await announce() }
    }

    /// Takes the notch from how the last step left it to how this one shows it, before your eyes:
    /// closed, to be opened, or open, as it opens on screen.
    private var demo: NotchDemo? {
        switch scene {
        case .layouts: chosen ? nil : .layouts
        case .tray: .dropInTray
        case .tryOpening, .liveActivity: nil
        }
    }

    private func play() async {
        let model = preview.model
        model.songPlaying = true
        // Left in the other layout by the layouts' step, it's back in the one chosen.
        if scene != .layouts, model.layout != layout {
            withAnimation(model.state == .open ? .spring(response: 0.5, dampingFraction: 1) : nil) { model.use(layout) }
        }
        // The tray's step shows the tray; every other, the player.
        let page: NotchPage = scene == .tray ? .tray : .player
        if model.page != page {
            withAnimation(model.state == .open ? .spring(response: 0.4, dampingFraction: 1) : nil) { model.page = page }
        }
        switch scene {
        case .tryOpening:
            preview.setInteractive(true, animated: true)
        case .tray:
            // Closed, for the photo to be dragged to; the drop opens it (see NotchDemoScene).
            preview.setInteractive(true, animated: true)
        case .layouts:
            preview.setInteractive(false, animated: true)
            guard model.state != .open else { return }
            try? await Task.sleep(for: .seconds(0.45))
            guard !Task.isCancelled else { return }
            model.open()
        case .liveActivity:
            preview.setInteractive(true, animated: true)
        }
    }

    /// On the live activity's step, the song is announced every few seconds, as each new one is,
    /// while announcing is on. Turned on, it's announced at once; turned off, an announcement under
    /// way folds away.
    private func announce() async {
        let model = preview.model
        guard scene == .liveActivity, announces else {
            if model.pop { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { model.pop = false } }
            return
        }
        try? await Task.sleep(for: .seconds(0.3))
        while !Task.isCancelled {
            guard model.activity, model.state == .closed else {
                try? await Task.sleep(for: .seconds(0.5))
                continue
            }
            // No wider than the picture: a longer title or artist scrolls, as it does on screen.
            let scale = NotchPreview.scale(for: PreviewHeader.width, model: model)
            let room = (OnboardingMetrics.picture.width / scale - model.closedSize.width) / 2 - 12
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                model.popWing = min(
                    LiveActivityView.popWing(
                        title: nowPlaying.title, artist: nowPlaying.artist, restingHeight: model.closedSize.height), room)
                model.pop = true
            }
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { model.pop = false }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

extension OpenTrigger {
    /// For the welcome tour's pictures of each choice.
    var symbol: String {
        switch self {
        case .hover: "cursorarrow"
        case .click: "cursorarrow.click"
        case .both: "cursorarrow.click.2"
        }
    }
}

private struct PermissionRow: View {
    /// The symbol's column, and the space between it and the name.
    static let icon: CGFloat = 20
    static let spacing: CGFloat = 10

    let symbol: String
    let title: String
    let detail: String
    let state: Permissions.State
    let allow: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Self.spacing) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.tint)
                .frame(width: Self.icon)
            // As Settings writes a line under a setting's name.
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            switch state {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.system(size: 12, weight: .medium))
            case .denied:
                Button("Open Settings", action: openSettings)
            case .notDetermined:
                Button("Allow", action: allow)
            case .notInstalled:
                Text("Not installed")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, GroupMetrics.inset)
        .padding(.vertical, 8)
        .frame(minHeight: GroupMetrics.rowHeight)
        .accessibilityElement(children: .combine)
    }
}
