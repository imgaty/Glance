//
//  CallPhotos.swift
//  Glance
//
//  Created by Gaty on 06/11/2026.
//

import AppKit
import Contacts

/// A caller's picture, small, to tell contacts apart by: the colors of a grid over the middle of
/// their circle, leaving out its lower right, where macOS's popup puts a phone's badge.
enum CallFace {
    /// Where the caller's picture is in macOS's popup, as shares of it from its top left, measured on
    /// a real call: a circle 69 pixels across in a 756 by 272 picture.
    static let inPopup = CGRect(x: 0.0800, y: 0.1654, width: 0.0913, height: 0.2537)
    static let grid = 6
    /// How much of the circle's width the grid covers, around its middle: the square inside it.
    static let middle: CGFloat = 0.7

    /// Whether a cell counts: the badge covers the lower right, two columns by three rows.
    static func counts(column: Int, row: Int) -> Bool { !(column >= grid - 2 && row >= grid - 3) }

    /// The average color of each cell that counts, red, green and blue, among 8-bit pixels with four
    /// channels each, red first, the top row first. `circle` is in pixels.
    nonisolated static func cells(pixels: UnsafeBufferPointer<UInt8>, width: Int, height: Int, rowBytes: Int, circle: CGRect) -> [UInt8] {
        let side = circle.width * middle
        let origin = CGPoint(x: circle.midX - side / 2, y: circle.midY - side / 2)
        let cell = side / CGFloat(grid)
        var found: [UInt8] = []
        for row in 0..<grid {
            for column in 0..<grid where counts(column: column, row: row) {
                var sum = (0, 0, 0, 0)
                let x0 = Int(origin.x + CGFloat(column) * cell), x1 = Int(origin.x + CGFloat(column + 1) * cell)
                let y0 = Int(origin.y + CGFloat(row) * cell), y1 = Int(origin.y + CGFloat(row + 1) * cell)
                for y in max(y0, 0)..<min(max(y1, y0 + 1), height) {
                    for x in max(x0, 0)..<min(max(x1, x0 + 1), width) {
                        let at = y * rowBytes + x * 4
                        sum = (sum.0 + Int(pixels[at]), sum.1 + Int(pixels[at + 1]), sum.2 + Int(pixels[at + 2]), sum.3 + 1)
                    }
                }
                let count = max(sum.3, 1)
                found += [UInt8(sum.0 / count), UInt8(sum.1 / count), UInt8(sum.2 / count)]
            }
        }
        return found
    }

