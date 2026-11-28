import AppKit
import ApplicationServices
import SwiftUI

/// A change that macOS announced, in its banner or in what Do Not Disturb's service logs. This is not
/// a query for the current Focus mode: what neither says stays unknown.
struct FocusChange: Equatable, Sendable {
    enum State: Equatable, Sendable { case on, off }

    let name: String
    let symbol: String
    let state: State
    /// Preserve the state word from the native banner, in its language.
    let stateText: String

    /// Beside the camera, as the iPhone and the Mac show it: the state's word alone, the symbol saying
    /// which Focus.
    var text: String { stateText }
    var spoken: String { "\(name), \(stateText)" }

    @MainActor
    func alert(kind: NotchAlert.Kind) -> NotchAlert {
        NotchAlert(
            kind: kind, content: .status(symbol: symbol, tint: state == .on ? Self.color(for: symbol) : Self.off, text: text, on: state == .on),
            spoken: spoken, seconds: Self.shows, name: name)
    }

    /// Accessibility gives a Focus's symbol and name but not its color. Apple's own Focuses each keep
    /// one color with their symbol (DoNotDisturb.framework), drawn as the system color in the dark,
    /// as on the iPhone's Dynamic Island; a Focus of your own takes your Mac's accent color.
    @MainActor
    static func color(for symbol: String) -> Color {
        let system: NSColor? =
            switch symbol {
            // Do Not Disturb's moon in purple, as macOS 27's own artwork and an iPhone recording show it.
            case "moon.fill", "person.fill", "_gm": .systemPurple
            case "bed.double.fill", "car.fill": .systemIndigo
            case "person.lanyardcard.fill": .systemTeal
            case "figure.run": .systemGreen
            case "book.closed.fill": .systemOrange
            case "rocket.fill": .systemBlue
            case "apple.mindfulness": .systemMint
            default: nil
            }
        guard let system else { return .accentColor }
        var resolved = system
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance { resolved = system.usingColorSpace(.sRGB) ?? system }
        return Color(nsColor: resolved)
    }

    /// Off, as the iPhone shows it: gray.
    static let off = Color(white: 103 / 255)

    /// How long a Focus changing shows beside the camera. It extends only with the pointer on it, or
    /// clicked, as every live activity's extended view does (the user, 2026-11-28: the extended view
    /// "is a view for when the user clicks/hovers on the notch"), never by itself.
    static let shows = 3.4

    static func read(
        _ snapshot: FocusBannerSnapshot, words: FocusStateWords?, symbolExists: (String) -> Bool
    ) -> FocusChange? {
        guard snapshot.identifier == FocusBannerSnapshot.identifier,
            let words, snapshot.texts.count == 2, snapshot.images.count == 1
        else { return nil }
        let name = snapshot.texts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let stateText = snapshot.texts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let image = snapshot.images[0]
        guard !name.isEmpty,
            image.description?.trimmingCharacters(in: .whitespacesAndNewlines) == name,
            let symbol = image.symbol, !symbol.isEmpty, symbolExists(symbol),
            let state = words.state(for: stateText)
        else { return nil }
        return FocusChange(name: name, symbol: symbol, state: state, stateText: stateText)
    }
}

/// The observed AX contract, kept separate from live Accessibility reads for deterministic tests.
struct FocusBannerSnapshot: Equatable, Sendable {
    static let identifier = "focus-system-banner"

    struct Image: Equatable, Sendable {
        let symbol: String?
        let description: String?
    }

    let identifier: String?
    let texts: [String]
    let images: [Image]
}

struct FocusStateWords: Equatable, Sendable {
    let on: String
    let off: String

    init?(on: String, off: String) {
        let on = on.trimmingCharacters(in: .whitespacesAndNewlines)
        let off = off.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !on.isEmpty, !off.isEmpty, on != off,
            on != "FOCUS_MODE_ON", off != "FOCUS_MODE_OFF"
        else { return nil }
        self.on = on
        self.off = off
    }

