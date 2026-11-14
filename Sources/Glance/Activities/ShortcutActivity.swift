import AppKit
import Darwin

/// A named item from the public Shortcuts command-line catalog. The UUID, never its name, is run.
struct ShortcutDefinition: Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    let name: String

    static func catalog(_ output: String) throws -> [ShortcutDefinition] {
        var result: [ShortcutDefinition] = []
        var ids: Set<UUID> = []
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard text.hasSuffix(")"), let separator = text.range(of: " (", options: .backwards),
                let id = UUID(uuidString: String(text[separator.upperBound..<text.index(before: text.endIndex)]))
            else { throw ShortcutError.invalidCatalog }
            let name = String(text[..<separator.lowerBound])
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ShortcutError.invalidCatalog }
            if ids.insert(id).inserted { result.append(.init(id: id, name: name)) }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum ShortcutError: Error { case invalidCatalog, unavailable }

/// A private cache entry, never a shortcut input or an exported result. Only completed entries
/// with an ownership receipt are eligible for age cleanup; active and legacy folders are left alone.
struct ShortcutRunStorage: Equatable, Sendable {
    static let retention: TimeInterval = 24 * 60 * 60
    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Glance-ShortcutRuns", isDirectory: true) }
    private static let owner = "Glance.ShortcutRun.v1"
    private static let receiptName = ".glance-completed.json"
    let directory: URL
    var output: URL { directory.appendingPathComponent("Result") }
    var errors: URL { directory.appendingPathComponent("Error.txt") }

    private struct Snapshot: Codable, Equatable {
        let bytes: UInt64
        let fileNumber: UInt64
        let modified: Date
    }
    private struct Receipt: Codable {
        let owner: String
        let directory: String
        let completed: Date
        let result: Snapshot?
    }

    static func create(in root: URL = Self.root) throws -> ShortcutRunStorage {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard isDirectory(root) else { throw ShortcutError.unavailable }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return .init(directory: directory)
    }

    /// Called only after the owned process has exited and closed both output handles.
    func finish(at date: Date = .now) -> (message: String?, output: URL?) {
        let errorSnapshot = Self.snapshot(errors)
        let errorFile: FileHandle? = errorSnapshot == nil ? nil : (try? FileHandle(forReadingFrom: errors))
        let data = try? errorFile?.read(upToCount: 4_096)
        try? errorFile?.close()
        let message = data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        // The raw stderr file is no longer needed once its bounded UI message is retained.
        if let errorSnapshot, Self.snapshot(errors) == errorSnapshot {
            try? FileManager.default.removeItem(at: errors)
        }
        let result = Self.snapshot(output)
        // An unexpected replacement, such as a symlink, is neither opened nor marked for deletion.
        if result != nil || !FileManager.default.fileExists(atPath: output.path) {
            let receipt = Receipt(owner: Self.owner, directory: directory.lastPathComponent, completed: date, result: result)
            if let encoded = try? JSONEncoder().encode(receipt) {
                try? encoded.write(to: directory.appendingPathComponent(Self.receiptName), options: .atomic)
            }
        }
        return (message.flatMap { $0.isEmpty ? nil : $0 }, result.map { $0.bytes > 0 } == true ? output : nil)
    }

    /// Done only discards an empty owned result. Nonempty results expire at a later startup,
    /// once their completion receipt is at least 24 hours old.
    func discardEmptyResult() {
        guard let receipt = receipt(), (receipt.result?.bytes ?? 0) == 0 else { return }
        removeCompleted(receipt)
    }

    /// Run at startup, off the main actor. A file changed by the user is no longer ours to expire.
    static func cleanupExpired(in root: URL = Self.root, now: Date = .now) {
        guard isDirectory(root), let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders {
            let entry = ShortcutRunStorage(directory: folder)
            guard let receipt = entry.receipt(), now.timeIntervalSince(receipt.completed) >= retention else { continue }
            entry.removeCompleted(receipt)
        }
    }

    private func receipt() -> Receipt? {
        guard UUID(uuidString: directory.lastPathComponent) != nil, Self.isDirectory(directory) else { return nil }
        let url = directory.appendingPathComponent(Self.receiptName)
        guard let attributes = Self.snapshot(url), attributes.bytes <= 4_096,
            let data = try? Data(contentsOf: url), let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
            receipt.owner == Self.owner, receipt.directory == directory.lastPathComponent
        else { return nil }
        return receipt
    }

