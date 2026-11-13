//
//  AirDropSending.swift
//  Glance
//
//  Created by Gaty on 31/10/2026.
//

import AppKit
import ApplicationServices
import QuickLookThumbnailing

/// A file going out over AirDrop, shown as one coming in is. macOS tells other apps nothing of what
/// it sends, but the service sending it runs as the user and reads the file from start to end, so
/// how far it has read is how far along it is, from when the other side accepts it. Who it's going
/// to is only in macOS's AirDrop window, through Accessibility, while that's open. Nothing's looked at
/// until AirDrop's own network is busy, which is checked once a second.
@MainActor
final class AirDropSendWatch {
    /// Told what's going out, and nil once nothing is.
    var changed: (AirDropShown?) -> Void = { _ in }

    /// A file the service has open to read: which, how far in, and how long.
    struct OpenFile: Equatable {
        var descriptor: Int32
        var path: String
        var offset: Int64
        var size: Int64
    }

    private var shown: AirDropShown? {
        didSet { changed(shown) }
    }
    /// The file being sent.
    private var sending: OpenFile?
    private var before: [OpenFile] = []
    private var bytesOut: UInt64?
    private var timer: Timer?
    private var quick = false
    private var clearing: Task<Void, Never>?
    /// The device in macOS's window, which stops it.
    private var device: AXUIElement?
    private var askedForDevice = Date.distantPast
    private var findingDevice = false
    private var service: pid_t?

    func start() {
        guard timer == nil, !ActivityBench.fakes else { return }
        pace(quick: false)
    }

    /// Once a second while AirDrop's quiet; a few times a second while it's busy.
    private func pace(quick: Bool) {
        guard timer == nil || quick != self.quick else { return }
        timer?.invalidate()
        self.quick = quick
        let timer = Timer(timeInterval: quick ? 0.25 : 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        timer.tolerance = quick ? 0.05 : 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard UserDefaults.standard.bool(forKey: Preferences.activityAirDrop) else { return }
        let out = Self.bytesOut(of: "awdl0")
        let busy = out.flatMap { now in bytesOut.map { now > $0 + Self.busyBytes } } ?? false
        bytesOut = out
        guard busy || sending != nil else {
            before = []
            return pace(quick: false)
        }
        pace(quick: true)
        guard let service = service.flatMap({ kill($0, 0) == 0 ? $0 : nil }) ?? Self.sharingService() else { return }
        self.service = service
        let files = Self.openFiles(of: service)
        defer { before = files }
        if let sending {
            guard let file = files.first(where: { $0.descriptor == sending.descriptor && $0.path == sending.path }) else { return finished() }
            self.sending = file
            let fraction = Self.fraction(of: file)
            if let shown, fraction > shown.fraction { self.shown?.fraction = fraction }
            findDevice()
        } else if let file = Self.sent(in: files, before: before) {
            begin(file)
        }
    }

    /// A moment's chatter stays under this, in the second or quarter of one between looks.
    private static let busyBytes: UInt64 = 32 * 1024

    private func begin(_ file: OpenFile) {
        clearing?.cancel()
        sending = file
        device = nil
        askedForDevice = .distantPast
        let url = URL(fileURLWithPath: file.path)
        let id = UUID().uuidString
        shown = AirDropShown(
            id: id, sender: "", preview: NSWorkspace.shared.icon(forFile: file.path), fraction: Self.fraction(of: file), sending: true,
            file: url.lastPathComponent, canStop: false)
        findDevice()
        Task { [weak self] in
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: .all)
            guard let picture = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage,
                let self, self.shown?.id == id
            else { return }
            self.shown?.preview = picture
        }
    }

