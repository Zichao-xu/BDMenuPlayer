import AppKit
import CVLCBridge
import Foundation

private actor VLCCommandActor {
    private var bridge: OpaquePointer?

    init(pluginPath: String) {
        bridge = pluginPath.withCString { vlcbridge_create($0) }
    }

    isolated deinit {
        if let bridge { vlcbridge_destroy(bridge) }
    }

    func isReady() -> Bool { bridge != nil }

    func bridgeAddress() -> UInt? {
        bridge.map { UInt(bitPattern: $0) }
    }

    func play(discPath: String, subtitleURI: String?) -> (result: Int32, error: String?) {
        guard let bridge else { return (-1, "Unable to initialize ARM64 libVLC") }
        let result = discPath.withCString { path in
            if let subtitleURI {
                return subtitleURI.withCString { vlcbridge_play_bluray(bridge, path, $0) }
            }
            return vlcbridge_play_bluray(bridge, path, nil)
        }
        return (result, error(fallback: "Playback failed"))
    }

    func addSubtitle(uri: String) -> (result: Int32, error: String?) {
        guard let bridge else { return (-1, "Unable to initialize ARM64 libVLC") }
        let result = uri.withCString { vlcbridge_add_subtitle(bridge, $0) }
        return (result, error(fallback: "Subtitle loading failed"))
    }

    func stop() {
        guard let bridge else { return }
        vlcbridge_stop(bridge)
    }

    func togglePause() {
        guard let bridge else { return }
        vlcbridge_toggle_pause(bridge)
    }

    func navigate(_ navigation: Int) {
        guard let bridge else { return }
        let value: VLCBridgeNavigation = switch navigation {
        case 1: VLCBridgeNavigateUp
        case 2: VLCBridgeNavigateDown
        case 3: VLCBridgeNavigateLeft
        case 4: VLCBridgeNavigateRight
        case 5: VLCBridgeNavigatePopup
        default: VLCBridgeNavigateActivate
        }
        vlcbridge_navigate(bridge, value)
    }

    func playerState() -> Int32 {
        guard let bridge else { return 7 }
        return vlcbridge_player_state(bridge)
    }

    func hasVideoOutput() -> Bool {
        guard let bridge else { return false }
        return vlcbridge_has_video_output(bridge) != 0
    }

    func playbackTimeMilliseconds() -> Int64 {
        guard let bridge else { return -1 }
        return vlcbridge_player_time(bridge)
    }

    func playbackLengthMilliseconds() -> Int64 {
        guard let bridge else { return -1 }
        return vlcbridge_player_length(bridge)
    }

    func setPlaybackTime(milliseconds: Int64) {
        guard let bridge else { return }
        vlcbridge_set_player_time(bridge, milliseconds)
    }

    func previousChapter() {
        guard let bridge else { return }
        vlcbridge_previous_chapter(bridge)
    }

    func nextChapter() {
        guard let bridge else { return }
        vlcbridge_next_chapter(bridge)
    }

    func audioState() -> (volume: Int32, muted: Bool) {
        guard let bridge else { return (100, false) }
        return (vlcbridge_audio_volume(bridge), vlcbridge_audio_muted(bridge) != 0)
    }

    func setVolume(_ volume: Int32) {
        guard let bridge else { return }
        vlcbridge_set_audio_volume(bridge, volume)
    }

    func toggleMute() {
        guard let bridge else { return }
        vlcbridge_toggle_audio_mute(bridge)
    }

    private func error(fallback: String) -> String {
        guard let bridge, let error = vlcbridge_last_error(bridge) else { return fallback }
        return String(cString: error)
    }
}

@MainActor
final class PlaybackController: ObservableObject {
    enum Navigation: Int, Sendable {
        case activate = 0
        case up = 1
        case down = 2
        case left = 3
        case right = 4
        case popup = 5
    }