    /// A contact's photo as the popup shows it, filling the circle: the cells of its middle.
    nonisolated static func cells(of image: CGImage) -> [UInt8]? {
        let side = 96
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // Filling the square, cropped to its middle if it isn't one.
            let scale = CGFloat(side) / CGFloat(min(image.width, image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.draw(image, in: CGRect(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2, width: size.width, height: size.height))
            return true
        }
        guard drawn else { return nil }
        return pixels.withUnsafeBufferPointer {
            cells(pixels: $0, width: side, height: side, rowBytes: side * 4, circle: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    /// How alike two pictures are, from -1 to 1: how their colors rise and fall together, which a
    /// popup's dimming or a brighter screen doesn't change.
    nonisolated static func likeness(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        let x = a.map(Double.init), y = b.map(Double.init)
        let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in x.indices {
            sxy += (x[i] - mx) * (y[i] - my)
            sxx += (x[i] - mx) * (x[i] - mx)
            syy += (y[i] - my) * (y[i] - my)
        }
        guard sxx > 0, syy > 0 else { return 0 }
        return sxy / (sxx * syy).squareRoot()
    }

    /// Which of several contacts' photos the popup shows: the one it's most like, if that's like it
    /// and clearly more than any other. None when it shows an initial, which no photo is like.
    nonisolated static func pick(_ face: [UInt8], among photos: [[UInt8]?]) -> Int? {
        let scored = photos.enumerated().compactMap { index, photo in photo.map { (index, likeness(face, $0)) } }.sorted { $0.1 > $1.1 }
        guard let best = scored.first, best.1 >= 0.85 else { return nil }
        if let second = scored.dropFirst().first, second.1 > best.1 - 0.1 { return nil }
        return best.0
    }
}

/// A FaceTime or Phone caller's photo, from Contacts: found by the name macOS's popup shows, or the
/// number when it shows one. When two contacts have that name, the popup's own picture of the caller
/// says which. Contacts is asked for the first time a FaceTime or Phone call shows; without it, or
/// without a photo, the caller has an initial.
@MainActor
final class CallPhotos: ObservableObject {
    static let shared = CallPhotos(book: ActivityBench.scene == nil ? .contacts : .empty)

    /// A contact found for the caller, with their photo, if they have one.
    struct Card: Sendable {
        var photo: Data?
    }

    /// Where contacts come from: Contacts itself, or, at the bench and in tests, made up.
    struct Book: Sendable {
        /// Whether Contacts may be read, or nil until it's been asked.
        var allowed: @MainActor @Sendable () -> Bool?
        var ask: @Sendable () async -> Bool
        /// The contacts with exactly this name, or this number.
        var cards: @Sendable (_ name: String, _ isNumber: Bool) -> [Card]

        static let empty = Book(allowed: { false }, ask: { false }, cards: { _, _ in [] })

        static let contacts = Book(
            allowed: {
                switch CNContactStore.authorizationStatus(for: .contacts) {
                case .authorized: true
                case .notDetermined: nil
                default: false
                }
            },
            ask: { (try? await CNContactStore().requestAccess(for: .contacts)) ?? false },
            cards: { name, isNumber in
                let keys: [CNKeyDescriptor] = [
                    CNContactFormatter.descriptorForRequiredKeys(for: .fullName), CNContactNicknameKey as CNKeyDescriptor,
                    CNContactOrganizationNameKey as CNKeyDescriptor, CNContactThumbnailImageDataKey as CNKeyDescriptor,
                ]
                let predicate =
                    isNumber
                    ? CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: name)) : CNContact.predicateForContacts(matchingName: name)
                let found = (try? CNContactStore().unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
                // Contacts finds anyone with any of the words; the popup shows a whole name.
                let wanted = found.filter { contact in
                    isNumber
                        || CallPhotos.same(CNContactFormatter.string(from: contact, style: .fullName), name)
                        || CallPhotos.same(contact.nickname, name) || CallPhotos.same(contact.organizationName, name)
                }
                return wanted.map { Card(photo: $0.thumbnailImageData) }
            })
    }

    /// Contacts, or made up, in tests.
    var book: Book
    /// The caller looked up, and what was found, each photo with its cells.
    private var name: String?
    private var found: [(image: NSImage, cells: [UInt8]?)?]?
    private var looking = false
    @Published private(set) var photo: NSImage?

    init(book: Book) {
        self.book = book
    }

    /// The same name, as macOS writes it and as it was read, whatever the case and accents.
    nonisolated static func same(_ a: String?, _ b: String) -> Bool {
        guard let a, !a.isEmpty else { return false }
        return a.trimmingCharacters(in: .whitespaces).compare(b.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive])
            == .orderedSame
    }

    /// A number, rather than a name.
    nonisolated static func isNumber(_ name: String) -> Bool {
        let digits = name.filter(\.isNumber).count
        return digits >= 3 && name.allSatisfy { $0.isNumber || " +-().".contains($0) }
    }

    /// The photo for this call, if it's the caller looked up.
    func photo(for call: CallShown) -> NSImage? {
        call.name == name ? photo : nil
    }

    /// Looks the caller up, once a name, asking for Contacts the first time; `face` is the popup's
    /// picture of them, to choose between contacts with the same name.
    func look(for call: CallShown, face: [UInt8]?) {
        guard call.throughApple, !call.name.isEmpty else { return }
        if call.name != name {
            name = call.name
            found = nil
            photo = nil
            looking = false
        }
        if let found { return choose(from: found, face: face) }
        guard !looking else { return }
        looking = true
        let wanted = call.name
        let book = book
        Task {
            var allowed = book.allowed()
            if allowed == nil { allowed = await book.ask() }
            guard allowed == true else { return }
            let cards = await Task.detached(priority: .utility) { book.cards(wanted, CallPhotos.isNumber(wanted)) }.value
            guard wanted == self.name else { return }
            let made: [(image: NSImage, cells: [UInt8]?)?] = cards.map { card in
                guard let data = card.photo, let image = NSImage(data: data) else { return nil }
                let cells = image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(CallFace.cells(of:))
                return (image, cells)
            }
            self.found = made
            self.looking = false
            self.choose(from: made, face: face)
        }
    }

    /// One contact: their photo, if any. More: the one the popup's picture shows.
    private func choose(from cards: [(image: NSImage, cells: [UInt8]?)?], face: [UInt8]?) {
        let chosen: NSImage?
        if cards.count == 1 {
            chosen = cards[0]?.image
        } else if cards.count > 1, let face, let index = CallFace.pick(face, among: cards.map { $0?.cells }) {
            chosen = cards[index]?.image
        } else {
            chosen = nil
        }
        if chosen !== photo { photo = chosen }
    }

    /// The call's over.
    func forget() {
        name = nil
        found = nil
        photo = nil
        looking = false
    }
}