    func state(for text: String) -> FocusChange.State? {
        if text == on { return .on }
        if text == off { return .off }
        return nil
    }

    @MainActor
    static func system() -> FocusStateWords? {
        let bundle = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemBannerUI.framework")
        return FocusStateWords(
            on: SystemNotices.words("FOCUS_MODE_ON", table: "SystemBannerUI", of: bundle),
            off: SystemNotices.words("FOCUS_MODE_OFF", table: "SystemBannerUI", of: bundle))
    }
}

/// What Do Not Disturb's service logs each time its state changes, read from one line of it: the
/// Focus on now and the one on before, each its name, its identifier and its symbol. Control Center
/// drops its own banner when the change comes from its open panel (the user, 2026-11-28: "i turned on
/// do not disturb on my mac and it didnt show on the notch"), and the service logs every change,
/// whatever made it. The line is cut short past about a thousand characters, so the Focus before can be
/// unreadable.
struct FocusStateLine: Equatable, Sendable {
    struct Mode: Equatable, Sendable {
        let identifier: String
        let name: String
        let symbol: String
    }

    /// The Focus on now, or nil with none on.
    let active: Mode?
    /// Whether the line still says which Focus was on before, and which: nil with none on.
    let previousRead: Bool
    let previous: Mode?

    static let prefix = "Delivering state update:"

    static func read(_ message: String) -> FocusStateLine? {
        guard message.hasPrefix(prefix) else { return nil }
        let parts = message.components(separatedBy: "; previousState: ")
        guard case .some(let active) = configuration(in: parts[0]) else { return nil }
        let previous = parts.count > 1 ? configuration(in: parts[1]) : nil
        return FocusStateLine(active: active, previousRead: previous != nil, previous: previous ?? nil)
    }

    /// The Focus a state names: none, one, or unreadable (nil).
    private static func configuration(in part: String) -> Mode?? {
        guard let start = part.range(of: "activeModeConfiguration: ") else { return nil }
        let rest = part[start.upperBound...]
        if rest.hasPrefix("(null)") { return .some(nil) }
        func field(_ name: String) -> String? {
            guard let range = rest.range(of: "; \(name): ") else { return nil }
            let value = rest[range.upperBound...].prefix { $0 != ";" && $0 != ">" }
            let text = value.trimmingCharacters(in: .whitespaces)
            return text.isEmpty || text == "(null)" ? nil : text
        }
        guard let identifier = field("modeIdentifier"), let name = field("name"), let symbol = field("symbolImageName") else { return nil }
        return .some(Mode(identifier: identifier, name: name, symbol: symbol))
    }
}

/// Follows the Focus from one logged state to the next, saying what turned on or off. The service
/// logs a state for each of its clients and for changes that leave the Focus as it was, as the screen
/// locks; only a different Focus is news. Before anything's known, a line that doesn't say what was on
/// before is only noted.
struct FocusModeFollower {
    private var known = false
    private(set) var active: FocusStateLine.Mode?

    mutating func take(_ line: FocusStateLine) -> (mode: FocusStateLine.Mode, on: Bool)? {
        let wasKnown = known || line.previousRead
        let before = known ? active : line.previous
        known = true
        defer { active = line.active }
        guard wasKnown, line.active?.identifier != before?.identifier else { return nil }
        if let now = line.active { return (now, true) }
        return before.map { ($0, false) }
    }
}

/// Deduplicate creation notifications by window identity, not the mode name or its current value.
/// A later event for the same Focus is still news. A window present at attachment is not.
struct FocusBannerLedger<ID: Hashable> {
    private var seen: Set<ID> = []

    mutating func prime(_ existing: [ID]) { seen = Set(existing) }

    mutating func newlyCreated(active: [ID]?, candidates: [ID]) -> [ID] {
        // A failed AX read must not forget the existing windows and announce them on recovery.
        guard let active else { return [] }
        let current = Set(active)
        seen.formIntersection(current)
        return candidates.filter { current.contains($0) && seen.insert($0).inserted }
    }
}