    private func removeCompleted(_ receipt: Receipt) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path),
            Set(names).isSubset(of: ["Result", Self.receiptName])
        else { return }
        if names.contains("Result") {
            // Preserve edited/replaced results; moved/exported files outside this folder are never visited.
            guard let current = Self.snapshot(output), current == receipt.result else { return }
            do { try manager.removeItem(at: output) } catch { return }
        }
        do { try manager.removeItem(at: directory.appendingPathComponent(Self.receiptName)) } catch { return }
        // Unlike recursive removal, rmdir leaves any concurrently added file alone.
        _ = directory.path.withCString { rmdir($0) }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func snapshot(_ url: URL) -> Snapshot? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
            values.isRegularFile == true, values.isSymbolicLink != true,
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let bytes = attributes[.size] as? NSNumber, let number = attributes[.systemFileNumber] as? NSNumber,
            let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return .init(bytes: bytes.uint64Value, fileNumber: number.uint64Value, modified: modified)
    }
}

struct ShortcutExit: Equatable, Sendable {
    enum Reason: Equatable, Sendable { case exit, signal }
    let status: Int32
    let reason: Reason
    var message: String?
    var output: URL?
    var storage: ShortcutRunStorage?
}

struct ShortcutRun: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case starting, running, stopping, stopDelayed
        case completed, stopped, endedAfterStop, failed

        var active: Bool { [.starting, .running, .stopping, .stopDelayed].contains(self) }
        var title: String {
            switch self {
            case .starting: String(localized: "Starting Shortcut…")
            case .running: String(localized: "Running Shortcut")
            case .stopping: String(localized: "Stopping Shortcut…")
            case .stopDelayed: String(localized: "Shortcut Is Still Running")
            case .completed: String(localized: "Shortcut Complete")
            case .stopped: String(localized: "Shortcut Stopped")
            case .endedAfterStop: String(localized: "Shortcut Run Ended")
            case .failed: String(localized: "Shortcut Couldn't Finish")
            }
        }
    }

    let id: UUID
    let shortcut: ShortcutDefinition
    let startedAt: Date
    var processIdentifier: Int32?
    var state: State = .starting
    var stopRequested = false
    var exit: ShortcutExit?
    var message: String?

    var canStop: Bool { state == .running || state == .stopDelayed }
    var spoken: String { "\(shortcut.name), \(state.title)" }

    /// Entirely local presentation data for Settings and the isolated activity bench.
    static func fixture(state: State = .running, ordinal: Int = 0, withOutput: Bool = false) -> ShortcutRun {
        let id = UUID(uuidString: ordinal == 0 ? "00000000-0000-0000-0000-000000000101" : "00000000-0000-0000-0000-000000000102")!
        let definition = ShortcutDefinition(
            id: UUID(uuidString: ordinal == 0 ? "00000000-0000-0000-0000-000000000201" : "00000000-0000-0000-0000-000000000202")!,
            name: ordinal == 0 ? String(localized: "Morning Routine") : String(localized: "Organize Notes"))
        var run = ShortcutRun(id: id, shortcut: definition, startedAt: Date(timeIntervalSince1970: 1_800_000_000), state: state)
        run.stopRequested = [.stopping, .stopDelayed, .stopped, .endedAfterStop].contains(state)
        if !state.active {
            run.exit = ShortcutExit(
                status: state == .completed ? 0 : state == .stopped ? SIGINT : 1,
                reason: state == .stopped ? .signal : .exit,
                output: withOutput ? URL(fileURLWithPath: "/glance-preview/ShortcutResult") : nil)
        }
        if state == .failed { run.message = String(localized: "The shortcut couldn't complete its action.") }
        return run
    }

    mutating func finish(_ exit: ShortcutExit) {
        guard state.active else { return }
        self.exit = exit
        message = exit.message
        if exit.reason == .exit, exit.status == 0 {
            state = .completed
        } else if stopRequested, exit.reason == .signal, exit.status == SIGINT {
            state = .stopped
        } else if stopRequested {
            // The CLI can report an error after Stop was requested. That alone does not prove
            // that a particular workflow action was canceled, or undo actions already completed.
            state = .endedAfterStop
        } else {
            state = .failed
        }
    }
}

struct ShortcutShown: Equatable {
    var run: ShortcutRun
    var additionalRuns = 0
    var status: String { run.state.title }
    var spoken: String { run.spoken }
}

