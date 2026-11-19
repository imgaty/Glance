import AppKit
import Darwin
import ObjectiveC
import Testing

@testable import Glance

/// An AirDrop asking to be accepted, answered from the notch as macOS's own Accept and Decline do.
@Suite("AirDrop requests")
@MainActor
struct AirDropAnswerTests {
    @Test("Accept saves to Downloads when that's offered, else takes the first action that doesn't decline")
    func acceptAction() {
        let save = AirDropAnswer.saveToDownloads, cancel = AirDropAnswer.cancel
        #expect(AirDropAnswer.acceptAction(among: ["SDOpenActionIdentifier", save, cancel], declining: cancel) == 1)
        #expect(AirDropAnswer.acceptAction(among: [cancel, "SDOpenActionIdentifier"], declining: cancel) == 1)
        #expect(AirDropAnswer.acceptAction(among: ["decline-here", "SDAddToPhotoLibraryActionIdentifier"], declining: "decline-here") == 1)
        #expect(AirDropAnswer.acceptAction(among: [cancel], declining: nil) == nil)
        #expect(AirDropAnswer.acceptAction(among: [], declining: cancel) == nil)
    }

    @Test("macOS's buttons are known by their own words, in English too")
    func buttonWords() {
        let accept = AirDropAnswer.titles(.accept), decline = AirDropAnswer.titles(.decline)
        #expect(accept.contains("Accept"))
        #expect(decline.contains("Decline"))
        #expect(accept.isDisjoint(with: decline))
        #expect(AirDropAnswer.isButton(labels: ["", " Accept "], named: accept))
        #expect(!AirDropAnswer.isButton(labels: ["Accept and Open"], named: accept))
        #expect(!AirDropAnswer.isButton(labels: ["Decline"], named: accept))
    }

    @Test("An action macOS gave no handler isn't run: its triggerAction would crash")
    func noHandlerNoTrigger() throws {
        guard dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY) != nil,
            let type = NSClassFromString("SFAirDropAction") as? NSObject.Type
        else { return }
        let selector = NSSelectorFromString("initWithTransferIdentifier:actionIdentifier:title:singleItemTitle:type:")
        typealias Make = @convention(c) (AnyObject, Selector, NSString, NSString, NSString, NSString, Int) -> Unmanaged<NSObject>?
        let make = unsafeBitCast(class_getMethodImplementation(type, selector), to: Make.self)
        let allocated = try #require(type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue())
        let action = try #require(make(allocated, selector, "glance-test", AirDropAnswer.cancel as NSString, "Decline", "Decline", 0)?.takeRetainedValue())
        #expect(!AirDropAnswer.trigger(action))
        #expect(!AirDropAnswer.trigger(NSObject()))
    }

    @Test("A request isn't done and has no Stop; it opens wider, for Decline and Accept")
    func asking() {
        let request = AirDropShown(id: "1", sender: "iPhone", fraction: 1, canStop: true, asking: true)
        #expect(!request.done)
        #expect(!request.offersStop)
        let h: CGFloat = 32, camera: CGFloat = 185
        let wide = AirDropLayout.width(restingHeight: h, camera: camera, asking: true)
        let narrow = AirDropLayout.width(restingHeight: h, camera: camera)
        // Both buttons fit beside the camera, as far in from the end as the ring is.
        #expect(wide >= camera + 2 * (LiveActivityView.cameraGap + AirDropLayout.trailing(h, asking: true) + AirDropLayout.ringEdge(h)))
        #expect(wide > narrow)
        // Who it's from keeps at least the room it has on a transfer.
        #expect(AirDropLayout.wordsRoom(h, width: wide, asking: true) >= AirDropLayout.wordsRoom(h, width: narrow) - 1)
        #expect(ExpandedAirDropView.spoken(request) == String(localized: "AirDrop from \("iPhone"), waiting for an answer"))
    }

    @Test("Decline and Accept answer only while the notch is open to the request")
    func answersWhenRevealed() {
        var answers: [AirDropAnswer.Choice] = []
        let request = AirDropShown(id: "1", sender: "iPhone", fraction: 0, canStop: false, asking: true)
        let open = ExpandedAirDropView(shown: request, restingHeight: 32, width: 400, answer: { answers.append($0) })
        open.perform(.decline)
        open.perform(.accept)
        ExpandedAirDropView(shown: request, restingHeight: 32, width: 400, revealed: false, answer: { answers.append($0) }).perform(.accept)
        var coming = request
        coming.asking = false
        ExpandedAirDropView(shown: coming, restingHeight: 32, width: 400, answer: { answers.append($0) }).perform(.accept)
        #expect(answers == [.decline, .accept])
    }
}