/// Observes real Focus banner creation, and what Do Not Disturb's service logs as the Focus changes,
/// which says so when Control Center keeps its banner to itself (see `FocusStateLine`). It does not
/// open Control Center, request permission, infer Off from absence, read private Focus preferences,
/// or suppress macOS's banner. The same change from both is told once.
final class FocusWatch: @unchecked Sendable {
    static let shared = FocusWatch()
    private static let menuBarAgent = "com.apple.MenuBarAgent"

    private let lock = NSLock()
    private var onChange: (@MainActor @Sendable (FocusChange) -> Void)?
    private var generation: UInt64 = 0
    @MainActor private var following: Task<Void, Never>?
    /// `log stream`, following the service's state lines, and when to try it again after it ended
    /// soon after starting, as it does for an account that isn't an administrator.
    @MainActor private var stream: Process?
    @MainActor private var streamRetry = Date.distantPast
    @MainActor private var quitting: NSObjectProtocol?
    @MainActor private var follower = FocusModeFollower()
    /// The last change told, so the banner and the log don't both tell it.
    @MainActor private var told: (change: FocusChange, at: Date)?
    static let sameChange: TimeInterval = 4

    // Owned by the dedicated AX run loop from here on.
    private var app: AXUIElement?
    private var agent: pid_t = 0
    private var observer: AXObserver?
    private var words: FocusStateWords?
    private var ledger = FocusBannerLedger<AXUIElement>()

    private init() {}

    private lazy var runLoop: CFRunLoop = {
        let ready = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var loop: CFRunLoop?
        let thread = Thread {
            loop = CFRunLoopGetCurrent()
            RunLoop.current.add(Port(), forMode: .default)
            ready.signal()
            RunLoop.current.run()
        }
        thread.name = "Focus banners"
        thread.qualityOfService = .utility
        thread.start()
        ready.wait()
        return loop!
    }()

