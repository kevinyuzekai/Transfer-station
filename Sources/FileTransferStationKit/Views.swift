import AppKit
import SwiftUI

// MARK: - Palette

private let accent = Color(red: 0.25, green: 0.41, blue: 0.94)
private let accent2 = Color(red: 0.48, green: 0.33, blue: 0.94)

// MARK: - Floating ball (F1 / F2)

struct BallView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: BallUIState
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: (CGSize) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(LinearGradient(colors: [accent, accent2],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: accent.opacity(0.45), radius: 12, x: 0, y: 6)

            Image(systemName: "tray.full.fill")
                .font(.system(size: 26))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.shelf.count > 0 {
                Text("\(model.shelf.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white))
                    .offset(x: 4, y: -4)
            }
        }
        .frame(width: 88, height: 88)
        .scaleEffect(ui.dropping ? 1.16 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: ui.dropping)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { onDragChanged($0.translation) }
                .onEnded { onDragEnded($0.translation) }
        )
    }
}

// MARK: - Panel root

struct PanelRoot: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Group {
                switch model.mode {
                case .menu: MenuView(model: model)
                case .shelf: ShelfView(model: model)
                case .clip: ClipView(model: model)
                case .settings: SettingsView(model: model)
                case .collapsed: Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let preview = model.previewItem {
                PreviewOverlay(model: model, item: preview)
            }
        }
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct PanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(red: 0.08, green: 0.10, blue: 0.14, opacity: 0.98))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct PanelHeader: View {
    let title: String
    let meta: String
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { model.mode = .menu }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Text(meta)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))

            Button(action: { model.mode = .collapsed }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Preview overlay (图片大图 / 文本全文)

private struct PreviewOverlay: View {
    @ObservedObject var model: AppModel
    let item: Item

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.82))
                .onTapGesture { model.closePreview() }

            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .help(item.name)
                    Spacer(minLength: 0)
                    if item.type != .text {
                        IconButton(system: "arrow.up.forward.app") { model.reveal(item) }
                    }
                    IconButton(system: "doc.on.doc") { model.copyBack(item) }
                    IconButton(system: "xmark") { model.closePreview() }
                }

                content

                Text(item.sizeText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.type == .text {
            ScrollView {
                Text(item.contentRef)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        } else if let image = NSImage(contentsOfFile: item.contentRef) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        } else {
            Text("无法预览该内容，原文件可能已失效")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Toast (悬浮球旁瞬时反馈)

struct ToastView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(accent)
            Text(model.toast ?? "")
                .font(.system(size: 12.5))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color(red: 0.08, green: 0.10, blue: 0.14, opacity: 0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(3)
    }
}

// MARK: - Entry menu (F3)

private struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 4) {
            Text("入口")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            MenuRow(icon: "tray.full.fill", tint: accent,
                    title: "文件中转站", sub: "\(model.shelf.count) 个文件待取用") { model.mode = .shelf }
            MenuRow(icon: "doc.on.clipboard.fill", tint: Color(red: 0.12, green: 0.62, blue: 0.42),
                    title: "剪贴板历史", sub: "\(model.clips.count) 条记录") { model.mode = .clip }
            MenuRow(icon: "gearshape.fill", tint: Color(red: 0.45, green: 0.5, blue: 0.6),
                    title: "设置", sub: "上限 · 开关 · 快捷键") { model.mode = .settings }

            Divider().background(Color.white.opacity(0.1))

            MenuRow(icon: "power", tint: Color(red: 0.84, green: 0.27, blue: 0.27),
                    title: "退出", sub: "") { NSApp.terminate(nil) }

            Spacer(minLength: 0)
        }
        .padding(6)
    }
}

