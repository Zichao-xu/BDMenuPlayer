import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var discs: [DiscVolume] = []
    @Published var selectedDiscID: DiscVolume.ID? {
        didSet {
            guard selectedDiscID != oldValue else { return }
            selectionChanged()
            autoPlayIfReady()
        }
    }
    @Published private(set) var externalSubtitle: URL?
    @Published private(set) var externalSubtitleLabel: String?
    @Published private(set) var subtitleError: String?
    @Published private(set) var isScanning = false
    let playback = PlaybackController()
    private var scanTask: Task<Void, Never>?
    private var volumeObservers: [NSObjectProtocol] = []
    /// Discs that already started on their own, so Stop is not undone by a rescan.
    private var autoPlayedDiscIDs: Set<DiscVolume.ID> = []

    var selectedDisc: DiscVolume? {
        guard let selectedDiscID else { return discs.first }
        return discs.first { $0.id == selectedDiscID }
    }

    init() {
        refreshDiscs()
        observeVolumes()
    }

    /// Rescans automatically when a disc is inserted or ejected. A freshly
    /// mounted BD-ROM can take a moment before its BDMV tree is readable.
    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDiscs(after: .seconds(1)) }
            })
        }
    }

    func refreshDiscs(after delay: Duration = .zero) {
        scanTask?.cancel()
        isScanning = true
        scanTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            // Picks up a MakeMKV installed while the app is running.
            BackendLocator.prepareMakeMKVIntegration()
            let scanned = await Task.detached(priority: .userInitiated) {
                DiscScanner.scan()
            }.value
            guard let self, !Task.isCancelled else { return }
            self.discs = scanned
            if let active = self.playback.activeDiscID, !scanned.contains(where: { $0.id == active }) {
                self.playback.stop()
                self.playback.dismissFailure()
            }
            if self.selectedDiscID == nil || !scanned.contains(where: { $0.id == self.selectedDiscID }) {
                self.selectedDiscID = scanned.first?.id
            }
            self.isScanning = false
            self.autoPlayIfReady()
        }
    }

    func chooseSubtitle() {
        guard let selectedDisc else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an external subtitle"
        panel.prompt = "Use Subtitle"
        panel.allowedContentTypes = [.init(filenameExtension: "srt")!, .init(filenameExtension: "ass")!, .init(filenameExtension: "ssa")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        do {
            externalSubtitle = try SubtitleComposer.compose(urls: panel.urls, for: selectedDisc.info)
            externalSubtitleLabel = panel.urls.count > 1
                ? panel.urls.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: " + ")
                : panel.urls[0].lastPathComponent
            subtitleError = nil
            if playback.isSessionActive, let externalSubtitle {
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
        playback.clearSubtitle()
    }

    /// Re-reads the discs after the user installs or activates a backend.
    func recheckBackend() {
        playback.dismissFailure()
        refreshDiscs()
    }

    /// Like a hardware player: an inserted disc starts its menu by itself,
    /// unless it is known not to open.
    private func autoPlayIfReady() {
        guard
            let disc = selectedDisc,
            !disc.info.needsDecryptionBackend,
            !playback.isSessionActive,
            playback.failure == nil,
            !autoPlayedDiscIDs.contains(disc.id)
        else { return }
        autoPlayedDiscIDs.insert(disc.id)
        playSelectedDisc()
    }

    /// Stops a session that belongs to a disc other than the selected one.
    private func selectionChanged() {
        guard let active = playback.activeDiscID, active != selectedDiscID else { return }
        playback.stop()
        playback.dismissFailure()
    }

    func playSelectedDisc() {
        guard let selectedDisc else { return }
        playback.play(disc: selectedDisc, subtitle: externalSubtitle)
    }
}
