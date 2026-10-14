import AppKit
import Foundation

/// Opt-in sounds for newly arrived items. Approval "Funk", question "Tink", done "Glass".
@MainActor
final class SoundPlayer {
    private let settings: AppSettings

    init(_ settings: AppSettings) {
        self.settings = settings
    }

    func play(_ item: NotchItem) {
        guard settings.soundsEnabled else { return }
        let name: String
        switch item.kind {
        case .approval: name = "Funk"
        case .question: name = "Tink"
        case .done: name = "Glass"
        default: return
        }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
