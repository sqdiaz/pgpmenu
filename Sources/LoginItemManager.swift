import Foundation

struct LoginItemManager {
    private static let label = "com.pgpmenu.app"
    private static let launchAgentDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
    private static var plistURL: URL {
        launchAgentDir.appendingPathComponent("\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func enable() {
        let executablePath = Bundle.main.executablePath
            ?? "/Applications/PGPMenu.app/Contents/MacOS/PGPMenu"
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true
        ]
        try? FileManager.default.createDirectory(at: launchAgentDir, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: plistURL)
        }
    }

    static func disable() {
        try? FileManager.default.removeItem(at: plistURL)
    }
}
