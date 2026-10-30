//
//  SettingsView.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// The sidebar of pages with its search field, and the page chosen, with back and forward.
struct SettingsView: View {
    var onShowPermissions: () -> Void
    /// The window's title follows the page shown.
    var onPage: (SettingsPane) -> Void = { _ in }
    @State private var pane: SettingsPane? = .general
    @State private var query = ""
    /// The pages visited, for back and forward.
    @State private var history: [SettingsPane] = []
    @State private var place = 0
    @State private var travelling = false
    @StateObject private var preview = SettingsPreview()
    /// Pages are built once and kept, so going back to one is instant: building a page of settings
    /// takes SwiftUI a moment, enough to be felt on every click. The rest are built just after the
    /// window opens.
    @State private var built: Set<SettingsPane> = []
    /// Read only by the notches pictured on pages, which hold still on pages not shown; nothing else
    /// has to change when the page does.
    @State private var shownPage = ShownPage()

    private var panes: [SettingsPane] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return SettingsPane.allCases }
        return SettingsPane.allCases.filter { pane in
            let text = (pane.title + " " + pane.keywords).lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(panes, selection: $pane) { pane in
                // Not a Label: the sidebar would shrink and dim its icon. System Settings' tiles are
                // 20 points, 19 from the window's edge and 7 from the name.
                HStack(spacing: 7) {
                    PaneIcon(pane: pane)
                    Text(pane.title)
                }
                .padding(.leading, 3)
                .tag(pane)
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Search")
            .toolbar(removing: .sidebarToggle)
            // Last, or the toolbar change above loses it.
            .navigationSplitViewColumnWidth(
                min: SettingsWindowController.sidebarWidth, ideal: SettingsWindowController.sidebarWidth,
                max: SettingsWindowController.sidebarWidth)
        } detail: {
            // The preview stays put; only the page under it scrolls.
            let shown = pane ?? .general
            VStack(spacing: 0) {
                // Kept on the pages without it, folded away, so it's never built again on the way
                // back, and carries on where it was.
                PreviewHeader(pane: shown)
                    .frame(height: shown.showsPreview ? nil : 0, alignment: .top)
                    .clipped()
                    .opacity(shown.showsPreview ? 1 : 0)
                    .allowsHitTesting(shown.showsPreview)
                    .accessibilityHidden(!shown.showsPreview)
                Pages(built: built.union([shown]))
                    .equatable()
                    // What scrolls fades away on its way under the preview, in the margin above the
                    // first group, rather than being cut off at its edge.
                    .mask { PageTopFade(fades: shown.showsPreview) }
            }
            .formStyle(.grouped)
            .modifier(PictureSong())
            .environmentObject(preview)
            .environment(\.shownPage, shownPage)
            .environment(\.showPermissions, ShowPermissions(action: onShowPermissions))
            .task {
                built.insert(shown)
                // After the preview has opened, so building them never catches its animation.
                try? await Task.sleep(for: .seconds(1.2))
                for page in SettingsPane.allCases where !built.contains(page) {
                    built.insert(page)
                    try? await Task.sleep(for: .seconds(0.35))
                }
            }
            .toolbar {
                // The system's own back and forward, as System Settings has them: one capsule with a
                // line between the arrows, and its hover and press.
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button {
                            go(by: -1)
                        } label: {
                            Label("Go Back", systemImage: "chevron.backward")
                        }
                        .disabled(place == 0)
                        .help("Go Back")
                        Button {
                            go(by: 1)
                        } label: {
                            Label("Go Forward", systemImage: "chevron.forward")
                        }
                        .disabled(place >= history.count - 1)
                        .help("Go Forward")
                    }
                    .controlGroupStyle(.navigation)
                }
            }
        }
        .frame(width: SettingsWindowController.width)
        .frame(minHeight: SettingsWindowController.minHeight, idealHeight: 700, maxHeight: .infinity)
        // Next time the window opens, the notch opens with it again, and the desktop pictures are
        // read again.
        .onDisappear {
            preview.revealed = false
            Wallpapers.shared.forget()
        }
        .onChange(of: pane, initial: true) {
            let shown = pane ?? .general
            shownPage.page = shown
            onPage(shown)
            guard !travelling else { return travelling = false }
            history = Array(history.prefix(place + 1)) + (history.last == shown && place == history.count - 1 ? [] : [shown])
            place = history.count - 1
        }
        .onChange(of: query) { if let first = panes.first, !panes.contains(pane ?? .general) { pane = first } }
    }

    private func go(by step: Int) {
        let target = place + step
        guard history.indices.contains(target) else { return }
        place = target
        travelling = true
        pane = history[target]
    }
}

