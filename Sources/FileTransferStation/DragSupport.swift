import AppKit
import SwiftUI

/// A borderless floating panel that can become key (so search fields receive
/// typing) without activating the whole app / stealing focus from the target app.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Observable drop-hover state shared between the AppKit host view and the ball.
final class BallUIState: ObservableObject {
    @Published var dropping = false
}

/// NSHostingView subclass that turns the ball window into an NSDraggingDestination
/// so files can be dropped onto the floating ball (F2).
final class BallHostingView: NSHostingView<BallView> {
    var onDrop: (([URL]) -> Void)?
    var onHover: ((Bool) -> Void)?

    required init(rootView: BallView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onHover?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHover?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onHover?(false)
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let pb = sender.draggingPasteboard
        return (pb.readObjects(forClasses: [NSURL.self],
                               options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}
