//
//  OpenedRowTests.swift
//  GlanceTests
//
//  Created by Gaty on 26/11/2026.
//

import AppKit
import Testing

@testable import Glance

/// Opened rows whose words stand level with the pictures and buttons in their middle without the
/// notch growing wider: a single line, as high as it goes under the camera, the row a little taller;
/// and the screen recording, whose time stands beside the camera.
@Suite("Opened rows' words are centered")
struct OpenedRowTests {
    private let h: CGFloat = 32
    private let title = NSFont.systemFont(ofSize: NotchType.size, weight: .semibold)
    private let detail = NSFont.systemFont(ofSize: NotchType.size)

    @Test("One line: it stays just under the camera, what's at the ends level with it, and the notch's edge as far under them as they are in from the ends")
    func oneLine() {
        let middle = UnderCamera.oneLineMiddle(font: title, restingHeight: h)
        #expect(abs(middle - (h + UnderCamera.clearance + UnderCamera.baseline([], font: title, restingHeight: h)) / 2) < 0.01)
        let side = TimerLayout.content(h), edge = TimerLayout.buttonEdge(h)
        let row = UnderCamera.oneLineHeight(middle: middle, side: side, edge: edge)
        #expect(abs(row - (middle + side / 2) - edge) <= 0.5)
        // Never less room above them than under them.
        #expect(UnderCamera.oneLineHeight(middle: 10, side: side, edge: edge) == (side + 2 * edge).rounded())
    }

    @Test("Music Recognition and Shortcuts: what's at the ends level with a name alone, or ending where two lines do, and the notch's edge as far under it as it is in from the ends")
    @MainActor func rows() {
        let found = MusicRecognitionActivity.State.match(.init(title: "Example Song", artist: "Example Artist", musicURL: nil))
        let m = ActivityRowMetrics.recognition(h)
        let side = ActivityRowLayout.side(m)
        // Found: the disc and the buttons end where the artist's line does.
        let bottom = UnderCamera.twoLineBottom(["Example Song"], first: m.titleNSFont, line: "Example Artist", font: detail, restingHeight: h)
        #expect(abs(ActivityRowLayout.sidesMiddle(title: "Example Song", detail: "Example Artist", metrics: m, restingHeight: h) + side / 2 - bottom) < 0.01)
        #expect(abs(MusicRecognitionActivityView.height(for: found, restingHeight: h) - bottom - m.buttonEdge) <= 0.5)
        // Listening: level with its name, as far under as from the ends.
        let middle = UnderCamera.oneLineMiddle(font: m.titleNSFont, restingHeight: h)
        #expect(abs(MusicRecognitionActivityView.height(for: .recognizing, restingHeight: h) - (middle + side / 2) - m.buttonEdge) <= 0.5)
        // The disc and the buttons as far in from the ends as every row's.
        #expect(m.pictureEdge == TimerLayout.buttonEdge(h) && m.buttonEdge == TimerLayout.buttonEdge(h))
        #expect(ShortcutRunView.height(restingHeight: h) > ActivityRowMetrics.shortcut(h).height)
    }

    @Test("Voice Memos, one line, a little taller; the screen recording, two lines, the iPhone's height")
    func recordings() {
        #expect(RecordingLook.openHeight(.voiceMemo(.recording(since: .now)), restingHeight: h) > TimerLayout.rowHeight(h))
        #expect(RecordingLook.openHeight(.screen(.recording(since: .now)), restingHeight: h) == TimerLayout.rowHeight(h))
    }

    @Test("Opened, the screen recording's time and name stand level with its button, the time beside the camera, clear of it")
    @MainActor func screenRecordingCentered() {
        let camera: CGFloat = 185
        let reading = "00:05"
        let font = NSFont.monospacedDigitSystemFont(ofSize: NotchType.size, weight: .semibold)
        let baseline = RecordingLook.screenBaseline(reading, restingHeight: h)
        let top = baseline - UnderCamera.reach([reading], font: font)
        let last = baseline + NotchType.size * RecordingLook.lines
        #expect(abs((top + last) / 2 - TimerLayout.rowHeight(h) / 2) < 0.01)
        let width = RecordingLook.screenWidth(restingHeight: h, camera: camera, length: 5)
        #expect((width - camera) / 2 >= TimerLayout.buttonEdge(h) + RecordingLook.firstLineWidth(5) + LiveActivityView.cameraGap)
        #expect(RecordingLook.screenWidth(restingHeight: h, camera: camera, length: 3_700) > width)
    }

    @Test("AirDrop and a call coming in or going out: the words stay just under the camera, the picture and buttons end where they do, and the room under them all is what they keep from the ends")
    @MainActor func twoLines() {
        let detail = NSFont.systemFont(ofSize: NotchType.size)
        let from = "From iPhone"
        let bottom = AirDropLayout.wordsBottom(h, from: from)
        let first = AirDropLayout.wordsBaseline(h)
        // The words' bottom: the line under "AirDrop", at its baseline, since none of its letters hangs
        // below (round ones overshoot it a hair).
        #expect(bottom >= first + UnderCamera.lineStep(detail) && bottom - (first + UnderCamera.lineStep(detail)) < 0.5)
        // A letter that hangs below takes it lower.
        #expect(AirDropLayout.wordsBottom(h, from: "From Gary") > bottom + 2)
        // The picture and the ring end there, and the notch's edge is as far under as they are in from the ends.
        #expect(abs(AirDropLayout.sidesMiddle(h, from: from) + TimerLayout.content(h) / 2 - bottom) < 0.01)
        let open = AirDropLayout.openHeight(h, from: from)
        #expect(abs(open - bottom - AirDropLayout.ringEdge(h)) <= 0.5)
        #expect(open > TimerLayout.rowHeight(h) && open < 80)
        let model = NotchModel(closedSize: CGSize(width: 185, height: h), layout: .top, hasCamera: true)
        model.airdrop = AirDropShown(id: "a", sender: "iPhone", preview: nil, fraction: 0.5)
        model.expanded = .airdrop
        model.state = .open
        #expect(model.metrics.height == open)
        // A call ringing: its announcement as tall as its opened row, the same width as ever.
        let ringing = CallShown(name: "Alex Morgan", over: "Phone", app: CallAudio.phone, phase: .ringing, line: "mobile")
        #expect(ExpandedCallView.height(for: ringing, restingHeight: h) == CallLayout.comingHeight(for: ringing, restingHeight: h))
        model.alert = NotchAlert(kind: .incomingCall, content: .incomingCall(ringing), spoken: "call", stays: true)
        #expect(model.restingHeight == CallLayout.comingHeight(for: ringing, restingHeight: h))
        let callBottom = CallLayout.wordsBottom(for: ringing, restingHeight: h)
        #expect(abs(CallLayout.sidesMiddle(for: ringing, restingHeight: h) + CallLayout.round(h) / 2 - callBottom) < 0.01)
        #expect(abs(CallLayout.comingHeight(for: ringing, restingHeight: h) - callBottom - CallLayout.roundEdge(h)) <= 0.5)
    }
}
