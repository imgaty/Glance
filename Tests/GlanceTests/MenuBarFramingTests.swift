import Foundation
import Testing

@testable import Glance

@Suite("Menu bar preview framing")
struct MenuBarFramingTests {
    @Test("A collapsing picture has no room for menu items", arguments: [-1.0, 0, 1, 3, 3.999])
    func narrow(_ shown: Double) {
        #expect(MenuBarFraming.inside(width: 1512, shown: shown) == nil)
    }

    @Test("Normal pictures retain their inset and zero-width interiors are valid")
    func margins() {
        #expect(MenuBarFraming.inside(width: 1512, shown: 600) == 458...1054)
        #expect(MenuBarFraming.inside(width: 1512, shown: 4) == 756...756)
        #expect(MenuBarFraming.inside(width: 1512, shown: 2000) == 2...1510)
        #expect(MenuBarFraming.inside(width: 0, shown: 600) == nil)
    }

    @Test("Nonfinite geometry cannot construct a range")
    func nonfinite() {
        #expect(MenuBarFraming.inside(width: .infinity, shown: 600) == nil)
        #expect(MenuBarFraming.inside(width: 1512, shown: .nan) == nil)
    }
}
