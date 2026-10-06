import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var playback: PlaybackController

    init(model: AppModel) {
        self.model = model
        self.playback = model.playback
    }

    var body: some View {
        Group {
            if playback.isFullScreen, model.selectedDisc != nil {
                PlayerSurfaceView(
                    playback: playback,
                    isFullScreen: true,
                    disc: model.selectedDisc,
                    onPlay: { model.playSelectedDisc() },
                    onRecheck: { model.recheckBackend() },
                    onChooseSubtitle: { model.chooseSubtitle() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .ignoresSafeArea()
            } else {
                standardLayout
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            playback.didEnterFullScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            playback.didExitFullScreen()
        }
    }

    private var standardLayout: some View {
        NavigationSplitView {
            List(selection: $model.selectedDiscID) {
                Section("Blu-ray Discs") {
                    ForEach(model.discs) { disc in
                        Label(disc.info.displayName, systemImage: "opticaldisc")
                            .tag(disc.id)
                    }
                }
            }
            .navigationTitle("BD Menu")
            .toolbar {
                if model.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        model.refreshDiscs()
                    }
                }
            }
        } detail: {
            if let disc = model.selectedDisc {
                DiscDetailView(disc: disc, model: model)
            } else if model.isScanning {
                ProgressView("Reading Blu-ray disc…")
            } else {
                ContentUnavailableView(
                    "No Blu-ray Disc",
                    systemImage: "opticaldisc",
                    description: Text("Insert a Blu-ray disc, then refresh.")
                )
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onChange(of: model.selectedDiscID) { _, _ in model.selectionChanged() }
    }
}

private struct DiscDetailView: View {
    let disc: DiscVolume
    @ObservedObject var model: AppModel
    @ObservedObject private var playback: PlaybackController

    init(disc: DiscVolume, model: AppModel) {
        self.disc = disc
        self.model = model
        self.playback = model.playback
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(disc.info.displayName)
                        .font(.largeTitle.weight(.semibold))
                    Text(disc.mountURL.path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    StatusBadge(label: "Top Menu", ready: disc.info.hasTopMenu)
                    StatusBadge(label: "First Play", ready: disc.info.hasFirstPlay)
                    StatusBadge(label: "HDMV", ready: disc.info.hdmvTitleCount > 0)
                    StatusBadge(label: "BD-J", ready: disc.info.usesBDJ)
                }

                PlayerSurfaceView(
                    playback: playback,
                    isFullScreen: false,
                    disc: disc,
                    onPlay: { model.playSelectedDisc() },
                    onRecheck: { model.recheckBackend() },
                    onChooseSubtitle: { model.chooseSubtitle() }
                )
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                GroupBox("Disc capabilities") {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                        infoRow("Titles", "\(disc.info.titleCount) total · \(disc.info.hdmvTitleCount) HDMV · \(disc.info.bdjTitleCount) BD-J")
                        infoRow("AACS", aacsStatus(for: disc.info), warning: disc.info.needsDecryptionBackend)
                        infoRow("BD+", disc.info.usesBDPlus ? (disc.info.bdplusReady ? "Ready" : "Detected — backend required") : "Not used")
                        infoRow("libbluray", disc.info.libblurayVersion + " · ARM64")
                    }
                    .padding(8)
                }

                GroupBox("External subtitle") {
                    HStack {
                        Image(systemName: "captions.bubble")
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(model.externalSubtitleLabel ?? "No subtitle selected")
                                .font(.headline)
                            Text("Select multiple ASS files to merge split episodes on a combined BD title.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.externalSubtitle != nil {
                            Button("Clear") { model.clearSubtitle() }
                        }
                        Button("Choose…") { model.chooseSubtitle() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(8)
                    if let subtitleError = model.subtitleError {
                        Label(subtitleError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                    }
                }

                Label(playback.status, systemImage: "wrench.and.screwdriver")
                    .foregroundStyle(.secondary)

                if let error = disc.info.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .padding(28)
        }
        .navigationTitle("Disc")
    }

    private func aacsStatus(for info: DiscTechnicalInfo) -> String {
        guard info.usesAACS else { return "Not used" }
        if info.aacsReady { return "Ready" }
        if BackendLocator.makeMKVLibrary != nil {
            return "MakeMKV found — activate or renew it"
        }
        return "Detected — decryption backend required"
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String, warning: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                .textSelection(.enabled)
        }
    }
}

private struct PlayerSurfaceView: View {
    @ObservedObject var playback: PlaybackController
    let isFullScreen: Bool
    let disc: DiscVolume?
    let onPlay: () -> Void
    let onRecheck: () -> Void
    let onChooseSubtitle: () -> Void

    /// A failure from the last attempt, or one that is already certain from
    /// the disc probe, so the user sees it before pressing Play.
    private var blocker: PlaybackFailure? {
        if let failure = playback.failure { return failure }
        if disc?.info.needsDecryptionBackend == true {
            return .decryption(backendInstalled: BackendLocator.makeMKVLibrary != nil)
        }
        return nil
    }

    @State private var showsControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var controlsHovered = false

    var body: some View {
        ZStack {
            VideoSurfaceView(controller: playback)
            MouseActivityView(onActivity: revealControls)

            if !playback.isSessionActive {
                if let blocker {
                    PlaybackBlockerView(failure: blocker, onRetry: onPlay, onRecheck: onRecheck)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 42))
                        Text("Blu-ray menu preview")
                            .font(.headline)
                        Button("Play Disc Menu", systemImage: "play.fill", action: onPlay)
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.return, modifiers: [.command])
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if !playback.subtitleLines.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    ForEach(Array(playback.subtitleLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(
                                size: isFullScreen ? (index == 0 ? 34 : 42) : (index == 0 ? 27 : 34),
                                weight: .semibold
                            ))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black, radius: 2, x: 0, y: 2)
                            .padding(.horizontal, 12)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, playback.isSessionActive && showsControls ? 150 : 34)
                .animation(.easeOut(duration: 0.2), value: showsControls)
                .allowsHitTesting(false)
            }

            if playback.isSessionActive, showsControls {
                PlayerControlsOverlay(
                    playback: playback,
                    onChooseSubtitle: onChooseSubtitle,
                    onHoverChanged: { hovering in
                        controlsHovered = hovering
                        if hovering {
                            hideTask?.cancel()
                            withAnimation(.easeOut(duration: 0.12)) { showsControls = true }
                        } else {
                            scheduleHide()
                        }
                    }
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            }
        }
        .background(.black)
        .contentShape(Rectangle())
        .onAppear { revealControls() }
        .onDisappear { hideTask?.cancel() }
        .onChange(of: playback.isPlaying) { _, isPlaying in
            if isPlaying {
                revealControls()
            } else {
                hideTask?.cancel()
                withAnimation(.easeOut(duration: 0.18)) { showsControls = true }
            }
        }
    }

    private func revealControls() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) { showsControls = true }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard playback.isPlaying, !controlsHovered else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, playback.isPlaying, !controlsHovered else { return }
            withAnimation(.easeInOut(duration: 0.24)) { showsControls = false }
            if isFullScreen { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }
}

