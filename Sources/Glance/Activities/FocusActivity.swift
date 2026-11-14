import AppKit
import ApplicationServices
import SwiftUI

/// A change that macOS actually announced. This is not a query for the current Focus mode:
/// Control Center can change Focus without issuing a banner, and inaccessible state stays unknown.
struct FocusChange: Equatable, Sendable {
    enum State: Equatable, Sendable { case on, off }

    let name: String
    let symbol: String
    let state: State
    /// Preserve the state word from the native banner, in its language.
    let stateText: String

    var text: String { "\(name) · \(stateText)" }
    var spoken: String { "\(name), \(stateText)" }

    @MainActor
    func alert(kind: NotchAlert.Kind) -> NotchAlert {
        // Accessibility supplies the symbol and name, but not a Focus mode's color. Use the
        // user's semantic accent instead of guessing a private mode-to-color mapping.
        NotchAlert(
            kind: kind, content: .status(symbol: symbol, tint: state == .on ? .accentColor : .secondary, text: text),
            spoken: spoken, name: name)
    }

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

/// Observes only real Focus banner creation. It does not open Control Center, request permission,
/// infer Off from absence, read private Focus preferences, or suppress macOS's banner.
final class FocusWatch: @unchecked Sendable {
    static let shared = FocusWatch()
    private static let menuBarAgent = "com.apple.MenuBarAgent"

    private let lock = NSLock()
    private var onChange: (@MainActor @Sendable (FocusChange) -> Void)?
    private var generation: UInt64 = 0
    @MainActor private var following: Task<Void, Never>?

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
        following = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                // Only reattach after permission or process changes; no Focus state is polled.
                self.follow()
            }
        }
    }

    @MainActor
    func stop() {
        following?.cancel()
        following = nil
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
                                    symbolExists: {
                                        NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
                                    }),
                                let callback = self.lock.withLock({ self.generation == version ? self.onChange : nil })
                            else { return }
                            callback(change)
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