    @Published private(set) var status = "Initializing ARM64 playback…"
    @Published private(set) var isPlaying = false
    @Published private(set) var isSessionActive = false
    @Published private(set) var subtitleLines: [String] = []
    @Published private(set) var isMainFeatureActive = false
    @Published private(set) var currentTimeMilliseconds: Int64 = 0
    @Published private(set) var currentDurationMilliseconds: Int64 = 0
    @Published private(set) var volume: Double = 1
    @Published private(set) var isMuted = false
    @Published private(set) var isFullScreen = false

    private let commands: VLCCommandActor
    private let videoView: NSView
    private var stateMonitor: Task<Void, Never>?
    private var subtitleTrack: ASSSubtitleTrack?
    private var expectedMainDurationMilliseconds: Int64 = 0

    init() {
        let vlcRoot = Self.vlcRoot
        let hasDecryptionBackend = BackendLocator.prepareMakeMKVIntegration()
        videoView = VLCVideoHostView()
        commands = VLCCommandActor(pluginPath: vlcRoot.appending(path: "plugins").path)

        let commands = self.commands
        Task { [weak self] in
            guard let self else { return }
            if await commands.isReady() {
                self.status = hasDecryptionBackend
                    ? "ARM64 libVLC + MakeMKV backend ready"
                    : "ARM64 libVLC ready — AACS backend required"
            } else {
                self.status = "Unable to initialize ARM64 libVLC"
            }
        }
    }

    isolated deinit {
        stateMonitor?.cancel()
    }

    func persistentVideoView() -> NSView {
        attachPersistentVideoView()
        return videoView
    }

    func attachPersistentVideoView() {
        let commands = self.commands
        Task { [weak self] in
            guard
                let self,
                let address = await commands.bridgeAddress(),
                let bridge = OpaquePointer(bitPattern: address)
            else { return }

            // libVLC's macOS video output is backed by AppKit. Attaching its
            // NSView must happen on the main thread or the decoder can run
            // normally while the view remains permanently black.
            let pointer = Unmanaged.passUnretained(self.videoView).toOpaque()
            vlcbridge_set_video_view(bridge, pointer)
        }
    }

    func play(disc: DiscVolume, subtitle: URL?) {
        stateMonitor?.cancel()
        attachPersistentVideoView()
        isPlaying = true
        isSessionActive = true
        status = "Opening Blu-ray menu…"
        subtitleTrack = subtitle.flatMap { try? ASSSubtitleTrack(url: $0) }
        expectedMainDurationMilliseconds = Int64(disc.info.mainDuration * 1000)
        subtitleLines = []
        isMainFeatureActive = false
        currentTimeMilliseconds = 0
        currentDurationMilliseconds = 0

        let commands = self.commands
        let discPath = disc.mountURL.path
        Task { [weak self] in
            // Start the interactive disc first. Adding an ASS slave while the
            // Blu-ray menu demuxer and macOS vout are both initializing can
            // leave libVLC decoding behind a permanently black surface.
            let outcome = await commands.play(discPath: discPath, subtitleURI: nil)
            guard let self else { return }
            // Some libbluray menu transitions return a non-zero play result
            // even though the media player continues opening and produces a
            // video output. Trust the state monitor instead of covering that
            // live output with the idle preview again.
            if outcome.result != 0 {
                self.status = "Blu-ray menu is still opening…"
            }
            self.startStateMonitor()
        }
    }

    func addSubtitle(_ subtitle: URL) {
        subtitleTrack = try? ASSSubtitleTrack(url: subtitle)
        status = subtitleTrack == nil ? "Subtitle loading failed" : "Bilingual subtitle loaded"
    }

    func stop() {
        stateMonitor?.cancel()
        isPlaying = false
        isSessionActive = false
        subtitleLines = []
        isMainFeatureActive = false
        currentTimeMilliseconds = 0
        currentDurationMilliseconds = 0
        status = "Stopped"
        let commands = self.commands
        Task { await commands.stop() }
    }

    func togglePause() {
        isPlaying.toggle()
        status = isPlaying ? "Playing…" : "Paused"
        let commands = self.commands
        Task { await commands.togglePause() }
    }

    func navigate(_ navigation: Navigation) {
        let commands = self.commands
        Task { await commands.navigate(navigation.rawValue) }
    }