private struct MenuRow: View {
    let icon: String
    let tint: Color
    let title: String
    let sub: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.85)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13)).foregroundColor(.white)
                    if !sub.isEmpty {
                        Text(sub).font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
                    }
                }
                Spacer()
            }
            .padding(7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shelf (F4 / F5 / F6)

private struct ShelfView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var confirmingClear = false

    private var filtered: [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let base = trimmed.isEmpty
            ? model.shelf
            : model.shelf.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.source.localizedCaseInsensitiveContains(trimmed)
            }
        return base.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.createdAt > b.createdAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "文件中转站", meta: "\(model.shelf.count) 项", model: model)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                TextField("搜索文件名或路径…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundColor(.white)
                Button(confirmingClear ? "确认清空" : "清空") {
                    if confirmingClear {
                        model.clearShelf()
                        confirmingClear = false
                    } else {
                        confirmingClear = true
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundColor(confirmingClear ? Color(red: 0.9, green: 0.3, blue: 0.3) : .white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 7) {
                    if filtered.isEmpty {
                        Text(model.shelf.isEmpty
                             ? "中转站是空的\n把文件拖到悬浮球上即可暂存"
                             : "没有匹配的记录")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 12.5))
                            .foregroundColor(.white.opacity(0.38))
                            .padding(.vertical, 40)
                    } else {
                        ForEach(filtered) { item in
                            ShelfRow(model: model, item: item)
                        }
                    }
                }
                .padding(11)
            }
        }
    }
}

private struct ShelfRow: View {
    @ObservedObject var model: AppModel
    let item: Item

    var body: some View {
        let available = item.isAvailable
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 12.5))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if !available { TagBadge(text: "已失效", color: Color(red: 0.9, green: 0.3, blue: 0.3)) }
                }
                Text(available ? "\(item.sizeText) · \(item.source)" : "原文件已移动或删除")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                    .help(item.source)
                if !available {
                    HStack(spacing: 8) {
                        Button("重新定位") { model.relocate(item) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(accent)
                        Button("移除") { model.removeShelf(item) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                IconButton(system: item.pinned ? "star.fill" : "star", active: item.pinned) {
                    model.togglePinShelf(item)
                }
                if item.isPreviewable {
                    IconButton(system: "eye") { model.openPreview(item) }
                }
                IconButton(system: "folder") { model.reveal(item) }
                    .disabled(!available)
                IconButton(system: "xmark") { model.removeShelf(item) }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(item.pinned ? accent.opacity(0.14) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(item.pinned ? accent.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 1)
        )
        .opacity(available ? 1 : 0.72)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("复制到…") { model.copyOut(item) }
            Button("移动到…") { model.moveOut(item) }
            if !available {
                Divider()
                Button("重新定位") { model.relocate(item) }
            }
            Divider()
            Button("移除") { model.removeShelf(item) }
        }
    }

    private var iconName: String {
        let lower = item.name.lowercased()
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "photo" }
        if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") { return "film" }
        return "doc"
    }
}

// MARK: - Clipboard history (F8 / F9 / F10)

private struct ClipView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var filter = "全部"
    @State private var confirmingClear = false

    private var filtered: [Item] {
        var items = model.clips
        switch filter {
        case "文本": items = items.filter { $0.type == .text }
        case "图片": items = items.filter { $0.type == .image }
        case "文件": items = items.filter { $0.type == .file }
        default: break
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.contentRef.localizedCaseInsensitiveContains(trimmed)
            }
        }
        return items.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.createdAt > b.createdAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "剪贴板历史", meta: "显示 \(filtered.count) 条", model: model)

            if !model.settings.monitorClipboard {
                Text("剪贴板监听已关闭，新复制内容不再记录")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
            }

            HStack(spacing: 6) {
                ForEach(["全部", "文本", "图片", "文件"], id: \.self) { choice in
                    Button(choice) { filter = choice }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundColor(filter == choice ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(filter == choice ? accent : Color.white.opacity(0.07)))
                }
                Spacer()
                Button(confirmingClear ? "确认清空" : "清空") {
                    if confirmingClear {
                        model.clearClips()
                        confirmingClear = false
                    } else {
                        confirmingClear = true
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundColor(confirmingClear ? Color(red: 0.9, green: 0.3, blue: 0.3) : .white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                TextField("搜索文本内容…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 7) {
                    if filtered.isEmpty {
                        Text(model.clips.isEmpty
                             ? "暂无记录\n开启监听后自动记录"
                             : "没有匹配的记录")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 12.5))
                            .foregroundColor(.white.opacity(0.38))
                            .padding(.vertical, 40)
                    } else {
                        ForEach(filtered) { item in
                            ClipRow(model: model, item: item)
                        }
                    }
                }
                .padding(11)
            }
        }
    }
}

