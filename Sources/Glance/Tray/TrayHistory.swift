//
//  TrayHistory.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import Combine
import Quartz
import SwiftUI

/// Everything the tray has kept, in a window like Spotlight's: what was copied, screenshots, and
/// what was dropped on the notch, by day, newest first, to search, look through with Quick Look,
/// copy, paste, drag out, AirDrop or remove. It floats over every app without leaving the one in
/// front, and goes once something else is clicked, as Spotlight does.
@MainActor
final class TrayHistoryController: NSObject, NSWindowDelegate {
    static let shared = TrayHistoryController()
    static let size = CGSize(width: 700, height: 500)

    private var panel: HistoryPanel?
    private var model: TrayHistoryModel?
    private var keys: Any?
    private var pasteWatch: AnyCancellable?

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let model = TrayHistoryModel(tray: .shared)
        let panel = HistoryPanel(contentRect: CGRect(origin: .zero, size: Self.size))
        let host = NSHostingView(rootView: TrayHistoryView(model: model) { [weak self] in self?.close() })
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self
        // A little below the top of the display the pointer is on, as Spotlight sits.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: visible.midX - Self.size.width / 2, y: visible.maxY - 64 - Self.size.height))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        self.model = model
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let (code, command, window) = (Int(event.keyCode), event.modifierFlags.contains(.command), event.windowNumber)
            let handled = MainActor.assumeIsolated { self?.key(code, command: command, window: window) ?? false }
            return handled ? nil : event
        }
        // Pasted: back to the app it's pasted into.
        pasteWatch = NotificationCenter.default.publisher(for: Tray.didPaste).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        model = nil
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        pasteWatch = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    /// Something else clicked: it goes, unless it's Quick Look, showing what was chosen here.
    func windowDidResignKey(_ notification: Notification) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared()?.isVisible == true { return }
        close()
    }

    /// Finder's keys: Space or ⌘Y for Quick Look, ⌘A, ⌘C and ⌘⌫ for the chosen items, Return to
    /// paste one; Escape clears the search, then closes. Typing goes to the search field.
    private func key(_ code: Int, command: Bool, window: Int) -> Bool {
        guard let panel, window == panel.windowNumber, let model else { return false }
        let chosen = model.chosen
        switch (code, command) {
        case (53, _):
            if model.query.isEmpty { close() } else { model.query = "" }
        case (49, false) where model.query.isEmpty && !chosen.isEmpty, (16, true) where !chosen.isEmpty:
            TrayQuickLook.shared.show(TrayQuickLook.urls(for: chosen, in: model.tray))
        case (0, true) where model.query.isEmpty:
            model.chooseAll()
        case (8, true) where !chosen.isEmpty:
            model.tray.copy(chosen)
        case (51, true) where !chosen.isEmpty:
            model.tray.remove(Set(chosen.map(\.id)))
        case (36, false) where chosen.count == 1:
            model.tray.paste(chosen[0])
        default:
            return false
        }
        return true
    }

    // Quick Look, from this window: it's the panel's controller while it's in front.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = TrayQuickLook.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }
}

/// A borderless, clear panel that takes the keyboard without bringing Glance to the front.
private final class HistoryPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// What the history window shows: the tray's items, filtered and searched, and those chosen.
@MainActor
final class TrayHistoryModel: ObservableObject, TraySelecting {
    enum Filter: String, CaseIterable, Identifiable {
        case all, copied, screenshots, dropped

        var id: Self { self }
        var title: String {
            switch self {
            case .all: "All"
            case .copied: "Copied"
            case .screenshots: "Screenshots"
            case .dropped: "Dropped"
            }
        }

        func admits(_ item: TrayItem) -> Bool {
            switch self {
            case .all: true
            case .copied: item.origin == .copied
            case .screenshots: item.origin == .screenshot
            case .dropped: item.origin == .dropped
            }
        }
    }

    let tray: Tray
    @Published var query = ""
    @Published var filter = Filter.all
    @Published private(set) var selection: Set<UUID> = []
    private var anchor: UUID?
    private var trayWatch: AnyCancellable?

