import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Lyrics preview scale")
struct PreviewScaleTests {
    @Test("Lyrics fit while keeping at least three quarters of the normal scale", arguments: [320.0, 468, 600])
    func fits(_ width: Double) {
        let preview = SettingsPreview()
        let model = preview.model
        for layout in PlayerLayout.allCases {
            model.use(layout)
            let normal = NotchPreview.scale(for: width, model: model)
            let lyrics = min(normal, NotchPreview.scale(for: width, model: model, lyrics: true))
            #expect(lyrics >= normal * 0.75)
            #expect((model.openSize.width + model.lyricsWidth + PlayerLayout.cornerRadius * 2) * lyrics <= width)
            for _ in 0..<10 { model.lyrics.toggle() }
            #expect(NotchPreview.scale(for: width, model: model) == normal)
        }
    }
}