private struct ClipRow: View {
    @ObservedObject var model: AppModel
    let item: Item

    var body: some View {
        HStack(spacing: 10) {
            thumb
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TagBadge(text: item.typeLabel, color: typeColor)
                    Text(item.name)
                        .font(.system(size: 12.5))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text(item.sizeText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if item.isPreviewable {
                    IconButton(system: "eye") { model.openPreview(item) }
                }
                IconButton(system: item.pinned ? "star.fill" : "star", active: item.pinned) {
                    model.togglePinClip(item)
                }
                IconButton(system: "xmark") { model.removeClip(item) }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(item.pinned ? accent.opacity(0.14) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(item.pinned ? accent.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.copyBack(item) }
        .onDrag { dragProvider }
        .contextMenu {
            Button("复制回剪贴板") { model.copyBack(item) }
            if item.isPreviewable {
                Button("预览") { model.openPreview(item) }
            }
            if item.url != nil {
                Button("打开所在位置") { model.reveal(item) }
            }
            Divider()
            Button("移除") { model.removeClip(item) }
        }
    }

    /// 文本型条目也能被拖出（提供字符串）；文件 / 图片提供文件 URL。
    private var dragProvider: NSItemProvider {
        switch item.type {
        case .text:
            return NSItemProvider(object: item.contentRef as NSString)
        case .image, .file:
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
    }

    @ViewBuilder
    private var thumb: some View {
        if item.type == .image, let image = NSImage(contentsOfFile: item.contentRef) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: item.type == .file ? "doc.fill" : "text.alignleft")
                .font(.system(size: 15))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
        }
    }

    private var typeColor: Color {
        switch item.type {
        case .text: return accent
        case .image: return Color(red: 0.12, green: 0.62, blue: 0.42)
        case .file: return Color(red: 0.78, green: 0.5, blue: 0.1)
        }
    }
}

// MARK: - Settings (F11)

private struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "设置", meta: "即时生效", model: model)
            ScrollView {
                VStack(spacing: 0) {
                    settingRow("剪贴板历史上限", "超出后自动淘汰最旧的非置顶条目") {
                        HStack(spacing: 8) {
                            stepButton("−") { model.changeLimit(-50) }
                            Text("\(model.settings.historyLimit)")
                                .font(.system(size: 12.5))
                                .foregroundColor(.white)
                                .frame(minWidth: 44)
                            stepButton("＋") { model.changeLimit(50) }
                        }
                    }
                    toggleRow("开机自动启动",
                              binding: Binding(get: { model.settings.autoLaunch },
                                               set: { model.setAutoLaunch($0) }))
                    toggleRow("监听剪贴板",
                              binding: Binding(get: { model.settings.monitorClipboard },
                                               set: { model.setMonitor($0) }))
                    settingRow("全局快捷键", "展开 / 收起入口菜单") {
                        Text(model.settings.hotkeyLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    settingRow("拖出默认行为", "复制不改变原文件") {
                        Picker("", selection: Binding(get: { model.settings.dragOutMode },
                                                      set: { model.setDragOut($0) })) {
                            Text("复制").tag(DragOutMode.copy)
                            Text("移动").tag(DragOutMode.move)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    settingRow("悬浮球位置", "重置到主屏右下角") {
                        Button("重置") { model.resetBallPosition() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.1)))
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func stepButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
    }

    @ViewBuilder
    private func settingRow<C: View>(_ title: String, _ sub: String,
                                     @ViewBuilder trailing: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5)).foregroundColor(.white)
                    Text(sub).font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                trailing()
            }
            .padding(.vertical, 11)
            Divider().background(Color.white.opacity(0.07))
        }
    }

    @ViewBuilder
    private func toggleRow(_ title: String, binding: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 12.5)).foregroundColor(.white)
                Spacer()
                Toggle("", isOn: binding).labelsHidden()
            }
            .padding(.vertical, 11)
            Divider().background(Color.white.opacity(0.07))
        }
    }
}

// MARK: - Shared small views

private struct IconButton: View {
    let system: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12))
                .foregroundColor(active ? Color(red: 0.98, green: 0.78, blue: 0.2) : .white.opacity(0.7))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }
}