    /// The caller owns the activity preference and announcement queue. Receiving a change does
    /// not mean it is visibly rendered, so this observer leaves the native banner available.
    @MainActor
    func start(onChange: @escaping @MainActor @Sendable (FocusChange) -> Void) {
        lock.withLock {
            self.onChange = onChange
            generation &+= 1
        }
        guard following == nil else { return }
        follow()
        followLog()
        following = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                // Only reattach after permission or process changes; no Focus state is polled.
                self.follow()
                self.followLog()
            }
        }
    }

    /// Follows the service's state lines in the system log, from now on, if it isn't already.
    @MainActor
    private func followLog() {
        guard lock.withLock({ onChange != nil }), stream == nil, Date.now >= streamRetry else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream", "--style", "ndjson",
            "--predicate", "process == \"donotdisturbd\" AND eventMessage BEGINSWITH \"\(FocusStateLine.prefix)\"",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let lines = LogLines()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            for message in lines.take(data) {
                guard let line = FocusStateLine.read(message) else { continue }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.took(line) } }
            }
        }
        let started = Date.now
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.stream = nil
                    // Ended right away: not allowed, or not there. Try again in a while.
                    if Date.now.timeIntervalSince(started) < 5 { self.streamRetry = .now + 60 }
                }
            }
        }
        do {
            try process.run()
            stream = process
        } catch {
            streamRetry = .now + 60
        }
        // Not left running past Glance.
        if quitting == nil {
            quitting = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stream?.terminate() }
            }
        }
    }

    @MainActor
    private func took(_ line: FocusStateLine) {
        guard let (mode, on) = follower.take(line), let words = FocusStateWords.system() else { return }
        // A Focus of your own can take a symbol the Mac doesn't draw.
        let symbol = SystemSymbol.exists(mode.symbol) ? mode.symbol : "moon.fill"
        tell(FocusChange(name: mode.name, symbol: symbol, state: on ? .on : .off, stateText: on ? words.on : words.off))
    }

    /// Tells a change once, however many of the banner and the log say it.
    @MainActor
    private func tell(_ change: FocusChange) {
        if let told, told.change.name == change.name, told.change.state == change.state, Date.now.timeIntervalSince(told.at) < Self.sameChange { return }
        told = (change, .now)
        lock.withLock { onChange }?(change)
    }

    @MainActor
    func stop() {
        following?.cancel()
        following = nil
        stream?.terminate()
        stream = nil
        lock.withLock {
            onChange = nil
            generation &+= 1
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in detach() }
        CFRunLoopWakeUp(runLoop)
    }

    @MainActor
    func follow() {
        guard lock.withLock({ onChange != nil }) else { return }
        guard AXIsProcessTrusted(),
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: Self.menuBarAgent).first?.processIdentifier,
            let words = FocusStateWords.system()
        else {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in detach() }
            CFRunLoopWakeUp(runLoop)
            return
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in attach(to: agent, words: words) }
        CFRunLoopWakeUp(runLoop)
    }

    private func attach(to agent: pid_t, words: FocusStateWords) {
        guard lock.withLock({ onChange != nil }) else { return }
        guard agent != self.agent || words != self.words else { return }
        detach()
        let app = AXUIElementCreateApplication(agent)
        AXUIElementSetMessagingTimeout(app, 0.25)
        // Without a successful baseline, an already-showing banner might be mistaken for news.
        guard let existing = SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] else { return }
        var made: AXObserver?
        let told: AXObserverCallback = { _, _, _, _ in FocusWatch.shared.changed() }
        guard AXObserverCreate(agent, told, &made) == .success, let made else { return }
        let created = AXObserverAddNotification(made, app, kAXCreatedNotification as CFString, nil)
        let windowCreated = AXObserverAddNotification(made, app, kAXWindowCreatedNotification as CFString, nil)
        guard created == .success || windowCreated == .success else { return }
        ledger.prime(existing)
        self.agent = agent
        self.app = app
        self.words = words
        observer = made
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(made), .defaultMode)
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        app = nil
        agent = 0
        words = nil
        ledger.prime([])
    }

    private func changed() {
        guard let app, let words,
            let windows = SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement]
        else { return }
        let candidates = windows.filter {
            SystemNotices.value($0, kAXIdentifierAttribute) as? String == FocusBannerSnapshot.identifier
        }
        let fresh = ledger.newlyCreated(active: windows, candidates: candidates)
        let version = lock.withLock { generation }
        for window in fresh {
            // The creation notification can precede its children. Wait briefly on this AX thread,
            // leaving the native banner in place while its complete content is becoming readable.
            for _ in 0..<25 {
                guard lock.withLock({ onChange != nil && generation == version }) else { return }
                if let snapshot = Self.snapshot(window),
                    FocusChange.read(snapshot, words: words, symbolExists: { _ in true }) != nil
                {
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, AXIsProcessTrusted(),
                                let change = FocusChange.read(
                                    snapshot, words: words,
                                    // Apple keeps some Focus symbols, like Work's, to itself.
                                    symbolExists: SystemSymbol.exists),
                                self.lock.withLock({ self.generation == version })
                            else { return }
                            self.tell(change)
                        }
                    }
                    break
                }
                usleep(20_000)
            }
        }
    }

    /// A small, bounded walk of this one banner, using the same safe AX accessor as other notices.
    private static func snapshot(_ window: AXUIElement) -> FocusBannerSnapshot? {
        guard let identifier = SystemNotices.value(window, kAXIdentifierAttribute) as? String,
            identifier == FocusBannerSnapshot.identifier
        else { return nil }
        var texts: [String] = []
        var images: [FocusBannerSnapshot.Image] = []
        var pending: [(AXUIElement, Int)] = [(window, 0)]
        var seen: Set<AXUIElement> = []
        while let (element, depth) = pending.popLast() {
            guard seen.insert(element).inserted else { continue }
            guard seen.count <= 64, depth <= 12 else { return nil }
            switch SystemNotices.value(element, kAXRoleAttribute) as? String {
            case kAXStaticTextRole:
                guard let value = SystemNotices.value(element, kAXValueAttribute) as? String else { return nil }
                texts.append(value)
            case kAXImageRole:
                images.append(
                    .init(
                        symbol: SystemNotices.value(element, kAXIdentifierAttribute) as? String,
                        description: SystemNotices.value(element, kAXDescriptionAttribute) as? String))
            default: break
            }
            let children = SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            pending += children.reversed().map { ($0, depth + 1) }
        }
        return FocusBannerSnapshot(identifier: identifier, texts: texts, images: images)
    }
}

