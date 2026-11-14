import AppKit
import SwiftUI

struct ShortcutRunMark: View {
    let shown: ShortcutShown
    let restingHeight: CGFloat
    var leadingOnly = false
    static let wing: CGFloat = 96

    var body: some View {
        ZStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/Shortcuts.app"))
                .resizable().scaledToFit()
                .frame(width: max(0, restingHeight - LiveActivityView.inset * 2), height: max(0, restingHeight - LiveActivityView.inset * 2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            if !leadingOnly {
                Text(shown.run.shortcut.name)
                    .lineLimit(1)
                    .frame(width: Self.wing - LiveActivityView.inset * 2, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.body)
        .padding(.horizontal, LiveActivityView.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
    }
}

/// App-owned CLI runs use standard macOS controls. The spinner means only that the process is
/// active; it does not pretend to report workflow progress or detect whether input is needed.
struct ShortcutRunView: View {
    let shown: ShortcutShown
    var stop: () -> Void = {}
    var dismiss: () -> Void = {}
    var openShortcuts: () -> Void = {}
    var showResult: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func width(camera: CGFloat) -> CGFloat { max(400, camera + PlayerLayout.padding * 2) }
    static func height(restingHeight: CGFloat) -> CGFloat { restingHeight + LiveActivityView.cameraGap + 235 }

    static func controls(for shown: ShortcutShown) -> [PlayerControl] {
        [.activityFirst] + (shown.run.exit?.output != nil ? [.activityThird] : [])
            + (shown.run.canStop || !shown.run.state.active ? [.activitySecond] : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(shown.status).font(.headline)
                Spacer()
                if shown.run.state.active, !reduceMotion {
                    ProgressView().controlSize(.small).accessibilityLabel(shown.status)
                }
            }
            .accessibilityIdentifier("shortcut-status")
            Text(shown.run.shortcut.name)
                .font(.body)
                .lineLimit(2)
                .help(shown.run.shortcut.name)
            if shown.run.state == .stopDelayed {
                Text("The shortcut hasn't stopped yet. You can try again or continue in Shortcuts.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let message = shown.run.message, !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(message)
            } else if shown.run.state.active {
                Text("If your shortcut asks for input, respond in Shortcuts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if shown.additionalRuns > 0 {
                Text("Other runs are available in the Run Shortcut menu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Open Shortcuts", action: openShortcuts)
                    .notchControl()
                    .keyControl(.activityFirst, in: RoundedRectangle(cornerRadius: 6), spoken: String(localized: "Open Shortcuts"), action: openShortcuts)
                    .accessibilityIdentifier("open-shortcuts")
                if shown.run.exit?.output != nil {
                    Button("Show Result", action: showResult)
                        .notchControl()
                        .keyControl(.activityThird, in: RoundedRectangle(cornerRadius: 6), spoken: String(localized: "Show Shortcut Result"), action: showResult)
                        .accessibilityIdentifier("show-shortcut-result")
                }
                Spacer(minLength: 8)
                if shown.run.state.active {
                    Button(shown.run.state == .stopDelayed ? String(localized: "Try Stopping Again") : String(localized: "Stop"), role: .destructive, action: stop)
                        .notchControl()
                        .keyControl(.activitySecond, in: RoundedRectangle(cornerRadius: 6), spoken: String(localized: "Stop Shortcut"), action: stop)
                        .disabled(!shown.run.canStop)
                        .accessibilityIdentifier("stop-shortcut")
                } else {
                    Button("Done", action: dismiss)
                        .notchControl()
                        .keyControl(.activitySecond, in: RoundedRectangle(cornerRadius: 6), spoken: String(localized: "Dismiss Shortcut Result"), action: dismiss)
                        .accessibilityIdentifier("dismiss-shortcut")
                }
            }
            .buttonStyle(.bordered).controlSize(.regular)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shown.spoken)
    }
}
