import Carbon.HIToolbox
import Testing

@testable import Glance

@MainActor
@Suite("Activity key routing")
struct ActivityKeyRoutingTests {
    @Test("A disappearing action cannot receive Return or Space", arguments: [kVK_Return, kVK_Space])
    func unavailableAction(_ key: Int) {
        let keys = PlayerKeys()
        keys.focus(on: .activityFirst)
        let presses = keys.presses
        #expect(keys.typed(key: key, shift: false, hasMedia: true, activity: []) == .none)
        #expect(keys.focus == nil)
        #expect(keys.presses == presses)
    }

    @Test("A changed activity clears the old control before activation")
    func differentActivity() {
        let keys = PlayerKeys()
        keys.focus(on: .activityFourth)
        #expect(keys.typed(key: kVK_Return, shift: false, hasMedia: true, activity: [.activitySecond]) == .none)
        #expect(keys.focus == nil)
        #expect(keys.typed(key: kVK_Tab, shift: false, hasMedia: true, activity: [.activitySecond]) == .moved)
        #expect(keys.focus == .activitySecond)
        #expect(keys.typed(key: kVK_Return, shift: false, hasMedia: true, activity: [.activitySecond]) == .pressed)
    }
}
