import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let gpg = GPGWrapper.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "PGP Menu")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        if !gpg.isAvailable {
            menu.addItem(withTitle: "⚠️ GPG not found", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Install: brew install gnupg", action: nil, keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
            statusItem.menu = menu
            return
        }

        // Encrypt submenu
        let encryptItem = NSMenuItem(title: "Encrypt Clipboard", action: nil, keyEquivalent: "e")
        let encryptMenu = NSMenu()
        let keys = gpg.listPublicKeys()

        if keys.isEmpty {
            encryptMenu.addItem(withTitle: "No keys found", action: nil, keyEquivalent: "")
        } else {
            for key in keys {
                let item = NSMenuItem(title: key.displayName, action: #selector(encryptForRecipient(_:)), keyEquivalent: "")
                item.representedObject = key.email
                item.target = self
                encryptMenu.addItem(item)
            }
        }
        encryptItem.submenu = encryptMenu
        menu.addItem(encryptItem)

        // Decrypt
        let decryptItem = NSMenuItem(title: "Decrypt Clipboard", action: #selector(decryptClipboard), keyEquivalent: "d")
        decryptItem.target = self
        menu.addItem(decryptItem)

        menu.addItem(NSMenuItem.separator())

        // Sign
        let signItem = NSMenuItem(title: "Sign Clipboard", action: #selector(signClipboard), keyEquivalent: "s")
        signItem.target = self
        menu.addItem(signItem)

        // Verify
        let verifyItem = NSMenuItem(title: "Verify Clipboard", action: #selector(verifyClipboard), keyEquivalent: "v")
        verifyItem.target = self
        menu.addItem(verifyItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh keys
        let refreshItem = NSMenuItem(title: "Refresh Keys", action: #selector(refreshKeys), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func encryptForRecipient(_ sender: NSMenuItem) {
        guard let email = sender.representedObject as? String else { return }
        guard let text = getClipboardText() else {
            showNotification(title: "Error", body: "Clipboard is empty or not text")
            return
        }

        switch gpg.encrypt(text: text, recipientEmail: email) {
        case .success(let encrypted):
            setClipboard(encrypted)
            showNotification(title: "Encrypted ✓", body: "Encrypted text copied to clipboard")
        case .failure(let error):
            showNotification(title: "Encryption Failed", body: error.localizedDescription)
        }
    }

    @objc private func decryptClipboard() {
        guard let text = getClipboardText() else {
            showNotification(title: "Error", body: "Clipboard is empty or not text")
            return
        }

        switch gpg.decrypt(text: text) {
        case .success(let decrypted):
            setClipboard(decrypted)
            showNotification(title: "Decrypted ✓", body: "Decrypted text copied to clipboard")
        case .failure(let error):
            showNotification(title: "Decryption Failed", body: error.localizedDescription)
        }
    }

    @objc private func signClipboard() {
        guard let text = getClipboardText() else {
            showNotification(title: "Error", body: "Clipboard is empty or not text")
            return
        }

        switch gpg.sign(text: text) {
        case .success(let signed):
            setClipboard(signed)
            showNotification(title: "Signed ✓", body: "Signed text copied to clipboard")
        case .failure(let error):
            showNotification(title: "Signing Failed", body: error.localizedDescription)
        }
    }

    @objc private func verifyClipboard() {
        guard let text = getClipboardText() else {
            showNotification(title: "Error", body: "Clipboard is empty or not text")
            return
        }

        switch gpg.verify(text: text) {
        case .success(let result):
            showNotification(title: "Signature Valid ✓", body: result)
        case .failure(let error):
            showNotification(title: "Verification Failed", body: error.localizedDescription)
        }
    }

    @objc private func refreshKeys() {
        buildMenu()
        showNotification(title: "Keys Refreshed", body: "Key list updated")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func getClipboardText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    private func setClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func showNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
