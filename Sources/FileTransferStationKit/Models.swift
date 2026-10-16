import Foundation

/// A single reusable content record shared by the shelf (中转站) and the
/// clipboard history (剪贴板历史). See PRD "共享业务对象：条目（Item）".
enum ItemType: String, Codable, CaseIterable {
    case file
    case text
    case image
}

struct Item: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: ItemType
    /// 名称：文件名；文本取前若干字符作为标题。
    var name: String
    /// 来源：原文件完整路径（文件型）；"系统剪贴板"（复制型）。
    var source: String
    /// 内容引用：文件路径 / 图片落盘路径 / 文本内容。
    var contentRef: String
    /// 大小 / 摘要：文件大小、文本字符数、图片尺寸。
    var sizeText: String
    /// 加入 / 复制时间，用于排序与淘汰。
    var createdAt: Date = Date()
    /// 置顶：固定在列表顶部且不参与淘汰。
    var pinned: Bool = false
    /// 去重键。
    var dedupKey: String

    /// 可用性：仅文件型与图片型需要校验引用是否仍存在。
    var isAvailable: Bool {
        switch type {
        case .text:
            return true
        case .file, .image:
            return FileManager.default.fileExists(atPath: contentRef)
        }
    }

    /// 拖出 / 定位使用的 URL（文本型没有）。
    var url: URL? {
        type == .text ? nil : URL(fileURLWithPath: contentRef)
    }

    var typeLabel: String {
        switch type {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    /// 是否可打开大图 / 全文预览。
    var isPreviewable: Bool {
        switch type {
        case .image: return FileManager.default.fileExists(atPath: contentRef)
        case .text: return true
        case .file: return Self.isImageFile(name)
        }
    }

    static func isImageFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "webp"].contains(ext)
    }
}

enum DragOutMode: String, Codable {
    case copy
    case move
}

struct Settings: Codable, Equatable {
    /// 剪贴板历史上限，默认 500 条。
    var historyLimit: Int = 500
    /// 开机自动启动，默认开。
    var autoLaunch: Bool = true
    /// 监听剪贴板，默认开。
    var monitorClipboard: Bool = true
    /// 全局快捷键：Carbon keyCode（默认 kVK_ANSI_V = 9）。
    var hotkeyKeyCode: Int = 9
    /// 全局快捷键：Carbon 修饰键（controlKey 4096 | shiftKey 512）。
    var hotkeyModifiers: Int = 4608
    /// 全局快捷键展示文案。
    var hotkeyLabel: String = "Ctrl + Shift + V"
    /// 拖出默认行为，默认复制。
    var dragOutMode: DragOutMode = .copy
}

/// 面板导航状态。
enum UIMode {
    case collapsed
    case menu
    case shelf
    case clip
    case settings
}

struct PersistedData: Codable {
    var shelf: [Item] = []
    var clips: [Item] = []
    var settings: Settings = Settings()
    var ballX: Double? = nil
    var ballY: Double? = nil
}