/// Every page built so far, one above another, only the one shown visible. Nothing here depends on
/// which page that is except each page's own slot, so changing pages only shows one and hides another.
private struct Pages: View, Equatable {
    let built: Set<SettingsPane>

    var body: some View {
        ZStack {
            ForEach(SettingsPane.allCases) { page in
                if built.contains(page) { PageSlot(page: page) }
            }
        }
    }
}

private struct PageSlot: View {
    let page: SettingsPane
    @Environment(\.shownPage) private var shownPage

    var body: some View {
        let shown = shownPage?.page == page
        PageContent(page: page)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .environment(\.settingsPage, page)
    }
}

private struct PageContent: View {
    let page: SettingsPane

    var body: some View {
        switch page {
        case .general: GeneralPage()
        case .appearance: AppearancePage()
        case .player: PlayerPage()
        case .tray: TrayPage()
        case .activities: ActivitiesPage()
        case .opening: OpeningPage()
        case .displays: DisplaysPage()
        }
    }
}

/// What the pictures of the notch play: what's playing, or with nothing playing, a song of their own
/// (see `NowPlaying.fallback`), so there's always something to show. Only that one is made, and only
/// if it's needed.
private struct PictureSong: ViewModifier {
    @EnvironmentObject private var nowPlaying: NowPlaying

    func body(content: Content) -> some View {
        content.environmentObject(nowPlaying.hasMedia ? nowPlaying : NowPlaying.fallback)
    }
}

/// Clear across the top of the pages, up to where the first group rests, so nothing at rest fades.
private struct PageTopFade: View {
    let fades: Bool
    /// The margin above a form's first group.
    private static let height: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: (0...12).map { i in
                    let t = CGFloat(i) / 12
                    return .init(color: .black.opacity(fades ? t * t * (3 - 2 * t) : 1), location: t)
                },
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Self.height)
            Color.black
        }
    }
}

/// Opening the permissions window from the General page.
struct ShowPermissions {
    var action: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var showPermissions = ShowPermissions()
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, player, tray, activities, opening, displays

    var id: Self { self }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .player: "Player"
        case .tray: "Tray"
        case .activities: "Live Activities"
        case .opening: "Opening"
        case .displays: "Displays"
        }
    }

    /// Those of System Settings' own pages where they have one.
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .player: "music.note"
        case .tray: "tray.full.fill"
        // The Dynamic Island's own shape.
        case .activities: "capsule.fill"
        case .opening: "cursorarrow.click.2"
        case .displays: "sun.max.fill"
        }
    }

    /// The pages about how the notch looks and works show it, live, at the top.
    var showsPreview: Bool { [.appearance, .player, .tray, .opening].contains(self) }

    var color: Color {
        switch self {
        case .general: .gray
        case .appearance: Color(white: 0.15)
        case .player: .pink
        case .tray: .indigo
        case .activities: .green
        case .opening: .orange
        case .displays: .blue
        }
    }

    /// Words a search in the sidebar finds the page by.
    var keywords: String {
        switch self {
        case .general: "login launch startup permissions about build version source"
        case .appearance: "look glass system black clear dark blur opaque liquid transparency accent color artwork background spotlight display preview"
        case .player:
            "music apps sources apple spotify safari browser layout cover progress bar controls customize buttons favorite shuffle repeat output lyrics animated art announce songs"
        case .tray: "shelf files drop drag clipboard copy paste history screenshots keep clear airdrop share quick look"
        case .activities:
            "live activity activities dynamic island music cover waveform closed battery charging low power plugged devices airpods headphones keyboard mouse trackpad bluetooth airplay timer countdown"
        case .opening: "hover click delay hold haptic feedback gestures swipe slide tool trackpad keyboard shortcut hotkey"
        case .displays: "monitor external virtual notch full screen menu bar"
        }
    }
}

/// A page's icon as System Settings draws its own: by macOS, in the icon style chosen in Appearance
/// settings (colored, dark, clear or tinted). Pages System Settings has too use its icons; the
/// others are described the same way and drawn by macOS just the same.
private struct PaneIcon: View {
    let pane: SettingsPane
    /// The tile's side: 20 points in the sidebar, like System Settings'.
    var size: CGFloat = 20
    /// Drawn again when another icon style, or light or dark, is chosen.
    @ObservedObject private var style = IconStyle.shared

    var body: some View {
        if let image = SystemIcons.image(for: pane) {
            // The tile fills four fifths of the picture.
            Image(nsImage: image)
                .resizable()
                .frame(width: size / 0.8, height: size / 0.8)
                .frame(width: size, height: size)
        } else {
            SettingsIcon(symbol: pane.symbol, color: pane.color, size: size)
        }
    }
}