    /// Read to the end, it shows a moment full, as one coming in does; stopped short, it just goes.
    private func finished() {
        sending = nil
        device = nil
        guard let shown, shown.fraction > 0.97 else {
            self.shown = nil
            return
        }
        self.shown?.fraction = 1
        self.shown?.canStop = false
        clearing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.shown = nil
        }
    }

    /// Stops it, as pressing the device in macOS's window does.
    func stop() {
        guard shown?.offersStop == true, let device else { return }
        guard Self.canStop(device), AXUIElementPerformAction(device, kAXPressAction as CFString) == .success else {
            self.device = nil
            shown?.canStop = false
            return
        }
        shown?.canStop = false
    }

    /// Rechecked while sending: a named recipient can outlive its window and its stop action.
    private func findDevice() {
        guard !findingDevice, Date.now.timeIntervalSince(askedForDevice) > 1 else { return }
        askedForDevice = .now
        findingDevice = true
        var apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").map(\.processIdentifier)
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier { apps.append(front) }
        apps.append(ProcessInfo.processInfo.processIdentifier)
        let id = shown?.id
        let recipient = shown?.recipient
        Task.detached(priority: .userInitiated) { [weak self, apps] in
            let found = Self.device(in: Array(Set(apps)), named: recipient)
            nonisolated(unsafe) let button = found?.button
            let name = found?.name
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.findingDevice = false
                guard self.shown?.id == id else { return }
                self.device = button
                self.shown?.canStop = button != nil
                if let name { self.shown?.recipient = name }
            }
        }
    }

    // MARK: Reading

    nonisolated static func fraction(of file: OpenFile) -> Double {
        file.size > 0 ? min(max(Double(file.offset) / Double(file.size), 0), 1) : 0
    }

    /// What's being sent: a file read further than it was a moment ago, outside macOS's own.
    nonisolated static func sent(in files: [OpenFile], before: [OpenFile]) -> OpenFile? {
        files.first { file in
            !["/System/", "/usr/", "/Library/"].contains { file.path.hasPrefix($0) }
                && before.contains { $0.descriptor == file.descriptor && $0.path == file.path && $0.offset < file.offset }
        }
    }

    /// The service that does the sending, among the user's own.
    nonisolated private static func sharingService() -> pid_t? {
        var ids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), &ids, Int32(ids.count * MemoryLayout<pid_t>.stride))
        for id in ids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride) where id > 0 {
            var name = [CChar](repeating: 0, count: 64)
            if proc_name(id, &name, UInt32(name.count)) > 0, String(cString: name) == "sharingd" { return id }
        }
        return nil
    }

    /// Plain files it has open to read and not to write.
    nonisolated private static func openFiles(of service: pid_t) -> [OpenFile] {
        let size = proc_pidinfo(service, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.stride)
        let used = proc_pidinfo(service, PROC_PIDLISTFDS, 0, &descriptors, size)
        var files: [OpenFile] = []
        for descriptor in descriptors.prefix(Int(used) / MemoryLayout<proc_fdinfo>.stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            guard proc_pidfdinfo(service, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, Int32(MemoryLayout<vnode_fdinfowithpath>.size)) > 0
            else { continue }
            // FREAD and FWRITE.
            guard info.pfi.fi_openflags & 1 != 0, info.pfi.fi_openflags & 2 == 0, info.pvip.vip_vi.vi_stat.vst_mode & S_IFMT == S_IFREG else { continue }
            let path = withUnsafeBytes(of: info.pvip.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            files.append(OpenFile(descriptor: descriptor.proc_fd, path: path, offset: info.pfi.fi_offset, size: info.pvip.vip_vi.vi_stat.vst_size))
        }
        return files
    }

    /// How much has gone out through a network interface.
    nonisolated private static func bytesOut(of interface: String) -> UInt64? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var node = list
        while let current = node {
            if String(cString: current.pointee.ifa_name) == interface, current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            {
                return UInt64(data.pointee.ifi_obytes)
            }
            node = current.pointee.ifa_next
        }
        return nil
    }

    /// A recipient saying Sending, rather than Waiting or Sent, with an enabled press action.
    nonisolated private static func canStop(_ device: AXUIElement) -> Bool {
        guard SystemNotices.value(device, kAXEnabledAttribute) as? Bool == true,
            let said = SystemNotices.value(device, kAXDescriptionAttribute) as? String
        else { return false }
        let bundle = Bundle(path: "/System/Library/PrivateFrameworks/DeviceDiscoveryUI.framework")
        let sending = bundle?.localizedString(forKey: "SENDING", value: "Sending", table: "Localizable") ?? "Sending"
        guard said.hasSuffix(sending) else { return false }
        var actions: CFArray?
        guard AXUIElementCopyActionNames(device, &actions) == .success else { return false }
        return (actions as? [String])?.contains(kAXPressAction as String) == true
    }

    /// Only one matching recipient can safely supply the cancellation action. Several sends are
    /// otherwise indistinguishable from file reads, so an arbitrary recipient must not be stopped.
    nonisolated private static func device(in apps: [pid_t], named recipient: String?) -> (name: String, button: AXUIElement)? {
        guard AXIsProcessTrusted() else { return nil }
        var found: [(name: String, button: AXUIElement)] = []
        for pid in apps {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.3)
            for window in SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
            where (SystemNotices.value(window, kAXTitleAttribute) as? String)?.contains("AirDrop") == true {
                let devices = SystemNotices.findAll(in: window) { SystemNotices.value($0, "AXIdentifier") as? String == "dd.nodeBody" }
                for device in devices {
                    guard let name = SystemNotices.value(device, kAXHelpAttribute) as? String,
                        recipient == nil || name == recipient, Self.canStop(device)
                    else { continue }
                    if !found.contains(where: { CFEqual($0.button, device) }) { found.append((name, device)) }
                }
            }
        }
        return found.count == 1 ? found.first : nil
    }
}
