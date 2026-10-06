import SwiftUI

@main
struct BDMenuPlayerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
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
                Button("Subtitle Earlier 0.5s") { model.playback.adjustSubtitleDelay(by: -500) }
                    .keyboardShortcut("g", modifiers: [])
                Button("Subtitle Later 0.5s") { model.playback.adjustSubtitleDelay(by: 500) }
                    .keyboardShortcut("h", modifiers: [])
                Button("Subtitle Earlier 5s") { model.playback.adjustSubtitleDelay(by: -5_000) }
                    .keyboardShortcut("g", modifiers: [.shift])
                Button("Subtitle Later 5s") { model.playback.adjustSubtitleDelay(by: 5_000) }
                    .keyboardShortcut("h", modifiers: [.shift])
                Divider()
                Button("Previous Chapter") { model.playback.previousChapter() }
                    .keyboardShortcut(.pageUp, modifiers: [])
                Button("Next Chapter") { model.playback.nextChapter() }
                    .keyboardShortcut(.pageDown, modifiers: [])
                Button("Stop") { model.playback.stop() }
                    .keyboardShortcut(".", modifiers: [.command])
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
