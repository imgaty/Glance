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
            }
            .formStyle(.grouped)
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
        case .music: MusicPage()
        case .opening: OpeningPage()
        case .displays: DisplaysPage()
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
    case general, appearance, music, opening, displays

    var id: Self { self }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .music: "Music"
        case .opening: "Opening"
        case .displays: "Displays"
        }
    }

    /// Those of System Settings' own pages where they have one.
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .music: "music.note"
        case .opening: "cursorarrow.click.2"
        case .displays: "sun.max.fill"
        }
    }

    /// The pages about how the notch looks and works show it, live, at the top.
    var showsPreview: Bool { [.appearance, .music, .opening].contains(self) }

    var color: Color {
        switch self {
        case .general: .gray
        case .appearance: Color(white: 0.15)
        case .music: .pink
        case .opening: .orange
        case .displays: .blue
        }
    }

    /// Words a search in the sidebar finds the page by.
    var keywords: String {
        switch self {
        case .general: "login launch startup permissions about build version source"
        case .appearance: "look glass system black clear dark blur opaque liquid transparency accent color artwork background spotlight fullscreen display preview"
        case .music:
            "player apps sources apple music spotify safari browser layout cover progress bar controls customize buttons favorite shuffle repeat output lyrics waveform animated art live activity announce songs closed"
        case .opening: "hover click delay hold haptic feedback gestures swipe trackpad keyboard shortcut hotkey"
        case .displays: "monitor external virtual notch full screen menu bar"
        }
    }
}

/// A page's icon as System Settings draws its own: by macOS, in the icon style chosen in Appearance
/// settings (colored, dark, clear or tinted). Pages System Settings has too use its icons; the
/// others are described the same way and drawn by macOS just the same.
private struct PaneIcon: View {
    let pane: SettingsPane
    /// Drawn again when another icon style, or light or dark, is chosen.
    @ObservedObject private var style = IconStyle.shared

    var body: some View {
        if let image = SystemIcons.image(for: pane) {
            // The tile fills four fifths of the picture: 20 points, like System Settings'.
            Image(nsImage: image)
                .resizable()
                .frame(width: 25, height: 25)
                .frame(width: 20, height: 20)
        } else {
            SettingsIcon(symbol: pane.symbol, color: pane.color)
        }
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
        case .music: described(pane, symbol: "music.note", color: "Red")
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
    private let size: CGFloat = 20

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
