import SwiftUI

@main
struct BDMenuPlayerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandMenu("Playback") {
                Button("Play/Pause") { model.playback.togglePause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Back 10 Seconds") { model.playback.seek(by: -10) }
                    .keyboardShortcut("j", modifiers: [])
                Button("Forward 10 Seconds") { model.playback.seek(by: 10) }
                    .keyboardShortcut("l", modifiers: [])
                Button("Mute") { model.playback.toggleMute() }
                    .keyboardShortcut("m", modifiers: [])
                Button("Blu-ray Popup Menu") { model.playback.navigate(.popup) }
                    .keyboardShortcut("p", modifiers: [])
                Button("Close Blu-ray Menu") { model.playback.navigate(.popup) }
                    .keyboardShortcut(.delete, modifiers: [])
                Button("Menu Up") { model.playback.navigate(.up) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("Menu Down") { model.playback.navigate(.down) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button("Menu Left / Back 10 Seconds") { model.playback.leftArrowAction() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Menu Right / Forward 10 Seconds") { model.playback.rightArrowAction() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Activate Menu Item") { model.playback.navigate(.activate) }
                    .keyboardShortcut(.return, modifiers: [])
                Divider()
                Button("Toggle Full Screen") { model.playback.toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [])
            }
            CommandGroup(after: .importExport) {
                Button("Choose External Subtitle…") {
                    model.chooseSubtitle()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
