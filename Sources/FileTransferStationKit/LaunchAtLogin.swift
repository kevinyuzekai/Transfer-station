import Foundation

/// 开机自动启动：写入 / 移除 ~/Library/LaunchAgents 下的 LaunchAgent plist。
enum LaunchAtLogin {
    static let label = "com.kevin.transferstation"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            guard let exe = Bundle.main.executablePath else { return }
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "KeepAlive": false
            ]
            let url = plistURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                              format: .xml,
                                                              options: 0) {
                try? data.write(to: url)
            }
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}
