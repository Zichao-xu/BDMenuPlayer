import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var discs: [DiscVolume] = []
    @Published var selectedDiscID: DiscVolume.ID?
    @Published private(set) var externalSubtitle: URL?
    @Published private(set) var externalSubtitleLabel: String?
    @Published private(set) var subtitleError: String?
    @Published private(set) var isScanning = false
    let playback = PlaybackController()
    private var scanTask: Task<Void, Never>?

    var selectedDisc: DiscVolume? {
        guard let selectedDiscID else { return discs.first }
        return discs.first { $0.id == selectedDiscID }
    }

    init() {
        refreshDiscs()
    }

    func refreshDiscs() {
        scanTask?.cancel()
        isScanning = true
        scanTask = Task { [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) {
                DiscScanner.scan()
            }.value
            guard let self, !Task.isCancelled else { return }
            self.discs = scanned
            if self.selectedDiscID == nil || !scanned.contains(where: { $0.id == self.selectedDiscID }) {
                self.selectedDiscID = scanned.first?.id
            }
            self.isScanning = false
        }
    }

    func chooseSubtitle() {
        let panel = NSOpenPanel()
        panel.title = "Choose an external subtitle"
        panel.prompt = "Use Subtitle"
        panel.allowedContentTypes = [.init(filenameExtension: "srt")!, .init(filenameExtension: "ass")!, .init(filenameExtension: "ssa")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        guard let selectedDisc else { return }
        do {
            externalSubtitle = try SubtitleComposer.compose(urls: panel.urls, for: selectedDisc.info)
            externalSubtitleLabel = panel.urls.count > 1
                ? panel.urls.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: " + ")
                : panel.urls[0].lastPathComponent
            subtitleError = nil
            if playback.isPlaying, let externalSubtitle {
                playback.addSubtitle(externalSubtitle)
            }
        } catch {
            subtitleError = error.localizedDescription
        }
    }

    func clearSubtitle() {
        externalSubtitle = nil
        externalSubtitleLabel = nil
        subtitleError = nil
    }

    func playSelectedDisc() {
        guard let selectedDisc else { return }
        playback.play(disc: selectedDisc, subtitle: externalSubtitle)
    }
}