/// The top of a feature's page, as System Settings' Siri page has it: the page's icon, its name, and
/// how it works in a line or two, with the same room on every side of the icon and beside it. A
/// page that's one feature has that feature's switch beside them, as Wi-Fi and Bluetooth do.
struct PageIntro<Control: View>: View {
    let pane: SettingsPane
    let text: String
    @ViewBuilder let control: Control

    /// Around the icon and between it and the words, measured from the Siri page.
    private let room: CGFloat = 15

    init(_ pane: SettingsPane, _ text: String, @ViewBuilder control: () -> Control = { EmptyView() }) {
        self.pane = pane
        self.text = text
        self.control = control()
    }

    var body: some View {
        HStack(spacing: room) {
            PaneIcon(pane: pane, size: 49)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        // The rest of it comes from the form's row.
        .padding(.leading, room - GroupMetrics.inset)
        .padding(.vertical, room - GroupMetrics.inset)
    }
}

/// The icon style chosen in Appearance settings, and light or dark: when either changes, the
/// icons macOS drew in the old one are let go, to be drawn again in the new one.
@MainActor
private final class IconStyle: ObservableObject {
    static let shared = IconStyle()
    @Published private(set) var changes = 0
    private var appearance: NSKeyValueObservation?

    private init() {
        // AppKit's word that the icon style changed; icons it draws from then on are in the new one.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: Notification.Name("NSWorkspaceIconAppearanceConfigurationDidChangeNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        appearance = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
        }
    }

    private func changed() {
        SystemIcons.forget()
        changes += 1
    }
}

@MainActor
private enum SystemIcons {
    private static var images: [SettingsPane: NSImage] = [:]

    static func forget() {
        images = [:]
    }

    static func image(for pane: SettingsPane) -> NSImage? {
        if let image = images[pane] { return image }
        guard let bundle = bundle(for: pane) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: bundle.path)
        images[pane] = image
        return image
    }

    private static func bundle(for pane: SettingsPane) -> URL? {
        let settings = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
        return switch pane {
        case .general: existing(settings.appending(path: "GeneralSettings.appex"))
        case .appearance: existing(settings.appending(path: "Appearance.appex"))
        case .displays: existing(settings.appending(path: "DisplaysExt.appex"))
        case .player: described(pane, symbol: "music.note", color: "Red")
        case .tray: described(pane, symbol: "tray.full.fill", color: "Indigo")
        case .activities: described(pane, symbol: "capsule.fill", color: "Green")
        case .opening: described(pane, symbol: "cursorarrow.click.2", color: "Orange")
        }
    }

    private static func existing(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A bundle holding nothing but the description of an icon, a symbol on a colored tile, in the
    /// form System Settings' extensions give theirs.
    private static func described(_ pane: SettingsPane, symbol: String, color: String) -> URL? {
        let bundle = URL.cachesDirectory.appending(path: "dev.vibe.Glance/Settings Icons/\(pane.rawValue).appex")
        let info: [String: Any] = [
            "CFBundleIdentifier": "dev.vibe.Glance.settings-icon.\(pane.rawValue)",
            "CFBundlePackageType": "XPC!",
            "CFBundleName": pane.title,
            "CFBundleIcons": ["ISGraphicIconConfiguration": ["ISSymbolName": symbol, "ISEnclosureColor": color, "ISSymbolColor": "White"]],
        ]
        let plist = bundle.appending(path: "Contents/Info.plist")
        guard let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0) else { return nil }
        if (try? Data(contentsOf: plist)) != data {
            try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? data.write(to: plist)) != nil else { return nil }
        }
        return bundle
    }
}

/// A symbol on a small square in the icon style chosen in Appearance settings, for when macOS
/// can't draw a page's icon itself.
private struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    private enum Style {
        case regular, dark, clear, tinted

        static var current: Style {
            let theme = UserDefaults.standard.string(forKey: "AppleIconAppearanceTheme") ?? ""
            if theme.hasPrefix("Clear") { return .clear }
            if theme.hasPrefix("Tinted") { return .tinted }
            return theme.contains("Dark") ? .dark : .regular
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        let glyph = Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .medium))
            .frame(width: size, height: size)
        Group {
            switch Style.current {
            case .regular:
                glyph.foregroundStyle(.white).background(color.gradient, in: shape)
            case .dark:
                glyph.foregroundStyle(color.gradient).background(Color(white: 0.13), in: shape)
            case .clear:
                // Measured from System Settings: the same flat gray in light and dark.
                glyph.foregroundStyle(.white).background(Color(white: 0.557), in: shape)
            case .tinted:
                glyph.foregroundStyle(.white).background(Color.accentColor.gradient, in: shape)
            }
        }
    }
}

/// A group's title, as close to the group above it as the page's margin, as in System Settings.
struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .padding(.top, -15)
    }
}
