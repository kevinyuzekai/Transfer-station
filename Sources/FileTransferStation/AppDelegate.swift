import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private var cancellables = Set<AnyCancellable>()
    private var ballWindow: FloatingPanel!
    private var panelWindow: FloatingPanel!
    private var ballHost: BallHostingView!
    private var panelHost: NSHostingView<AnyView>!
    private var clipTimer: Timer?
    private var lastChangeCount = 0
    private var ignoreChangeCount = -1
    private let hotKey = HotKeyManager()
    private let ballUI = BallUIState()
    private var dragStart: NSPoint?
    private var outsideMonitor: Any?

    private let ballSize = NSSize(width: 88, height: 88)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        model.onDidWritePasteboard = { [weak self] in
            self?.ignoreChangeCount = NSPasteboard.general.changeCount
        }
        model.onResetBall = { [weak self] in self?.resetBallPosition() }
        model.onAutoLaunchChange = { [weak self] in self?.applyAutoLaunch() }

        setupBallWindow()
        setupPanelWindow()
        observeMode()
        startClipboardMonitor()
        registerHotKey()
        installOutsideClickMonitor()
        applyAutoLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipTimer?.invalidate()
        if let monitor = outsideMonitor { NSEvent.removeMonitor(monitor) }
        model.persist()
    }

    // MARK: - Windows

    private func setupBallWindow() {
        let window = FloatingPanel(contentRect: NSRect(origin: .zero, size: ballSize),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered,
                                   defer: false)
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false

        let host = BallHostingView(rootView: BallView(
            model: model,
            ui: ballUI,
            onDragChanged: { [weak self] translation in self?.ballDragChanged(translation) },
            onDragEnded: { [weak self] translation in self?.ballDragEnded(translation) }
        ))
        host.onDrop = { [weak self] urls in self?.model.addFilesToShelf(urls) }
        host.onHover = { [weak self] hovering in self?.ballUI.dropping = hovering }
        window.contentView = host
        ballHost = host

        if let position = model.ballPosition() {
            window.setFrameOrigin(NSPoint(x: position.x, y: position.y))
        } else {
            window.setFrameOrigin(defaultBallOrigin())
        }
        window.orderFrontRegardless()
        ballWindow = window
    }

    private func setupPanelWindow() {
        let window = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered,
                                   defer: false)
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false

        let host = NSHostingView(rootView: AnyView(PanelRoot(model: model)))
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 540)
        window.contentView = host
        panelHost = host
        panelWindow = window
    }

    private func defaultBallOrigin() -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - ballSize.width - 24, y: visible.minY + 24)
    }

    // MARK: - Panel layout

    private func observeMode() {
        model.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in self?.layoutPanel(for: mode) }
            .store(in: &cancellables)
    }

    private func panelSize(for mode: UIMode) -> NSSize {
        switch mode {
        case .menu: return NSSize(width: 240, height: 220)
        case .shelf: return NSSize(width: 420, height: 540)
        case .clip: return NSSize(width: 420, height: 540)
        case .settings: return NSSize(width: 420, height: 430)
        case .collapsed: return NSSize(width: 1, height: 1)
        }
    }

    private func layoutPanel(for mode: UIMode) {
        guard let window = panelWindow else { return }
        guard mode != .collapsed else {
            window.orderOut(nil)
            return
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var size = panelSize(for: mode)
        size.height = min(size.height, visible.height - 40)
        size.width = min(size.width, visible.width - 40)

        window.setContentSize(size)
        panelHost.frame = NSRect(origin: .zero, size: size)

        let ball = ballWindow.frame
        var x = ball.maxX - size.width
        var y = ball.maxY + 8
        if y + size.height > visible.maxY - 8 {
            y = ball.minY - size.height - 8
        }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.orderFrontRegardless()
    }

    // MARK: - Ball interaction

    private func ballDragChanged(_ translation: CGSize) {
        if dragStart == nil { dragStart = ballWindow.frame.origin }
        guard let start = dragStart else { return }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: start.x + translation.width, y: start.y - translation.height)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - ballWindow.frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - ballWindow.frame.height)
        ballWindow.setFrameOrigin(origin)
        if model.mode != .collapsed { layoutPanel(for: model.mode) }
    }

    private func ballDragEnded(_ translation: CGSize) {
        dragStart = nil
        let moved = abs(translation.width) > 3 || abs(translation.height) > 3
        if moved {
            let origin = ballWindow.frame.origin
            model.setBallPosition(Double(origin.x), Double(origin.y))
            if model.mode != .collapsed { layoutPanel(for: model.mode) }
        } else {
            toggleMenu()
        }
    }

    private func toggleMenu() {
        model.mode = (model.mode == .collapsed) ? .menu : .collapsed
    }

    private func resetBallPosition() {
        let origin = defaultBallOrigin()
        ballWindow.setFrameOrigin(origin)
        model.setBallPosition(Double(origin.x), Double(origin.y))
        if model.mode != .collapsed { layoutPanel(for: model.mode) }
    }

    // MARK: - Clipboard

    private func startClipboardMonitor() {
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pollClipboard()
        }
        RunLoop.main.add(timer, forMode: .common)
        clipTimer = timer
    }

    private func pollClipboard() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        if count == lastChangeCount { return }
        lastChangeCount = count
        if count == ignoreChangeCount { return }
        model.captureFromPasteboard()
    }

    // MARK: - Hotkey & outside click

    private func registerHotKey() {
        hotKey.register(keyCode: UInt32(kVK_ANSI_V),
                        modifiers: UInt32(controlKey | shiftKey)) { [weak self] in
            self?.toggleMenu()
        }
    }

    private func installOutsideClickMonitor() {
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            if self.model.mode != .collapsed { self.model.mode = .collapsed }
        }
    }

    private func applyAutoLaunch() {
        LaunchAtLogin.setEnabled(model.settings.autoLaunch)
    }
}