private struct MenuDirectionPad: View {
    let playback: PlaybackController
    var enableShortcuts = true

    var body: some View {
        VStack(spacing: 4) {
            menuButton("chevron.up", shortcut: .upArrow) { playback.navigate(.up) }
            HStack(spacing: 4) {
                menuButton("chevron.left", shortcut: .leftArrow) { playback.leftArrowAction() }
                okButton
                menuButton("chevron.right", shortcut: .rightArrow) { playback.rightArrowAction() }
            }
            menuButton("chevron.down", shortcut: .downArrow) { playback.navigate(.down) }
        }
    }

    @ViewBuilder
    private var okButton: some View {
        let button = Button("OK") { playback.navigate(.activate) }
            .buttonStyle(MenuPadButtonStyle(isPrimary: true))
            .help("Activate selected menu item")
        if enableShortcuts {
            button.keyboardShortcut(.return, modifiers: [])
        } else {
            button
        }
    }

    @ViewBuilder
    private func menuButton(
        _ symbol: String,
        shortcut: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
        }
        .buttonStyle(MenuPadButtonStyle())
        if enableShortcuts {
            button.keyboardShortcut(shortcut, modifiers: [])
        } else {
            button
        }
    }
}

private struct PlayerControlsOverlay: View {
    @ObservedObject var playback: PlaybackController
    let onChooseSubtitle: () -> Void
    let onHoverChanged: (Bool) -> Void
    @State private var showsMenuPad = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    controlButton(playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", "静音 · M") {
                        playback.toggleMute()
                    }
                    Slider(
                        value: Binding(get: { playback.volume }, set: { playback.setVolume($0) }),
                        in: 0...1.25
                    )
                    .frame(width: 108)

                    Spacer(minLength: 16)
                    controlButton("backward.end.fill", "上一章节") { playback.previousChapter() }
                        .disabled(!playback.isMainFeatureActive)
                    controlButton("gobackward.10", "后退 10 秒 · J") { playback.seek(by: -10) }
                        .disabled(!playback.isMainFeatureActive)
                    playPauseButton
                    controlButton("goforward.10", "前进 10 秒 · L") { playback.seek(by: 10) }
                        .disabled(!playback.isMainFeatureActive)
                    controlButton("forward.end.fill", "下一章节") { playback.nextChapter() }
                        .disabled(!playback.isMainFeatureActive)
                    Spacer(minLength: 16)

