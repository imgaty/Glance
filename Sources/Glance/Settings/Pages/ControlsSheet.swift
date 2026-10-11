//
//  ControlsSheet.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// Choosing the player's controls as Apple has controls chosen: the player as it opens on screen,
/// life size, its two buttons in edit mode as on the iPhone's Lock Screen (− takes a control away,
/// in a puff of smoke; an empty one shows +; clicking one selects it), and under it the controls, in
/// a section as Settings groups its settings, a click adding one to the selected button. Controls can also
/// be dragged into the player, from one side to the other, or out of it. Restore Defaults puts back
/// the controls it came with.
struct ControlsSheet: View {
    let display: String
    let top: ScreenTop
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preferences.musicLeftButton) private var left = PlayerSlot.favorite
    @AppStorage(Preferences.musicRightButton) private var right = PlayerSlot.output
    @AppStorage(Preferences.musicLayout) private var layout = PlayerLayout.top
    @State private var places = ControlPlaces()
    /// Where the pointer is while a control is dragged.
    @State private var location = CGPoint.zero
    /// The button in the player that choosing a control changes.
    @State private var selected = ControlPlace.left
    /// The control the pointer is over, below the player.
    @State private var hovered: PlayerSlot?

    private static let width: CGFloat = 600
    private static let margin: CGFloat = 20
    private static let pictureWidth = width - margin * 2
    /// How far the pointer moves before a click becomes a drag.
    private static let slop: CGFloat = 3

    var body: some View {
        let open = layout.size(closed: top.notch)
        let gap = top.island ? NotchModel.islandGap : 0
        let chosen = content(at: selected)
        VStack(alignment: .leading, spacing: 0) {
            // As much of the screen as the sheet is wide, life size, down to a little below the player.
            ControlsPicture(layout: layout, display: display, top: top, places: places)
                .id(layout)
                .frame(width: Self.pictureWidth, height: top.edge + gap + open.height + 44)
                .clipShape(RoundedRectangle(cornerRadius: GroupMetrics.radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: GroupMetrics.radius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                }
                .padding([.horizontal, .top], Self.margin)
            // The controls in a section, as System Settings groups its settings: a round button each,
            // named under it, the chosen one in the accent color.
            Form {
                Section {
                    ControlGallery(chosen: chosen, hovered: $hovered, choose: choose) { control in
                        drag(control, from: nil)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(height: 136)
            HStack {
                Button("Restore Defaults") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        left = ControlPlace.left.standard
                        right = ControlPlace.right.standard
                    }
                }
                .disabled(left == ControlPlace.left.standard && right == ControlPlace.right.standard)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], Self.margin)
        }
        .frame(width: Self.width)
        .overlay(alignment: .topLeading) { editing }
        .coordinateSpace(.named(ControlPlaces.space))
        // An empty button is the one to fill first.
        .onAppear { if right == .empty, left != .empty { selected = .right } }
    }

    /// Over the player's two buttons: the selected one ringed in the accent color, each one to
    /// click or pick up, and − on those with a control; and what's being dragged, under the pointer.
    private var editing: some View {
        ZStack(alignment: .topLeading) {
            ForEach(ControlPlace.allCases) { place in
                if let frame = places.frames[place] {
                    let control = content(at: place)
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .frame(width: frame.width + 9, height: frame.height + 9)
                        .position(x: frame.midX, y: frame.midY)
                        .opacity(selected == place && places.dragging == nil ? 1 : 0)
                        .allowsHitTesting(false)
                    Color.clear
                        .contentShape(Circle())
                        .frame(width: frame.width, height: frame.height)
                        .gesture(drag(control, from: place))
                        .pointerStyle(control == .empty ? .link : .grabIdle)
                        .help(control == .empty ? "No button here" : control.summary)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityElement()
                        .accessibilityLabel("\(place == .left ? "Left" : "Right") button: \(control.title)")
                        .accessibilityAddTraits(selected == place ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { selected = place }
                    if control != .empty, places.lifted != place {
                        // As on an app's icon while the Home Screen is being arranged.
                        Button {
                            remove(at: place)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color(white: 0.42)))
                                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(control.title)")
                        .position(x: frame.minX + 7, y: frame.minY + 7)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
            }
            if let control = places.dragging {
                let removing = places.target == nil && places.lifted != nil
                ControlGhost(control: control)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    // As an app dragged off the Dock says so.
                    .overlay(alignment: .top) {
                        if removing {
                            Text("Remove")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.black.opacity(0.72)))
                                .fixedSize()
                                .offset(y: -28)
                                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                        }
                    }
                    .position(location)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.15), value: removing)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: places.dragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: left)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: right)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    /// A click chooses (a control for the selected button, or which button is selected); moved
    /// past a few points, it's a drag.
    private func drag(_ control: PlayerSlot, from source: ControlPlace?) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(ControlPlaces.space))
            .onChanged { value in
                if places.dragging == nil {
                    guard control != .empty, hypot(value.translation.width, value.translation.height) > Self.slop else { return }
                    places.dragging = control
                    places.lifted = source
                }
                location = value.location
                let over = ControlPlace.allCases.first { place in
                    places.frames[place].map { $0.insetBy(dx: -10, dy: -10).contains(value.location) } == true
                }
                if over != places.target {
                    places.target = over
                    if over != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                }
            }
            .onEnded { _ in
                defer {
                    places.dragging = nil
                    places.lifted = nil
                    places.target = nil
                }
                guard places.dragging != nil else {
                    // A click.
                    if let source { selected = source } else { choose(control) }
                    return
                }
                if let target = places.target {
                    put(control, at: target)
                    selected = target
                } else if let source {
                    set(.empty, at: source)
                    poof()
                }
            }
    }

    /// A control chosen for the selected button.
    private func choose(_ control: PlayerSlot) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if control == .empty { set(.empty, at: selected) } else { put(control, at: selected) }
        }
    }

    private func remove(at place: ControlPlace) {
        set(.empty, at: place)
        selected = place
        poof()
    }

    /// Gone in a puff of smoke, as anything dragged off a toolbar or the Dock.
    private func poof() {
        NSAnimationEffect.poof.show(centeredAt: NSEvent.mouseLocation, size: NSSize(width: 40, height: 40))
    }

    private func content(at place: ControlPlace) -> PlayerSlot {
        place == .left ? left : right
    }

    private func set(_ control: PlayerSlot, at place: ControlPlace) {
        if place == .left { left = control } else { right = control }
    }

    /// Puts a control in a place. If it was in the other place, what was here goes there; otherwise
    /// what was here goes back among the rest.
    private func put(_ control: PlayerSlot, at place: ControlPlace) {
        let displaced = content(at: place)
        if let from = ControlPlace.allCases.first(where: { content(at: $0) == control }), from != place {
            set(displaced, at: from)
        }
        set(control, at: place)
    }
}