/// A Focus changing, extended, as the iPhone shows it for a moment after it changes, measured from a
/// recording: the symbol in a circle at the left end, white with the symbol in its color when it's on,
/// the color faintly behind it when it's off; the Focus's name in white beside it; the state's word at
/// the right end, in the color. The words stand as high as they go under the camera, so they run on
/// beneath it.
struct FocusExtendedView: View {
    let symbol: String
    let tint: Color
    let name: String
    let state: String
    let on: Bool
    let restingHeight: CGFloat

    /// From the right end to the state's word: its ink as far in as the circle is from the left end,
    /// and from the top and bottom (the user, 2026-11-28: the padding "consistent all around").
    static func stateEnd(_ state: String, restingHeight h: CGFloat) -> CGFloat {
        circleEdge(h) - Ink.trail(state, font: .systemFont(ofSize: NotchType.size, weight: .semibold))
    }
    /// The circle, 56 points across and 14 in from its end on the iPhone's 84-point island.
    static func circle(_ h: CGFloat) -> CGFloat { TimerLayout.rowHeight(h) * 56 / 84 }
    static func circleEdge(_ h: CGFloat) -> CGFloat { TimerLayout.rowHeight(h) * 14 / 84 }

    var body: some View {
        let h = restingHeight
        let tall = TimerLayout.rowHeight(h)
        let side = Self.circle(h)
        ZStack {
            SystemSymbol.glyph(symbol, size: side * 0.5)
                .foregroundStyle(on ? tint : .white)
                .frame(width: side, height: side)
                .background(Circle().fill(on ? Color.white : tint.opacity(0.29)))
                .padding(.leading, Self.circleEdge(h))
                .frame(maxWidth: .infinity, alignment: .leading)
            // The name and its state on one line, as high as they go under the camera.
            HStack(alignment: .firstTextBaseline, spacing: h * AirDropLayout.gap) {
                Text(name)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(state)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(IslandType.title(restingHeight))
            .firstBaseline(Self.wordsBaseline(name: name, state: state, restingHeight: h))
            .padding(.leading, Self.circleEdge(h) + side + h * AirDropLayout.gap)
            .padding(.trailing, Self.stateEnd(state, restingHeight: h))
        }
        .frame(height: tall)
    }

    /// Each side of the camera: the circle beside it, as it stands as high as the camera, and the words
    /// under it, a long name cut short, as the iPhone's is.
    @MainActor
    static func wing(restingHeight h: CGFloat, closedWidth: CGFloat) -> CGFloat {
        (circleEdge(h) + circle(h) + LiveActivityView.cameraGap).rounded(.up)
    }

    /// Where the name and its state stand: as high as they go under the camera.
    static func wordsBaseline(name: String, state: String, restingHeight h: CGFloat) -> CGFloat {
        UnderCamera.baseline([name, state], font: .systemFont(ofSize: NotchType.size, weight: .semibold), restingHeight: h)
    }
}

/// Whole lines from a stream of the system log's newline-delimited JSON, each line's message.
final class LogLines: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    func take(_ data: Data) -> [String] {
        lock.withLock {
            pending.append(data)
            var messages: [String] = []
            while let end = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<end]
                pending.removeSubrange(pending.startIndex...end)
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let message = object["eventMessage"] as? String {
                    messages.append(message)
                }
            }
            return messages
        }
    }
}
