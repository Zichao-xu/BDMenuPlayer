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

    func logErrors() -> String {
        guard let bridge else { return "" }
        var buffer = [CChar](repeating: 0, count: 1024)
        vlcbridge_copy_log_errors(bridge, &buffer, buffer.count)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func error(fallback: String) -> String {
        guard let bridge, let error = vlcbridge_last_error(bridge) else { return fallback }
        return String(cString: error)
    }
}

struct PlaybackFailure: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The disc is AACS-encrypted and no working backend is installed.
        case decryptionBackendMissing
        /// MakeMKV is installed but could not unlock the disc (expired beta key,
        /// unknown disc, …).
        case decryptionBackendInactive
        case openFailed
    }

    let kind: Kind
    let title: String
    let detail: String

    static func decryption(backendInstalled: Bool) -> PlaybackFailure {
        backendInstalled
            ? PlaybackFailure(
                kind: .decryptionBackendInactive,
                title: "MakeMKV 无法解密这张光盘",
                detail: "已找到 MakeMKV,但它未能解开 AACS。打开 MakeMKV 确认已激活（Beta Key 未过期）并能读取这张光盘，然后重试。"
            )
            : PlaybackFailure(
                kind: .decryptionBackendMissing,
                title: "需要 AACS 解密后端",
                detail: "这张光盘使用 AACS 加密。请安装并激活 MakeMKV(BD Menu Player 会自动发现它),然后点“重新检测”。"
            )
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
    @Published private(set) var failure: PlaybackFailure?

    private let commands: VLCCommandActor
    private let videoView: NSView
    private var stateMonitor: Task<Void, Never>?
    private var subtitleTrack: ASSSubtitleTrack?
    private var expectedMainDurationMilliseconds: Int64 = 0
    private var currentDisc: DiscVolume?
    private var currentSubtitle: URL?
    private var lastPlayerState: Int32 = 0

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
        currentDisc = disc
        currentSubtitle = subtitle
        failure = nil

        // libVLC cannot open an AACS disc without a backend and only reports
        // "Ended", which used to leave a black surface with a dead play button.
        // Fail fast with an actionable explanation instead.
        if disc.info.needsDecryptionBackend {
            isPlaying = false
            isSessionActive = false
            failure = .decryption(backendInstalled: BackendLocator.makeMKVLibrary != nil)
            status = failure?.title ?? ""
            return
        }

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
        lastPlayerState = 1

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
        currentSubtitle = subtitle
        subtitleTrack = try? ASSSubtitleTrack(url: subtitle)
        status = subtitleTrack == nil ? "Subtitle loading failed" : "Bilingual subtitle loaded"
    }

    func clearSubtitle() {
        currentSubtitle = nil
        subtitleTrack = nil
        subtitleLines = []
    }

    var hasSubtitle: Bool { subtitleTrack != nil }

    /// The disc that the current (or last failed) session belongs to.
    var activeDiscID: DiscVolume.ID? { currentDisc?.id }

    func stop() {
        stateMonitor?.cancel()
        lastPlayerState = 5
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

    /// Clears a failed or finished session so the disc can be opened again.
    func dismissFailure() {
        failure = nil
        status = "Ready"
    }

    func togglePause() {
        // Pausing an ended, stopped or failed player is a no-op in libVLC, so
        // the play button reopens the disc instead.
        if failure != nil || !isSessionActive || [0, 5, 6, 7].contains(lastPlayerState) {
            if let currentDisc { play(disc: currentDisc, subtitle: currentSubtitle) }
            return
        }
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
            var reachedPlayback = false
            var terminalPolls = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self else { return }
                let state = await commands.playerState()
                self.lastPlayerState = state
                terminalPolls = (state == 5 || state == 6) ? terminalPolls + 1 : 0
                switch state {
                case 1:
                    self.status = "Opening Blu-ray menu…"
                case 2:
                    self.status = "Buffering Blu-ray menu…"
                case 3:
                    reachedPlayback = true
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
                    // Never reaching Playing means the input could not be
                    // opened at all; libVLC reports that as Ended, not Error.
                    if !reachedPlayback, terminalPolls >= 4 {
                        await self.failSession(log: commands.logErrors())
                        return
                    }
                    // Blu-ray Java/HDMV menus can briefly transition through
                    // Ended or Stopped while switching menu clips. Keep the
                    // video surface exposed until the user explicitly stops.
                case 7:
                    await self.failSession(log: commands.logErrors())
                    return
                default:
                    break
                }
            }
        }
    }

    private func failSession(log: String) {
        isPlaying = false
        isSessionActive = false
        subtitleLines = []
        isMainFeatureActive = false
        currentTimeMilliseconds = 0
        currentDurationMilliseconds = 0
        if log.localizedCaseInsensitiveContains("AACS") || log.localizedCaseInsensitiveContains("BD+") {
            failure = .decryption(backendInstalled: BackendLocator.makeMKVLibrary != nil)
        } else {
            failure = PlaybackFailure(
                kind: .openFailed,
                title: "无法打开蓝光菜单",
                detail: log.isEmpty ? "libVLC 未能打开这张光盘。" : log
            )
        }
        status = failure?.title ?? "Playback failed"
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
