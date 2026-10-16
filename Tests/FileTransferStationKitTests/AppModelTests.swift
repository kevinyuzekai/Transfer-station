import XCTest
@testable import FileTransferStationKit

/// 覆盖中转站与剪贴板历史的核心规则：去重、容量淘汰、置顶保护、工具方法。
final class AppModelTests: XCTestCase {

    /// 每个用例都从干净状态开始，避免真实持久化文件相互影响。
    private func makeModel() -> AppModel {
        let model = AppModel()
        model.shelf = []
        model.clips = []
        model.settings = Settings()
        return model
    }

    private func textItem(_ value: String) -> Item {
        Item(type: .text,
             name: value,
             source: "系统剪贴板",
             contentRef: value,
             sizeText: "文本",
             dedupKey: "text:" + value)
    }

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fts-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 容量与淘汰

    func testEvictionDropsOldestUnpinnedEntries() {
        let model = makeModel()
        model.settings.historyLimit = 2
        model.clips = [textItem("c"), textItem("b"), textItem("a")]
        model.evictIfNeeded()
        XCTAssertEqual(model.clips.count, 2)
        XCTAssertEqual(model.clips.map { $0.contentRef }, ["c", "b"])
    }

    func testPinnedEntriesSurviveEviction() {
        let model = makeModel()
        model.settings.historyLimit = 1
        model.clips = [textItem("c"), textItem("b"), textItem("a")]
        model.clips[2].pinned = true
        model.evictIfNeeded()
        XCTAssertEqual(model.clips.count, 2)
        XCTAssertTrue(model.clips.contains { $0.pinned })
        XCTAssertEqual(model.clips.map { $0.contentRef }.sorted(), ["a", "c"])
    }

    func testAddClipEvictsImmediately() {
        let model = makeModel()
        model.settings.historyLimit = 2
        model.addClip(textItem("a"))
        model.addClip(textItem("b"))
        model.addClip(textItem("c"))
        XCTAssertEqual(model.clips.count, 2)
        XCTAssertFalse(model.clips.contains { $0.contentRef == "a" })
    }

    // MARK: - 去重

    func testLatestKeyDedupe() {
        let model = makeModel()
        XCTAssertFalse(model.isLatestKey("text:x"))
        model.addClip(textItem("x"))
        XCTAssertTrue(model.isLatestKey("text:x"))
        XCTAssertFalse(model.isLatestKey("text:y"))
    }

    // MARK: - 中转站

    func testAddFilesToShelfCapturesMetadataAndDedupes() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: file)

        let model = makeModel()
        model.addFilesToShelf([file])
        XCTAssertEqual(model.shelf.count, 1)
        XCTAssertEqual(model.shelf[0].type, .file)
        XCTAssertEqual(model.shelf[0].name, "note.txt")
        XCTAssertTrue(model.shelf[0].isAvailable)

        model.addFilesToShelf([file])
        XCTAssertEqual(model.shelf.count, 1, "同一路径应去重")
    }

    func testShelfItemBecomesUnavailableWhenFileIsDeleted() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("temp.txt")
        try Data("x".utf8).write(to: file)
        let item = Item(type: .file,
                        name: "temp.txt",
                        source: file.path,
                        contentRef: file.path,
                        sizeText: "1 KB",
                        dedupKey: "file:" + file.path)
        XCTAssertTrue(item.isAvailable)
        try FileManager.default.removeItem(at: file)
        XCTAssertFalse(item.isAvailable)
    }

    // MARK: - 工具方法

    func testUniqueURLSuffixesOnCollision() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("note.txt")
        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = AppModel.uniqueURL(first)
        XCTAssertEqual(second.lastPathComponent, "note (1).txt")
        FileManager.default.createFile(atPath: second.path, contents: Data())
        XCTAssertEqual(AppModel.uniqueURL(first).lastPathComponent, "note (2).txt")
    }

    func testImageFileDetection() {
        XCTAssertTrue(Item.isImageFile("shot.PNG"))
        XCTAssertTrue(Item.isImageFile("photo.heic"))
        XCTAssertFalse(Item.isImageFile("archive.zip"))
    }

    // MARK: - 预览与反馈

    func testToastIsSet() {
        let model = makeModel()
        model.showToast("已暂存 2 个文件")
        XCTAssertEqual(model.toast, "已暂存 2 个文件")
    }

    func testPreviewOpensAndCloses() {
        let model = makeModel()
        let item = textItem("hello")
        XCTAssertNil(model.previewItem)
        model.openPreview(item)
        XCTAssertEqual(model.previewItem?.id, item.id)
        model.closePreview()
        XCTAssertNil(model.previewItem)
    }
}
