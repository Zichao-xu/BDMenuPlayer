import AppKit
import SwiftUI

/// The window is the picture. Everything else lives in the auto-hiding
/// control bar or its popovers.
struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black
            if let disc = model.selectedDisc {
                PlayerSurfaceView(model: model, disc: disc)
            } else {
                EmptyDiscView(isScanning: model.isScanning, onRefresh: { model.refreshDiscs() })
            }
        }
        .overlay(alignment: .top) { WindowDragStrip() }
        .ignoresSafeArea()
        .frame(minWidth: 640, minHeight: 360)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            model.playback.didEnterFullScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            model.playback.didExitFullScreen()
        }
    }
}

private struct EmptyDiscView: View {
    let isScanning: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if isScanning {
                ProgressView().controlSize(.large)
                Text("正在读取光盘…")
            } else {
                Image(systemName: "opticaldisc").font(.system(size: 44))
                Text("插入蓝光光盘")
                    .font(.title3.weight(.semibold))
                Button("重新扫描", systemImage: "arrow.clockwise", action: onRefresh)
                    .buttonStyle(.glass)
            }
        }
        .foregroundStyle(.secondary)
    }
}

/// Invisible strip along the top edge so the title-bar-less window can be moved.
private struct WindowDragStrip: View {
    var body: some View {
        Color.clear
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }
}

private struct PlayerSurfaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var playback: PlaybackController
    let disc: DiscVolume

    @State private var showsControls = false
    @State private var hideTask: Task<Void, Never>?
    @State private var controlsPinned = false

    init(model: AppModel, disc: DiscVolume) {
        self.model = model
        self.playback = model.playback
        self.disc = disc
    }

    /// A failure from the last attempt, or one that is already certain from
    /// the disc probe, so the user sees it before pressing Play.
    private var blocker: PlaybackFailure? {
        if let failure = playback.failure { return failure }
        if disc.info.needsDecryptionBackend {
            return .decryption(backendInstalled: BackendLocator.makeMKVLibrary != nil)
        }
        return nil
    }

    var body: some View {
        ZStack {
            VideoSurfaceView(controller: playback)
            MouseActivityView(onActivity: revealControls, onExit: { hideControls(after: .zero) })

            if !playback.isSessionActive {
                if let blocker {
                    PlaybackBlockerView(failure: blocker, onRetry: model.playSelectedDisc, onRecheck: model.recheckBackend)
                } else {
                    VStack(spacing: 12) {
                        Text(disc.info.displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Button("播放光盘菜单", systemImage: "play.fill", action: model.playSelectedDisc)
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.return, modifiers: [.command])
                    }
                }
            } else if playback.isOpening {
                ProgressView().controlSize(.large).allowsHitTesting(false)
            }

            if !playback.subtitleLines.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    ForEach(Array(playback.subtitleLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: index == 0 ? 30 : 38, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black, radius: 2, x: 0, y: 2)
                            .padding(.horizontal, 12)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 34)
                .allowsHitTesting(false)
            }

            if playback.isSessionActive, showsControls {
                PlayerControlsBar(
                    model: model,
                    playback: playback,
                    disc: disc,
                    onPinnedChanged: { pinned in
                        controlsPinned = pinned
                        pinned ? hideTask?.cancel() : hideControls(after: .seconds(2))
                    }
                )
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onChange(of: showsControls) { _, visible in setWindowChromeVisible(visible || !playback.isSessionActive) }
        .onChange(of: playback.isSessionActive) { _, active in setWindowChromeVisible(!active || showsControls) }
        .onDisappear {
            hideTask?.cancel()
            setWindowChromeVisible(true)
        }
    }

    private func revealControls() {
        if !showsControls {
            withAnimation(.easeOut(duration: 0.15)) { showsControls = true }
        }
        hideControls(after: .seconds(2))
    }

    private func hideControls(after delay: Duration) {
        hideTask?.cancel()
        guard !controlsPinned else { return }
        hideTask = Task { @MainActor in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, !controlsPinned else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showsControls = false }
            if playback.isSessionActive { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }

    /// Traffic-light buttons fade with the controls so nothing sits on the picture.
    private func setWindowChromeVisible(_ visible: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.superview?.animator().alphaValue = visible ? 1 : 0
        }
    }
}

