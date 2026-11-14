import Testing

@testable import Glance

@Suite("Verified Focus announcements")
struct FocusActivityTests {
    private let english = FocusStateWords(on: "On", off: "Off")

    private func snapshot(
        identifier: String? = FocusBannerSnapshot.identifier,
        texts: [String] = ["Work", "On"], symbol: String? = "person.lanyardcard.fill", description: String? = "Work"
    ) -> FocusBannerSnapshot {
        FocusBannerSnapshot(identifier: identifier, texts: texts, images: [.init(symbol: symbol, description: description)])
    }

    @Test("A complete native banner preserves the mode, symbol, and actual state word")
    func recognizedChange() throws {
        let change = try #require(FocusChange.read(snapshot(), words: english, symbolExists: { $0 == "person.lanyardcard.fill" }))
        #expect(change.name == "Work")
        #expect(change.symbol == "person.lanyardcard.fill")
        #expect(change.state == .on)
        #expect(change.text == "Work · On")
        #expect(change.spoken == "Work, On")
        let off = try #require(FocusChange.read(snapshot(texts: ["Work", "Off"]), words: english, symbolExists: { _ in true }))
        #expect(off.state == .off)
    }

    @Test("State parsing uses the native language, with no English or false-Off fallback")
    func localizedState() throws {
        let portuguese = try #require(FocusStateWords(on: "Ativado", off: "Desativado"))
        let change = try #require(FocusChange.read(snapshot(texts: ["Trabalho", "Desativado"], description: "Trabalho"), words: portuguese, symbolExists: { _ in true }))
        #expect(change.state == .off)
        #expect(change.stateText == "Desativado")
        #expect(FocusChange.read(snapshot(), words: portuguese, symbolExists: { _ in true }) == nil)
        #expect(FocusChange.read(snapshot(texts: ["Work", "Unavailable"]), words: english, symbolExists: { _ in true }) == nil)
        #expect(FocusChange.read(snapshot(), words: nil, symbolExists: { _ in true }) == nil)
    }

    @Test("Unresolved or ambiguous localized words cannot become known Focus state")
    func unknownLocalization() {
        #expect(FocusStateWords(on: "FOCUS_MODE_ON", off: "FOCUS_MODE_OFF") == nil)
        #expect(FocusStateWords(on: "", off: "Off") == nil)
        #expect(FocusStateWords(on: "On", off: "On") == nil)
    }

    @Test("Partial, ambiguous, unrelated, and unsupported banners remain native")
    func rejectsUnknownBanners() {
        let invalid = [
            snapshot(identifier: "volume-system-banner"),
            snapshot(identifier: nil),
            snapshot(texts: []),
            snapshot(texts: ["Work"]),
            snapshot(texts: ["Work", "On", "Until tonight"]),
            snapshot(texts: ["", "On"], description: ""),
            snapshot(description: nil),
            snapshot(description: "Personal"),
            snapshot(symbol: nil),
            snapshot(symbol: ""),
            FocusBannerSnapshot(identifier: FocusBannerSnapshot.identifier, texts: ["Work", "On"], images: []),
            FocusBannerSnapshot(
                identifier: FocusBannerSnapshot.identifier, texts: ["Work", "On"],
                images: [
                    .init(symbol: "person.fill", description: "Work"), .init(symbol: "moon.fill", description: "Work"),
                ]),
        ]
        for banner in invalid {
            #expect(FocusChange.read(banner, words: english, symbolExists: { _ in true }) == nil)
        }
        #expect(FocusChange.read(snapshot(symbol: "_private_focus_symbol"), words: english, symbolExists: { _ in false }) == nil)
    }

    @Test("Startup is quiet and repeated creation notifications deliver one event per window")
    func deduplicatesWindowEvents() {
        var ledger = FocusBannerLedger<Int>()
        ledger.prime([1])
        #expect(ledger.newlyCreated(active: [1], candidates: [1]).isEmpty)
        #expect(ledger.newlyCreated(active: [1, 2], candidates: [2, 2]) == [2])
        #expect(ledger.newlyCreated(active: [1, 2], candidates: [2]).isEmpty)
        // The same mode and state may legitimately be announced in a later native window.
        #expect(ledger.newlyCreated(active: [3], candidates: [3]) == [3])
    }

    @Test("Transient AX failure or incomplete window identifiers cannot replay old news")
    func preservesBaselineAcrossPartialReads() {
        var ledger = FocusBannerLedger<Int>()
        ledger.prime([1])
        #expect(ledger.newlyCreated(active: nil, candidates: []).isEmpty)
        #expect(ledger.newlyCreated(active: [1], candidates: [1]).isEmpty)
        // A new window's identifier can arrive after its initial creation notification.
        #expect(ledger.newlyCreated(active: [1, 2], candidates: []).isEmpty)
        #expect(ledger.newlyCreated(active: [1, 2], candidates: [2]) == [2])
        #expect(ledger.newlyCreated(active: [1, 2], candidates: [99]).isEmpty)
    }
}