@MainActor
protocol ShortcutRunHandle: AnyObject {
    var processIdentifier: Int32 { get }
    var isRunning: Bool { get }
    /// Only this retained process receives the interrupt; never a name-wide or PID-only kill.
    func requestStop()
}

@MainActor
protocol ShortcutRunning {
    func catalog() async throws -> [ShortcutDefinition]
    func launch(_ shortcut: ShortcutDefinition, completion: @escaping @MainActor (ShortcutExit) -> Void) throws -> any ShortcutRunHandle
}

/// Runs explicitly selected shortcuts through Apple's public CLI. The native Shortcuts activity
/// remains available: this process does not expose its private running-context identifier.
@MainActor
final class ShortcutCLI: ShortcutRunning {
    private final class Handle: ShortcutRunHandle {
        let process: Process
        init(_ process: Process) { self.process = process }
        var processIdentifier: Int32 { process.processIdentifier }
        var isRunning: Bool { process.isRunning }
        func requestStop() { if process.isRunning { process.interrupt() } }
    }

    func catalog() async throws -> [ShortcutDefinition] {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list", "--show-identifiers"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            guard process.terminationReason == .exit, process.terminationStatus == 0,
                data.count <= 2_000_000, let text = String(data: data, encoding: .utf8)
            else { throw ShortcutError.unavailable }
            return try ShortcutDefinition.catalog(text)
        }.value
    }

    func launch(_ shortcut: ShortcutDefinition, completion: @escaping @MainActor (ShortcutExit) -> Void) throws -> any ShortcutRunHandle {
        let storage = try ShortcutRunStorage.create()
        let directory = storage.directory
        let output = storage.output
        let errors = storage.errors
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
            FileManager.default.createFile(atPath: errors.path, contents: nil)
        else { throw ShortcutError.unavailable }
        let out = try FileHandle(forWritingTo: output)
        let err = try FileHandle(forWritingTo: errors)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", shortcut.id.uuidString]
        process.standardInput = FileHandle.nullDevice
        // Preserve actual output bytes without converting their type or evaluating shell text.
        process.standardOutput = out
        process.standardError = err
        process.terminationHandler = { finished in
            try? out.close()
            try? err.close()
            let saved = storage.finish()
            let result = ShortcutExit(
                status: finished.terminationStatus, reason: finished.terminationReason == .exit ? .exit : .signal,
                message: saved.message, output: saved.output, storage: storage)
            Task { @MainActor in completion(result) }
        }
        do { try process.run() } catch {
            process.terminationHandler = nil
            try? out.close()
            try? err.close()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return Handle(process)
    }
}

/// Tracks only runs started from Glance. Concurrent invocations of the same shortcut have distinct
/// identities, handles, exit states, and Stop actions. No percentage or input-wait state is inferred.
@MainActor
final class ShortcutActivity: ObservableObject {
    static let shared = ShortcutActivity(isEnabled: {
        UserDefaults.standard.object(forKey: Preferences.activityShortcuts) as? Bool ?? true
    })
    @Published private(set) var runs: [ShortcutRun] = []
    @Published private(set) var shown: ShortcutShown?
    private let source: any ShortcutRunning
    private let live: Bool
    private let isEnabled: () -> Bool
    private let stopDelay: Duration
    private var settingsObserver: NSObjectProtocol?
    private var benched = false
    private var benchDismissed: () -> Void = {}
    private(set) var benchActions: [String] = []
    private var simulated: Bool { benched || (live && ActivityBench.scene != nil) }
    private var handles: [UUID: any ShortcutRunHandle] = [:]
    private var pendingStops: [UUID: Task<Void, Never>] = [:]
    private var selected: UUID?
    private var catalogCache: [ShortcutDefinition] = []

    init(source: (any ShortcutRunning)? = nil, stopDelay: Duration = .seconds(8), isEnabled: @escaping () -> Bool = { true }) {
        self.source = source ?? ShortcutCLI()
        live = source == nil
        self.stopDelay = stopDelay
        self.isEnabled = isEnabled
    }

