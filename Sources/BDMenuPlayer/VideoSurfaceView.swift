import AppKit
import SwiftUI

final class VLCVideoHostView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        autoresizesSubviews = true
    }

    required init?(coder: NSCoder) { nil }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        fitVideoSubview(subview)
    }

    override func layout() {
        super.layout()
        subviews.forEach(fitVideoSubview)
    }

    private func fitVideoSubview(_ subview: NSView) {
        subview.frame = bounds
        subview.autoresizingMask = [.width, .height]
    }
}

struct VideoSurfaceView: NSViewRepresentable {
    let controller: PlaybackController

    func makeNSView(context: Context) -> NSView {
        controller.persistentVideoView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.attachPersistentVideoView()
    }
}

struct MouseActivityView: NSViewRepresentable {
    let onActivity: () -> Void

    func makeNSView(context: Context) -> MouseTrackingView {
        let view = MouseTrackingView()
        view.onActivity = onActivity
        return view
    }

    func updateNSView(_ nsView: MouseTrackingView, context: Context) {
        nsView.onActivity = onActivity
    }
}

final class MouseTrackingView: NSView {
    var onActivity: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        onActivity?()
    }
}