                    // The disc's own popup menu is toggled by the same key that
                    // opens it; this is the "back / close menu" of a BD remote.
                    controlButton("menucard", "打开/关闭光盘菜单 · P 或 Delete") {
                        playback.navigate(.popup)
                    }
                    controlButton("dpad", "菜单方向键（键盘方向键 + Return 也可）") { showsMenuPad.toggle() }
                        .popover(isPresented: $showsMenuPad, arrowEdge: .top) {
                            HStack(spacing: 14) {
                                MenuDirectionPad(playback: playback, enableShortcuts: false)
                                Button {
                                    playback.navigate(.popup)
                                    showsMenuPad = false
                                } label: {
                                    Label("关闭菜单", systemImage: "chevron.down.circle")
                                }
                                .help("关闭光盘弹出菜单并收起方向键")
                            }
                            .padding(12)
                        }
                        // Keep the bar (and so the popover) up while the pad is in use.
                        .onChange(of: showsMenuPad) { _, shown in onHoverChanged(shown) }
                    controlButton(
                        playback.hasSubtitle ? "captions.bubble.fill" : "captions.bubble",
                        playback.hasSubtitle ? "更换外挂字幕 · ⇧⌘O" : "选择外挂字幕 · ⇧⌘O",
                        action: onChooseSubtitle
                    )
                    controlButton("stop.fill", "停止") { playback.stop() }
                    controlButton("arrow.up.left.and.arrow.down.right", "全屏 · F") {
                        playback.toggleFullScreen()
                    }
                }

                HStack(spacing: 12) {
                    Text(time(playback.currentTimeMilliseconds))
                    Slider(
                        value: Binding(
                            get: { Double(playback.currentTimeMilliseconds) / 1000 },
                            set: { playback.seek(to: $0) }
                        ),
                        in: 0...max(1, Double(playback.currentDurationMilliseconds) / 1000)
                    )
                    .disabled(!playback.isMainFeatureActive)
                    Text("−" + time(max(0, playback.currentDurationMilliseconds - playback.currentTimeMilliseconds)))
                }
                .font(.caption.monospacedDigit().weight(.semibold))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: 780)
            .glassEffect(.regular.tint(.black.opacity(0.18)).interactive(), in: .rect(cornerRadius: 26))
            .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .onHover(perform: onHoverChanged)
    }

    private var playPauseButton: some View {
        Button {
            playback.togglePause()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .bold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glassProminent)
        .help("播放/暂停 · Space")
    }

    private func controlButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .help(help)
    }

    private func time(_ milliseconds: Int64) -> String {
        let total = max(0, milliseconds / 1000)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct MenuPadButtonStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 42, height: 28)
            .foregroundStyle(isPrimary || configuration.isPressed ? Color.white : Color.primary)
            .background(
                configuration.isPressed
                    ? Color.accentColor.opacity(0.9)
                    : (isPrimary ? Color.accentColor.opacity(0.72) : Color.secondary.opacity(0.14)),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

private struct StatusBadge: View {
    let label: String
    let ready: Bool

    var body: some View {
        Label(label, systemImage: ready ? "checkmark.circle.fill" : "minus.circle")
            .font(.callout.weight(.medium))
            .foregroundStyle(ready ? .green : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.quaternary, in: Capsule())
    }
}

private struct PlaybackBlockerView: View {
    let failure: PlaybackFailure
    let onRetry: () -> Void
    let onRecheck: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: failure.kind == .openFailed ? "exclamationmark.triangle" : "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(failure.title)
                .font(.title3.weight(.semibold))
            Text(failure.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 460)
            HStack(spacing: 10) {
                switch failure.kind {
                case .decryptionBackendMissing:
                    Link(destination: BackendLocator.makeMKVDownloadURL) {
                        Label("获取 MakeMKV", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.glassProminent)
                    Button("重新检测", systemImage: "arrow.clockwise", action: onRecheck)
                        .buttonStyle(.glass)
                case .decryptionBackendInactive:
                    Button("打开 MakeMKV", systemImage: "arrow.up.forward.app") {
                        if let app = BackendLocator.makeMKVLibrary?
                            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() {
                            NSWorkspace.shared.open(app)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    Button("重新检测", systemImage: "arrow.clockwise", action: onRecheck)
                        .buttonStyle(.glass)
                case .openFailed:
                    Button("重试", systemImage: "arrow.clockwise", action: onRetry)
                        .buttonStyle(.glassProminent)
                }
            }
            .controlSize(.large)
        }
        .foregroundStyle(.primary)
        .padding(28)
    }
}