    /// Display preferences never launch, cancel or forget an actual shortcut process.
    func start() {
        guard settingsObserver == nil else { return }
        if live, !simulated {
            Task.detached(priority: .utility) { ShortcutRunStorage.cleanupExpired() }
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    func settingsChanged() { publish() }

    func bench(_ runs: [ShortcutRun], selected: UUID? = nil, onDismiss: @escaping () -> Void = {}) {
        guard handles.isEmpty else { return }
        pendingStops.values.forEach { $0.cancel() }
        pendingStops = [:]
        benched = true
        benchActions = []
        benchDismissed = onDismiss
        self.runs = runs
        self.selected = selected ?? runs.first?.id
        publish()
    }

    @discardableResult
    func run(_ shortcut: ShortcutDefinition) -> UUID {
        let id = UUID()
        runs.append(.init(id: id, shortcut: shortcut, startedAt: .now))
        selected = id
        if simulated {
            runs[runs.count - 1].state = .running
            benchActions.append("run:\(id.uuidString)")
            publish()
            return id
        }
        publish()
        do {
            let handle = try source.launch(shortcut) { [weak self] exit in self?.finished(id, exit: exit) }
            if let index = runs.firstIndex(where: { $0.id == id }), runs[index].state == .starting {
                handles[id] = handle
                runs[index].processIdentifier = handle.processIdentifier
                runs[index].state = .running
            }
        } catch {
            if let index = runs.firstIndex(where: { $0.id == id }) {
                runs[index].state = .failed
                runs[index].message = error.localizedDescription
            }
        }
        publish()
        return id
    }

    func stop(_ id: UUID) {
        guard let index = runs.firstIndex(where: { $0.id == id }), runs[index].canStop else { return }
        if simulated {
            runs[index].stopRequested = true
            runs[index].finish(.init(status: SIGINT, reason: .signal))
            benchActions.append("stop:\(id.uuidString)")
            publish()
            return
        }
        guard let handle = handles[id], handle.isRunning else { return }
        runs[index].stopRequested = true
        runs[index].state = .stopping
        publish()
        handle.requestStop()
        guard runs.first(where: { $0.id == id })?.state == .stopping else { return }
        pendingStops[id]?.cancel()
        pendingStops[id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: stopDelay)
            guard !Task.isCancelled, handles[id]?.isRunning == true,
                let index = runs.firstIndex(where: { $0.id == id }), runs[index].state == .stopping
            else { return }
            runs[index].state = .stopDelayed
            publish()
        }
    }

    func select(_ id: UUID) {
        guard runs.contains(where: { $0.id == id }) else { return }
        selected = id
        publish()
    }

    /// A running shortcut cannot be discarded while its process is still tracked.
    func dismiss(_ id: UUID) {
        guard let run = runs.first(where: { $0.id == id }), !run.state.active else { return }
        if !simulated { run.exit?.storage?.discardEmptyResult() }
        runs.removeAll { $0.id == id }
        pendingStops.removeValue(forKey: id)?.cancel()
        if selected == id { selected = nil }
        publish()
        if benched, runs.isEmpty { benchDismissed() }
    }

    func openShortcuts() {
        if simulated {
            benchActions.append("openShortcuts")
            return
        }
        if !NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")),
            let index = runs.firstIndex(where: { $0.id == selected })
        {
            runs[index].message = String(localized: "Couldn't Open Shortcuts")
            publish()
        }
    }

    func showResult(_ id: UUID) {
        guard let index = runs.firstIndex(where: { $0.id == id }), let url = runs[index].exit?.output else { return }
        if simulated {
            benchActions.append("showResult:\(id.uuidString)")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            runs[index].exit?.output = nil
            runs[index].message = String(localized: "The shortcut's result is no longer available.")
            publish()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func loadCatalog() async throws -> [ShortcutDefinition] {
        if simulated {
            var seen: Set<UUID> = []
            return runs.map(\.shortcut).filter { seen.insert($0.id).inserted }
        }
        let entries = try await source.catalog()
        catalogCache = entries
        return entries
    }

    /// Supply this submenu to an ordinary NSMenuItem. Selecting a catalog item launches it;
    /// selecting an existing run only selects that exact run and calls the host's opening action.
    func makeRunMenu(canRun: @escaping () -> Bool = { true }, open: @escaping (UUID) -> Void = { _ in }) -> NSMenu {
        ShortcutRunMenu(
            activity: self, cached: catalogCache,
            canRun: { [weak self] in
                self?.isEnabled() == true && canRun()
            }, open: open)
    }

    private func finished(_ id: UUID, exit: ShortcutExit) {
        guard let index = runs.firstIndex(where: { $0.id == id }), runs[index].state.active else { return }
        runs[index].finish(exit)
        handles.removeValue(forKey: id)
        pendingStops.removeValue(forKey: id)?.cancel()
        publish()
    }

    private func publish() {
        guard benched || isEnabled() else {
            shown = nil
            return
        }
        let run =
            selected.flatMap { id in runs.first { $0.id == id } }
            ?? runs.first(where: { $0.state.active }) ?? runs.last
        selected = run?.id
        shown = run.map { ShortcutShown(run: $0, additionalRuns: max(0, runs.count - 1)) }
    }
}

@MainActor
private final class ShortcutRunMenu: NSMenu, NSMenuDelegate {
    private weak var activity: ShortcutActivity?
    private var entries: [ShortcutDefinition]
    private let open: (UUID) -> Void
    private let canRun: () -> Bool
    private var loading: Task<Void, Never>?

    init(activity: ShortcutActivity, cached: [ShortcutDefinition], canRun: @escaping () -> Bool, open: @escaping (UUID) -> Void) {
        self.activity = activity
        entries = cached
        self.open = open
        self.canRun = canRun
        super.init(title: String(localized: "Run Shortcut"))
        autoenablesItems = false
        delegate = self
        populate(loading: true)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func menuWillOpen(_ menu: NSMenu) {
        loading?.cancel()
        populate(loading: true)
        loading = Task { [weak self] in
            guard let self, let activity else { return }
            do {
                let entries = try await activity.loadCatalog()
                guard !Task.isCancelled else { return }
                self.entries = entries
                populate(loading: false)
            } catch {
                guard !Task.isCancelled else { return }
                populate(loading: false, failed: true)
            }
        }
    }
    func menuDidClose(_ menu: NSMenu) {
        loading?.cancel()
        loading = nil
    }

    private func populate(loading: Bool, failed: Bool = false) {
        removeAllItems()
        if let runs = activity?.runs, !runs.isEmpty {
            disabled(String(localized: "Runs Started in Glance"))
            for run in runs {
                let item = NSMenuItem(title: "\(run.shortcut.name) — \(run.state.title)", action: nil, keyEquivalent: "")
                item.representedObject = run.id
                let controls = NSMenu(title: run.shortcut.name)
                controls.autoenablesItems = false
                func command(_ title: String, _ action: Selector, id: String, enabled: Bool = true) {
                    let command = NSMenuItem(title: title, action: action, keyEquivalent: "")
                    command.target = self
                    command.representedObject = run.id
                    command.identifier = NSUserInterfaceItemIdentifier(id)
                    command.isEnabled = enabled
                    controls.addItem(command)
                }
                command(String(localized: "Show Activity"), #selector(selectRun(_:)), id: "show-shortcut-activity", enabled: canRun())
                if run.exit?.output != nil {
                    command(String(localized: "Show Result"), #selector(showResult(_:)), id: "show-shortcut-result")
                }
                if run.state.active {
                    let title = run.state == .stopDelayed ? String(localized: "Try Stopping Again") : String(localized: "Stop")
                    command(title, #selector(stopRun(_:)), id: "stop-shortcut", enabled: run.canStop)
                } else {
                    command(String(localized: "Done"), #selector(dismissRun(_:)), id: "dismiss-shortcut")
                }
                item.submenu = controls
                addItem(item)
            }
            addItem(.separator())
        }
        if failed {
            disabled(String(localized: "Couldn't Load Shortcuts"))
        } else if entries.isEmpty {
            disabled(loading ? String(localized: "Loading Shortcuts…") : String(localized: "No Shortcuts"))
        } else {
            for entry in entries {
                let item = NSMenuItem(title: entry.name, action: #selector(runShortcut(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry
                item.isEnabled = canRun()
                addItem(item)
            }
        }
        addItem(.separator())
        let editor = NSMenuItem(title: String(localized: "Open Shortcuts"), action: #selector(openEditor), keyEquivalent: "")
        editor.target = self
        addItem(editor)
        update()
    }

    private func disabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
    @objc private func selectRun(_ item: NSMenuItem) {
        guard canRun(), let id = item.representedObject as? UUID, let activity else { return }
        activity.select(id)
        open(id)
    }
    @objc private func stopRun(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        activity?.stop(id)
    }
    @objc private func dismissRun(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        activity?.dismiss(id)
    }
    @objc private func showResult(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        activity?.showResult(id)
    }
    @objc private func runShortcut(_ item: NSMenuItem) {
        guard canRun(), let shortcut = item.representedObject as? ShortcutDefinition, let activity else { return }
        open(activity.run(shortcut))
    }
    @objc private func openEditor() { activity?.openShortcuts() }
}
