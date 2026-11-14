import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Hide commands keep their menu target")
struct ActivityMenuSnapshotTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func model() -> NotchModel {
        NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
    }

    private func seed(_ activity: NotchModel.Activity, in model: NotchModel, player: NowPlaying, variant: Int = 0) {
        let offset = Double(variant) * 30
        switch activity {
        case .call:
            model.call = CallShown(name: "Caller \(variant)", over: "Phone", app: nil, phase: .connected(since: start + offset))
        case .screenRecording: model.screenRecording = .recording(since: start + offset)
        case .voiceMemo: model.voiceMemo = .recording(since: start + offset)
        case .music:
            player.apply(["title": "Song \(variant)", "artist": "Artist", "album": "Album", "elapsed": 10.0])
            model.activity = true
        case .airdrop:
            model.airdrop = AirDropShown(id: "transfer-\(variant)", sender: "Alex", preview: nil, fraction: 0.2)
        case .timer: model.timer = .running(until: start + 300 + offset, total: 300)
        case .stopwatch: model.stopwatch = .running(since: start + offset)
        case .airplay: model.airplay = AirPlayRoute(name: "Speaker \(variant)", symbol: "homepod", outputID: UInt32(variant + 1))
        }
    }

    private func remove(_ activity: NotchModel.Activity, from model: NotchModel, player: NowPlaying) {
        switch activity {
        case .call: model.call = nil
        case .screenRecording: model.screenRecording = nil
        case .voiceMemo: model.voiceMemo = nil
        case .music:
            player.apply([:])
            model.activity = false
        case .airdrop: model.airdrop = nil
        case .timer: model.timer = nil
        case .stopwatch: model.stopwatch = nil
        case .airplay: model.airplay = nil
        }
    }

    @Test("A menu keeps its original display and named activity when the visible selection changes", arguments: NotchModel.Activity.allCases)
    func keepsTarget(_ activity: NotchModel.Activity) throws {
        let original = model(), otherDisplay = model()
        let player = NowPlaying(followsPlayers: false)
        seed(activity, in: original, player: player)
        var hidden: [NotchController.PutAwayTarget] = []
        let command = try #require(NotchController.putAwayCommand(model: original, nowPlaying: player) { hidden.append($0) })
        #expect(command.title == NotchController.putAwayTitle(alert: nil, first: activity))

        // Moving to another display, or opening another page, must not retarget the old row.
        otherDisplay.timer = .paused(left: 60, total: 60)
        original.state = .open
        original.page = .tray
        command.action()

        #expect(hidden == [.activity(activity)])
        #expect(otherDisplay.timer == .paused(left: 60, total: 60))
    }

    @Test("An ended target cannot hide the activity that survives it", arguments: NotchModel.Activity.allCases)
    func endedTarget(_ activity: NotchModel.Activity) throws {
        let model = model(), player = NowPlaying(followsPlayers: false)
        seed(activity, in: model, player: player)
        var hidden: [NotchController.PutAwayTarget] = []
        let command = try #require(NotchController.putAwayCommand(model: model, nowPlaying: player) { hidden.append($0) })
        remove(activity, from: model, player: player)
        seed(activity == .timer ? .airdrop : .timer, in: model, player: player)
        command.action()
        #expect(hidden.isEmpty)
    }

    @Test("A replacement of the same activity kind cannot inherit a menu command", arguments: NotchModel.Activity.allCases)
    func replacedTarget(_ activity: NotchModel.Activity) throws {
        let model = model(), player = NowPlaying(followsPlayers: false)
        seed(activity, in: model, player: player)
        var hidden: [NotchController.PutAwayTarget] = []
        let command = try #require(NotchController.putAwayCommand(model: model, nowPlaying: player) { hidden.append($0) })
        seed(activity, in: model, player: player, variant: 1)
        command.action()
        #expect(hidden.isEmpty)
    }

    @Test("An activity that leaves and returns with identical values is still a new arrival", arguments: NotchModel.Activity.allCases)
    func returnedTarget(_ activity: NotchModel.Activity) throws {
        let model = model(), player = NowPlaying(followsPlayers: false)
        seed(activity, in: model, player: player)
        var hidden: [NotchController.PutAwayTarget] = []
        let command = try #require(NotchController.putAwayCommand(model: model, nowPlaying: player) { hidden.append($0) })
        remove(activity, from: model, player: player)
        seed(activity, in: model, player: player)
        command.action()
        #expect(hidden.isEmpty)
    }

    @Test("Progress and action-availability updates keep the same transfer and route hideable")
    func continuingTransfers() throws {
        for activity in [NotchModel.Activity.airdrop, .airplay] {
            let model = model(), player = NowPlaying(followsPlayers: false)
            seed(activity, in: model, player: player)
            var hidden: [NotchController.PutAwayTarget] = []
            let command = try #require(NotchController.putAwayCommand(model: model, nowPlaying: player) { hidden.append($0) })
            if activity == .airdrop {
                model.airdrop?.fraction = 0.8
                model.airdrop?.canStop = false
            } else {
                model.airplay?.stopFailed = true
                model.airplay?.canStop = false
            }
            command.action()
            #expect(hidden == [.activity(activity)])
        }
    }

    @Test("A new announcement of the same kind does not inherit Hide")
    func replacedAnnouncement() throws {
        let model = model(), player = NowPlaying(followsPlayers: false)
        model.alert = BatteryWatch.lowBattery(.init(percent: 20, onPower: false, charging: false))
        var hidden: [NotchController.PutAwayTarget] = []
        let command = try #require(NotchController.putAwayCommand(model: model, nowPlaying: player) { hidden.append($0) })
        model.alert = BatteryWatch.lowBattery(.init(percent: 10, onPower: false, charging: false))
        command.action()
        #expect(hidden.isEmpty)
    }

    @Test("Hiding one announcement preserves a queued announcement of the same kind")
    func queuedAnnouncement() {
        let activities = Activities()
        let first = NotchAlert(kind: .lowBattery, content: .lowBattery(percent: 20), spoken: "Low battery", stays: true)
        let next = NotchAlert(kind: .lowBattery, content: .lowBattery(percent: 10), spoken: "Low battery", stays: true)
        activities.post(first)
        activities.post(next)
        activities.dismiss(id: UUID())
        #expect(activities.alert?.id == first.id)
        #expect(activities.waiting.map(\.id) == [next.id])
        activities.dismiss(id: first.id)
        #expect(activities.alert == nil)
        #expect(activities.waiting.map(\.id) == [next.id])
        activities.dismiss(id: next.id)
    }
}
