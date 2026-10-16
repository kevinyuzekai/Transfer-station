import AppKit
import Combine
import Foundation

/// Central state + business logic for the app. Owns the shelf, the clipboard
/// history and the persisted settings, and is observed by every SwiftUI view.
final class AppModel: ObservableObject {
    @Published var shelf: [Item] = []
    @Published var clips: [Item] = []
    @Published var settings: Settings = Settings()
    @Published var mode: UIMode = .collapsed
    /// 当前预览的条目（图片大图 / 文本全文）。
    @Published var previewItem: Item?
    /// 悬浮球旁的瞬时反馈文案。
    @Published var toast: String?

    // Hooks wired up by AppDelegate for platform side effects.
    var onDidWritePasteboard: (() -> Void)?
    var onResetBall: (() -> Void)?
    var onAutoLaunchChange: (() -> Void)?
    var onHotKeyChanged: (() -> Void)?

    private let baseDir: URL
    private let imagesDir: URL
    private let dataURL: URL
    private var persisted = PersistedData()
    private var toastWorkItem: DispatchWorkItem?

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        baseDir = appSupport.appendingPathComponent("FileTransferStation", isDirectory: true)
        imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        dataURL = baseDir.appendingPathComponent("data.json")
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: dataURL),
              let decoded = try? JSONDecoder().decode(PersistedData.self, from: data) else { return }
        persisted = decoded
        shelf = decoded.shelf
        clips = decoded.clips
        settings = decoded.settings
    }

    func persist() {
        persisted.shelf = shelf
        persisted.clips = clips
        persisted.settings = settings
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        do {
            try data.write(to: dataURL, options: .atomic)
        } catch {
            NSLog("FileTransferStation: persist failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Toast feedback

    func showToast(_ message: String) {
        toast = message
        toastWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: work)
    }

    // MARK: - Preview

    func openPreview(_ item: Item) { previewItem = item }
    func closePreview() { previewItem = nil }

    // MARK: - Ball position

    func ballPosition() -> (x: Double, y: Double)? {
        guard let x = persisted.ballX, let y = persisted.ballY else { return nil }
        return (x, y)
    }

    func setBallPosition(_ x: Double, _ y: Double) {
        persisted.ballX = x
        persisted.ballY = y
        persist()
    }

    // MARK: - Shelf (中转站)

    /// F2 · 拖入暂存：只记录路径引用，同一路径去重。
    func addFilesToShelf(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            let path = url.path
            let key = "file:" + path
            if let idx = shelf.firstIndex(where: { $0.dedupKey == key }) {
                var item = shelf[idx]
                item.createdAt = Date()
                item.name = url.lastPathComponent
                item.contentRef = path
                item.source = path
                shelf.remove(at: idx)
                shelf.insert(item, at: 0)
            } else {
                let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                let bytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                let item = Item(type: .file,
                                name: url.lastPathComponent,
                                source: path,
                                contentRef: path,
                                sizeText: Self.formatSize(bytes),
                                dedupKey: key)
                shelf.insert(item, at: 0)
            }
        }
        persist()
        showToast("已暂存 \(urls.count) 个文件")
    }

    func togglePinShelf(_ item: Item) {
        guard let idx = shelf.firstIndex(where: { $0.id == item.id }) else { return }
        shelf[idx].pinned.toggle()
        persist()
        showToast(shelf[idx].pinned ? "已置顶" : "已取消置顶")
    }

    func removeShelf(_ item: Item) {
        shelf.removeAll { $0.id == item.id }
        persist()
        showToast("已移出中转站（原文件未删除）")
    }

    /// F10 · 清空中转站（不删除任何原文件）。
    func clearShelf() {
        shelf.removeAll()
        persist()
        showToast("已清空中转站")
    }

    /// F6 · 重新定位失效文件。
    func relocate(_ item: Item) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "重新定位"
        panel.message = "选择该文件的新位置"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let idx = shelf.firstIndex(where: { $0.id == item.id }) else { return }
        shelf[idx].contentRef = url.path
        shelf[idx].source = url.path
        shelf[idx].name = url.lastPathComponent
        shelf[idx].dedupKey = "file:" + url.path
        persist()
        showToast("已重新定位并恢复可用")
    }

    func reveal(_ item: Item) {
        guard let url = item.url, FileManager.default.fileExists(atPath: url.path) else {
            showToast("原文件已不存在，无法定位")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        showToast("已在访达中定位原文件")
    }

    /// F5 · 拖出到目标目录（默认复制）。
    func copyOut(_ item: Item) { transfer(item, move: false) }
    /// F5 · 移动到目标目录。
    func moveOut(_ item: Item) { transfer(item, move: true) }

    private func transfer(_ item: Item, move: Bool) {
        guard let src = item.url, FileManager.default.fileExists(atPath: src.path) else {
            showToast("原文件已不存在，无法\(move ? "移动" : "复制")")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = move ? "移动至此" : "复制至此"
        panel.message = "选择目标文件夹"
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        var dest = dir.appendingPathComponent(src.lastPathComponent)
        if !move && FileManager.default.fileExists(atPath: dest.path) {
            dest = Self.uniqueURL(dest)
        }
        do {
            if move {
                try FileManager.default.moveItem(at: src, to: dest)
                removeShelf(item)
                showToast("已移动到 \(dir.lastPathComponent)")
            } else {
                try FileManager.default.copyItem(at: src, to: dest)
                showToast("已复制到 \(dir.lastPathComponent)")
            }
        } catch {
            showToast("操作失败：\(error.localizedDescription)")
        }
    }

    static func uniqueURL(_ url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var i = 1
        while true {
            let name = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    // MARK: - Clipboard history (剪贴板历史)

    /// F7 · 剪贴板捕获。
    func captureFromPasteboard() {
        guard settings.monitorClipboard else { return }
        let pb = NSPasteboard.general
        let types = pb.types ?? []

        // 文件列表
        if types.contains(.fileURL) {
            let urls = (pb.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            if !urls.isEmpty {
                for url in urls { addClipFile(url) }
                persist()
                return
            }
        }

        // 图片
        if types.contains(.tiff) || types.contains(.png) {
            if let image = NSImage(pasteboard: pb),
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let key = "img:" + Self.fnv(png)
                if isLatestKey(key) {
                    touchLatest()
                } else {
                    let file = imagesDir.appendingPathComponent("\(UUID().uuidString).png")
                    try? png.write(to: file)
                    let dims = "\(Int(image.size.width))×\(Int(image.size.height))"
                    addClip(Item(type: .image,
                                 name: "截图 \(Self.timeStamp()).png",
                                 source: "系统剪贴板",
                                 contentRef: file.path,
                                 sizeText: "图片 · \(dims)",
                                 dedupKey: key))
                }
                persist()
                return
            }
        }

        // 文本
        if types.contains(.string), let text = pb.string(forType: .string), !text.isEmpty {
            let key = "text:" + text
            if isLatestKey(key) {
                touchLatest()
            } else {
                let title = String(text.prefix(40))
                addClip(Item(type: .text,
                             name: title,
                             source: "系统剪贴板",
                             contentRef: text,
                             sizeText: "文本 · \(text.count) 字符",
                             dedupKey: key))
            }
            persist()
            return
        }
    }

    private func addClipFile(_ url: URL) {
        let path = url.path
        let key = "file:" + path
        if isLatestKey(key) {
            touchLatest()
            return
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let bytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        addClip(Item(type: .file,
                     name: url.lastPathComponent,
                     source: "系统剪贴板",
                     contentRef: path,
                     sizeText: "文件 · " + Self.formatSize(bytes),
                     dedupKey: key))
    }

    /// 插入一条剪贴板记录（内部可见，便于单元测试）。
    func addClip(_ item: Item) {
        clips.insert(item, at: 0)
        evictIfNeeded()
    }

    func isLatestKey(_ key: String) -> Bool {
        clips.first?.dedupKey == key
    }

    private func touchLatest() {
        if !clips.isEmpty { clips[0].createdAt = Date() }
    }

    /// F10 / 规则 · 容量与淘汰：超出上限时淘汰最旧的非置顶条目。
    func evictIfNeeded() {
        let nonPinned = clips.filter { !$0.pinned }
        guard nonPinned.count > settings.historyLimit else { return }
        var overflow = nonPinned.count - settings.historyLimit
        var i = clips.count - 1
        while i >= 0 && overflow > 0 {
            if !clips[i].pinned {
                let removed = clips.remove(at: i)
                deleteImageIfNeeded(removed)
                overflow -= 1
            }
            i -= 1
        }
    }

    func togglePinClip(_ item: Item) {
        guard let idx = clips.firstIndex(where: { $0.id == item.id }) else { return }
        clips[idx].pinned.toggle()
        persist()
        showToast(clips[idx].pinned ? "已置顶" : "已取消置顶")
    }

    func removeClip(_ item: Item) {
        deleteImageIfNeeded(item)
        clips.removeAll { $0.id == item.id }
        persist()
        showToast("已移除该记录")
    }

    /// F10 · 清空剪贴板历史（含落盘图片）。
    func clearClips() {
        for item in clips { deleteImageIfNeeded(item) }
        clips.removeAll()
        persist()
        showToast("已清空剪贴板历史")
    }

    func deleteImageIfNeeded(_ item: Item) {
        guard item.type == .image else { return }
        try? FileManager.default.removeItem(atPath: item.contentRef)
    }

    /// F9 · 复制回剪贴板。
    func copyBack(_ item: Item) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text:
            pb.setString(item.contentRef, forType: .string)
        case .image:
            guard let image = NSImage(contentsOfFile: item.contentRef) else {
                showToast("图片文件已丢失")
                return
            }
            pb.writeObjects([image])
        case .file:
            guard FileManager.default.fileExists(atPath: item.contentRef) else {
                showToast("原文件已不存在，未写回")
                return
            }
            pb.writeObjects([URL(fileURLWithPath: item.contentRef) as NSURL])
        }
        onDidWritePasteboard?()
        showToast("已复制到剪贴板")
    }

    // MARK: - Settings (F11)

    func changeLimit(_ delta: Int) {
        settings.historyLimit = min(max(settings.historyLimit + delta, 10), 100000)
        evictIfNeeded()
        persist()
    }

    func setAutoLaunch(_ value: Bool) {
        settings.autoLaunch = value
        persist()
        onAutoLaunchChange?()
    }

    func setMonitor(_ value: Bool) {
        settings.monitorClipboard = value
        persist()
    }

    func setDragOut(_ value: DragOutMode) {
        settings.dragOutMode = value
        persist()
    }

    func setHotKey(keyCode: Int, modifiers: Int, label: String) {
        settings.hotkeyKeyCode = keyCode
        settings.hotkeyModifiers = modifiers
        settings.hotkeyLabel = label
        persist()
        onHotKeyChanged?()
    }

    func resetBallPosition() {
        onResetBall?()
    }

    // MARK: - Helpers

    static func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func timeStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return f.string(from: Date())
    }

    static func fnv(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