    func seek(by seconds: Double) {
        guard isMainFeatureActive else { return }
        seek(to: Double(currentTimeMilliseconds) / 1000 + seconds)
    }

    func seek(to seconds: Double) {
        guard isMainFeatureActive else { return }
        let upper = max(Int64(0), currentDurationMilliseconds - 500)
        let target = min(upper, max(Int64(0), Int64(seconds * 1000)))
        currentTimeMilliseconds = target
        let commands = self.commands
        Task { await commands.setPlaybackTime(milliseconds: target) }
    }

    func previousChapter() {
        guard isMainFeatureActive else { return }
        let commands = self.commands
        Task { await commands.previousChapter() }
    }

    func nextChapter() {
        guard isMainFeatureActive else { return }
        let commands = self.commands
        Task { await commands.nextChapter() }
    }

    func setVolume(_ newValue: Double) {
        volume = min(1.25, max(0, newValue))
        let commands = self.commands
        let value = Int32((volume * 100).rounded())
        Task { await commands.setVolume(value) }
    }

    func toggleMute() {
        isMuted.toggle()
        let commands = self.commands
        Task { await commands.toggleMute() }
    }

    func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    func didEnterFullScreen() {
        isFullScreen = true
    }

    func didExitFullScreen() {
        isFullScreen = false
    }

    func leftArrowAction() {
        isMainFeatureActive ? seek(by: -10) : navigate(.left)
    }

    func rightArrowAction() {
        isMainFeatureActive ? seek(by: 10) : navigate(.right)
    }

    private func startStateMonitor() {
        stateMonitor?.cancel()
        let commands = self.commands
        stateMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self else { return }
                switch await commands.playerState() {
                case 1:
                    self.status = "Opening Blu-ray menu…"
                case 2:
                    self.status = "Buffering Blu-ray menu…"
                case 3:
                    self.isPlaying = true
                    let length = await commands.playbackLengthMilliseconds()
                    let isMainFeature = self.isMainFeature(lengthMilliseconds: length)
                    self.isMainFeatureActive = isMainFeature
                    self.currentDurationMilliseconds = max(0, length)
                    self.currentTimeMilliseconds = max(0, await commands.playbackTimeMilliseconds())
                    let audio = await commands.audioState()
                    self.volume = Double(audio.volume) / 100
                    self.isMuted = audio.muted
                    if isMainFeature {
                        self.status = self.subtitleTrack == nil
                            ? "Playing main feature"
                            : "Playing main feature · bilingual subtitle enabled"
                        self.subtitleLines = self.subtitleTrack?.lines(at: self.currentTimeMilliseconds) ?? []
                    } else {
                        self.status = "Playing original Blu-ray menu"
                        self.subtitleLines = []
                    }
                case 4:
                    self.isPlaying = false
                    self.status = "Paused"
                case 5, 6:
                    self.isPlaying = false
                    self.isMainFeatureActive = false
                    // Blu-ray Java/HDMV menus can briefly transition through
                    // Ended or Stopped while switching menu clips. Keep the
                    // video surface exposed until the user explicitly stops.
                case 7:
                    self.isPlaying = false
                    self.isSessionActive = false
                    self.status = "Blu-ray playback error — check the AACS backend"
                    self.subtitleLines = []
                    self.isMainFeatureActive = false
                    self.currentTimeMilliseconds = 0
                    self.currentDurationMilliseconds = 0
                    return
                default:
                    break
                }
            }
        }
    }

    private func isMainFeature(lengthMilliseconds: Int64) -> Bool {
        guard lengthMilliseconds > 20 * 60 * 1000 else { return false }
        guard expectedMainDurationMilliseconds > 0 else { return true }
        let tolerance = max(Int64(3_000), expectedMainDurationMilliseconds / 100)
        return abs(lengthMilliseconds - expectedMainDurationMilliseconds) <= tolerance
    }

    private static var vlcRoot: URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appending(path: "VLC")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        if let configured = ProcessInfo.processInfo.environment["BD_MENU_PLAYER_VLC_ROOT"],
           !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Dependencies/VLC")
    }
}