    init(tray: Tray) {
        self.tray = tray
        trayWatch = tray.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var shown: [TrayItem] {
        let words = query.lowercased().split(separator: " ")
        return tray.items.filter { item in
            guard filter.admits(item) else { return false }
            guard !words.isEmpty else { return true }
            let text = ([item.title, TrayItemPicture.caption(for: item), item.text ?? ""] + item.names).joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    var chosen: [TrayItem] { shown.filter { selection.contains($0.id) } }

    func choose(_ id: UUID, toggling: Bool, extending: Bool) {
        let order = shown
        if extending, let anchor, let from = order.firstIndex(where: { $0.id == anchor }),
            let to = order.firstIndex(where: { $0.id == id })
        {
            selection = Set(order[min(from, to)...max(from, to)].map(\.id))
            return
        }
        if toggling {
            if selection.remove(id) == nil { selection.insert(id) }
        } else {
            selection = [id]
        }
        anchor = id
    }

    func chooseAll() {
        selection = Set(shown.map(\.id))
    }

    func deselect() {
        selection = []
        anchor = nil
    }

    func targets(of item: TrayItem) -> [TrayItem] {
        selection.contains(item.id) ? chosen : [item]
    }
}

struct TrayHistoryView: View {
    @ObservedObject var model: TrayHistoryModel
    let close: () -> Void
    @FocusState private var searching: Bool

    private static let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        let shown = model.shown
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search Tray History", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($searching)
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            Divider()
                .padding(.horizontal, 12)
            HStack(spacing: 12) {
                Picker("Show", selection: $model.filter) {
                    ForEach(TrayHistoryModel.Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                actions(shown)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            if shown.isEmpty {
                empty
            } else {
                grid(shown)
            }
        }
        .frame(width: TrayHistoryController.size.width, height: TrayHistoryController.size.height)
        .background { Color.clear.glassEffect(.regular, in: Self.shape) }
        .clipShape(Self.shape)
        .onAppear { searching = true }
        .onChange(of: model.filter) { model.deselect() }
        .onChange(of: model.query) { model.deselect() }
    }

    /// With items chosen: how many, and what can be done with them all; otherwise how many there are.
    @ViewBuilder private func actions(_ shown: [TrayItem]) -> some View {
        let chosen = model.chosen
        if chosen.isEmpty {
            Text(shown.count == 1 ? "1 Item" : "\(shown.count) Items")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text("\(chosen.count) Selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            ControlGroup {
                Button {
                    model.tray.airDrop(model.tray.shareable(chosen))
                } label: {
                    Label("AirDrop", systemImage: "dot.radiowaves.left.and.right")
                }
                .help("AirDrop")
                Button {
                    model.tray.copy(chosen)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy")
                Button {
                    model.tray.remove(Set(chosen.map(\.id)))
                } label: {
                    Label("Remove from Tray", systemImage: "minus.circle")
                }
                .help("Remove from Tray")
            }
            .controlGroupStyle(.navigation)
            .fixedSize()
        }
    }

    private func grid(_ shown: [TrayItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 120), spacing: 4)], alignment: .leading, spacing: 6) {
                ForEach(Self.days(of: shown), id: \.day) { group in
                    Section {
                        ForEach(group.items) { HistoryTile(item: $0, model: model) }
                    } header: {
                        Text(Self.title(of: group.day))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                            .padding(.leading, 4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        // A click between items lets go of the chosen ones, as in Finder.
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture { model.deselect() }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: model.query.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text(model.query.isEmpty ? "No History" : "No Results")
                .font(.title3.weight(.semibold))
            Text(
                model.query.isEmpty
                    ? "What you copy, your screenshots and what you drop on the notch show up here."
                    : "Nothing in the tray matches “\(model.query)”."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Items by the day they came in.
    private static func days(of items: [TrayItem]) -> [(day: Date, items: [TrayItem])] {
        let calendar = Calendar.current
        var groups: [(day: Date, items: [TrayItem])] = []
        for item in items {
            let day = calendar.startOfDay(for: item.added)
            if groups.last?.day == day { groups[groups.count - 1].items.append(item) } else { groups.append((day, [item])) }
        }
        return groups
    }

    /// Today, Yesterday, then the weekday for this week, then the date, as Photos heads its days.
    private static func title(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if let week = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)), day >= week {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// An item in the history window, as Finder shows a file in its icon view: its picture, its name
/// under it, chosen in the accent color, and when it came in.
private struct HistoryTile: View {
    let item: TrayItem
    @ObservedObject var model: TrayHistoryModel
    @State private var hovered = false

    var body: some View {
        let chosen = model.selection.contains(item.id)
        let copied = model.tray.justCopied.contains(item.id)
        VStack(spacing: 4) {
            TrayItemPicture(item: item, tray: model.tray, side: 60)
                .padding(5)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.primary.opacity(chosen ? 0.12 : hovered ? 0.06 : 0))
                }
                .overlay {
                    if copied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(white: 0.2).opacity(0.85))
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
            Text(TrayItemPicture.caption(for: item))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .foregroundStyle(chosen ? .white : .primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background {
                    if chosen { RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor) }
                }
                .frame(maxWidth: 100)
            Text(item.added.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(width: 104, height: 132, alignment: .top)
        .padding(.top, 4)
        .overlay {
            TileInteraction(item: item, tray: model.tray, selector: model, clickSelects: true) { hovered = $0 }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: copied)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}