/// The controls that can be added, each a round button as the notch draws its controls: just its
/// symbol, with a circle behind it under the pointer; the one in the selected button in the accent
/// color. The pointer over one also shows the Controls Gallery's green +; a click adds it to the
/// selected button, and it can be dragged into the player.
private struct ControlGallery<Drag: Gesture>: View {
    let chosen: PlayerSlot
    @Binding var hovered: PlayerSlot?
    let choose: (PlayerSlot) -> Void
    let drag: (PlayerSlot) -> Drag

    var body: some View {
        // The same space between the buttons as at the row's ends.
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(PlayerSlot.controls) { control in
                let isChosen = control == chosen
                // Its name under it, as the welcome tour names its choices: bold for the chosen one.
                VStack(spacing: 6) {
                    // The size the player draws its controls.
                    ControlSymbol(control: control)
                        .font(.system(size: PlayerLayout.optionGlyph, weight: .medium))
                        .foregroundStyle(isChosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .hoverCircle(hovered == control, diameter: NowPlayingView.hitbox + 6)
                        .overlay(alignment: .topLeading) {
                            if hovered == control, !isChosen {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .green)
                                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                                    .offset(x: -2, y: -2)
                                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                            }
                        }
                    Text(control.title)
                        .font(.system(size: 12, weight: isChosen ? .semibold : .regular))
                        .foregroundStyle(isChosen ? .primary : .secondary)
                        .fixedSize()
                }
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hovered = control } else if hovered == control { hovered = nil }
                }
                .gesture(drag(control))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(control.title)
                .accessibilityHint(control.summary)
                .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { choose(control) }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.15), value: chosen)
    }
}

/// A control picked up from the player, as the player shows it: its symbol on the notch's black.
private struct ControlGhost: View {
    let control: PlayerSlot

    var body: some View {
        ControlSymbol(control: control)
            .font(.system(size: PlayerLayout.optionGlyph, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: NowPlayingView.hitbox, height: NowPlayingView.hitbox)
            .background(Circle().fill(Color(white: 0.12)))
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }
}

/// The picture in the controls sheet: the top of the display's screen, life size, around the
/// notch, with the player open in it over a window and its controls' places marked.
private struct ControlsPicture: View {
    let display: String
    let top: ScreenTop
    let places: ControlPlaces
    @StateObject private var model: NotchModel

    init(layout: PlayerLayout, display: String, top: ScreenTop, places: ControlPlaces) {
        self.display = display
        self.top = top
        self.places = places
        _model = StateObject(wrappedValue: .picture(of: top, layout: layout))
    }

    var body: some View {
        GeometryReader { proxy in
            ScreenPicture(top: top, size: proxy.size) {
                ApplePage.Still()
            } notch: {
                NotchView(model: model, display: display)
                    .environment(\.controlPlaces, places)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct AppIcon: View {
    let bundleID: String
    @MainActor private static var icons: [String: NSImage] = [:]

    var body: some View {
        Group {
            if let icon = Self.icon(bundleID) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
    }

    /// Looked up once for each app.
    private static func icon(_ app: String) -> NSImage? {
        if let icon = icons[app] { return icon }
        let icon = NSWorkspace.shared.icon(forApp: app)
        icons[app] = icon
        return icon
    }
}
