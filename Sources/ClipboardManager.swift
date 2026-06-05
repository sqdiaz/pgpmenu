import Cocoa
import UserNotifications

class ClipboardManager {
    static let shared = ClipboardManager()

    enum ClearTimeout: Int, CaseIterable {
        case fifteenSeconds = 15
        case thirtySeconds = 30
        case sixtySeconds = 60
        case never = 0

        var label: String {
            switch self {
            case .fifteenSeconds: return "15 seconds"
            case .thirtySeconds: return "30 seconds"
            case .sixtySeconds: return "60 seconds"
            case .never: return "Never"
            }
        }
    }

    private var clearTimer: DispatchSourceTimer?
    private var trackedChangeCount: Int?
    private let queue = DispatchQueue(label: "com.pgpmenu.clipboard-clear")

    var timeout: ClearTimeout = .thirtySeconds

    /// Place sensitive content on the clipboard and schedule auto-clear.
    func setSensitive(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        trackedChangeCount = pasteboard.changeCount
        scheduleClear()
    }

    /// Place non-sensitive content (ciphertext) on the clipboard without auto-clear.
    func setNonSensitive(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        cancelTimer()
    }

    /// Immediately clear the clipboard if we still own it.
    func clearNow() {
        cancelTimer()
        let pasteboard = NSPasteboard.general

        if let tracked = trackedChangeCount {
            guard pasteboard.changeCount == tracked else {
                trackedChangeCount = nil
                return
            }
        }

        pasteboard.clearContents()
        pasteboard.setString("", forType: .string)
        trackedChangeCount = nil
        notifyCleared()
    }

    /// Force-clear regardless of ownership (for manual "Clear Clipboard Now").
    func forceClear() {
        cancelTimer()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("", forType: .string)
        trackedChangeCount = nil
        notifyCleared()
    }

    // MARK: - Private

    private func scheduleClear() {
        cancelTimer()
        guard timeout != .never else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(timeout.rawValue))
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.clearNow()
            }
        }
        timer.resume()
        clearTimer = timer
    }

    private func cancelTimer() {
        clearTimer?.cancel()
        clearTimer = nil
    }

    private func notifyCleared() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = "Clipboard Cleared"
        content.body = "Sensitive data removed from clipboard"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