private struct PlayerControlsBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var playback: PlaybackController
    let disc: DiscVolume
    let onPinnedChanged: (Bool) -> Void

    @State private var hovering = false
    @State private var showsMenuPad = false
    @State private var showsInfo = false

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Button {
                    playback.togglePause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.glassProminent)
                .help("播放/暂停 · Space")

                barButton("gobackward.10", "后退 10 秒 · J") { playback.seek(by: -10) }
                    .disabled(!playback.isMainFeatureActive)
                barButton("goforward.10", "前进 10 秒 · L") { playback.seek(by: 10) }
                    .disabled(!playback.isMainFeatureActive)

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

                barButton(playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", "静音 · M") {
                    playback.toggleMute()
                }
                Slider(value: Binding(get: { playback.volume }, set: { playback.setVolume($0) }), in: 0...1.25)
                    .frame(width: 70)

                // The disc's popup menu is closed with the key that opens it —
                // the "back" of a BD remote.
                barButton("menucard", "打开/关闭光盘菜单 · P 或 Delete") { playback.navigate(.popup) }
                barButton("dpad", "菜单方向键（键盘方向键 + Return 也可）") { showsMenuPad.toggle() }
                    .popover(isPresented: $showsMenuPad, arrowEdge: .top) {
                        HStack(spacing: 14) {
                            MenuDirectionPad(playback: playback, enableShortcuts: false)
                            Button {
                                playback.navigate(.popup)
                                showsMenuPad = false
                            } label: {
                                Label("关闭菜单", systemImage: "chevron.down.circle")
                            }
                        }
                        .padding(12)
                    }
                barButton(
                    playback.hasSubtitle ? "captions.bubble.fill" : "captions.bubble",
                    playback.hasSubtitle ? "更换外挂字幕 · ⇧⌘O" : "选择外挂字幕 · ⇧⌘O",
                    action: model.chooseSubtitle
                )
                barButton("info.circle", "光盘信息") { showsInfo.toggle() }
                    .popover(isPresented: $showsInfo, arrowEdge: .top) {
                        DiscInfoView(model: model, disc: disc)
                    }
                barButton(playback.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", "全屏 · F") {
                    playback.toggleFullScreen()
                }
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 900)
            .glassEffect(.regular.tint(.black.opacity(0.25)), in: .capsule)
            .onHover { hovering = $0; updatePin() }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .onChange(of: showsMenuPad) { _, _ in updatePin() }
        .onChange(of: showsInfo) { _, _ in updatePin() }
    }

    private func updatePin() {
        onPinnedChanged(hovering || showsMenuPad || showsInfo)
    }

    private func barButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .help(help)
    }

    private func time(_ milliseconds: Int64) -> String {
        let total = max(0, milliseconds / 1000)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct DiscInfoView: View {
    @ObservedObject var model: AppModel
    let disc: DiscVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.discs.count > 1 {
                Picker("光盘", selection: $model.selectedDiscID) {
                    ForEach(model.discs) { Text($0.info.displayName).tag(Optional($0.id)) }
                }
            } else {
                Text(disc.info.displayName).font(.headline)
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                row("标题", "\(disc.info.titleCount) 个 · \(disc.info.hdmvTitleCount) HDMV · \(disc.info.bdjTitleCount) BD-J")
                row("菜单", [disc.info.hasFirstPlay ? "First Play" : nil, disc.info.hasTopMenu ? "Top Menu" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                row("AACS", disc.info.usesAACS ? (disc.info.aacsReady ? "已解密" : "缺少解密后端") : "未使用")
                row("BD+", disc.info.usesBDPlus ? (disc.info.bdplusReady ? "已解密" : "缺少解密后端") : "未使用")
                row("libbluray", disc.info.libblurayVersion)
                row("位置", disc.mountURL.path)
            }
            .font(.callout)
            Divider()
            HStack {
                Text(model.externalSubtitleLabel ?? "无外挂字幕")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if model.externalSubtitle != nil { Button("清除") { model.clearSubtitle() } }
                Button("选择…") { model.chooseSubtitle() }
            }
            if let error = model.subtitleError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Text(model.playback.status).foregroundStyle(.secondary).font(.caption)
                Spacer()
                Button("停止", systemImage: "stop.fill") { model.playback.stop() }
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
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
