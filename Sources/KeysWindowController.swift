import Cocoa

struct GPGKeyInfo {
    let fingerprint: String
    let shortID: String
    let email: String
    let name: String
    let creationDate: String
    let expiryDate: String
    let hasSecret: Bool
    let trustLevel: String

    var displayName: String {
        if name.isEmpty { return email }
        return "\(name) <\(email)>"
    }

    var typeLabel: String {
        hasSecret ? "sec/pub" : "pub"
    }
}

class KeysWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private var window: NSWindow?
    private var tableView: NSTableView!
    private var keys: [GPGKeyInfo] = []
    private let gpg = GPGWrapper.shared

    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 450),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PGPMenu — Key Management"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 300)

        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        contentView.autoresizingMask = [.width, .height]

        // Toolbar buttons
        let toolbar = makeToolbar()
        contentView.addSubview(toolbar)

        // Table view
        let scrollView = makeTableView()
        contentView.addSubview(scrollView)

        // Layout
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            toolbar.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        window.contentView = contentView
        self.window = window

        reloadKeys()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI Construction

    private func makeToolbar() -> NSView {
        let container = NSView()

        let importBtn = makeButton(title: "Import…", action: #selector(importKey))
        let exportBtn = makeButton(title: "Export", action: #selector(exportKey))
        let deleteBtn = makeButton(title: "Delete", action: #selector(deleteKey))
        let copyBtn = makeButton(title: "Copy Fingerprint", action: #selector(copyFingerprint))
        let refreshBtn = makeButton(title: "Refresh", action: #selector(refreshKeys))

        let stack = NSStackView(views: [importBtn, exportBtn, deleteBtn, copyBtn, refreshBtn])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .regular
        return btn
    }

    private func makeTableView() -> NSScrollView {
        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 22

        let columns: [(id: String, title: String, width: CGFloat)] = [
            ("name", "Name", 160),
            ("email", "Email", 180),
            ("keyid", "Key ID", 120),
            ("type", "Type", 60),
            ("created", "Created", 90),
            ("expires", "Expires", 90),
        ]

        for col in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.id))
            column.title = col.title
            column.width = col.width
            column.minWidth = 50
            tableView.addTableColumn(column)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        return scrollView
    }

    // MARK: - Data

    private func reloadKeys() {
        keys = gpg.listDetailedKeys()
        tableView.reloadData()
    }

    private func selectedKey() -> GPGKeyInfo? {
        let row = tableView.selectedRow
        guard row >= 0, row < keys.count else { return nil }
        return keys[row]
    }

    // MARK: - Actions

    @objc private func importKey() {
        let panel = NSOpenPanel()
        panel.title = "Import GPG Key"
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        panel.begin { [weak self] response in
            guard response == .OK else { return }
            var imported = 0
            var failed = 0

            for url in panel.urls {
                switch self?.gpg.importKey(fromFile: url.path) {
                case .success:
                    imported += 1
                case .failure:
                    failed += 1
                case .none:
                    break
                }
            }

            DispatchQueue.main.async {
                self?.reloadKeys()
                let msg = "Imported: \(imported)" + (failed > 0 ? ", Failed: \(failed)" : "")
                self?.showAlert(title: "Import Complete", message: msg, style: .informational)
            }
        }
    }

    @objc private func exportKey() {
        guard let key = selectedKey() else {
            showAlert(title: "No Selection", message: "Select a key to export.", style: .warning)
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Public Key"
        panel.nameFieldStringValue = "\(key.shortID).asc"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            switch self?.gpg.exportKey(fingerprint: key.fingerprint) {
            case .success(let armor):
                do {
                    try armor.write(to: url, atomically: true, encoding: .utf8)
                    self?.showAlert(title: "Exported", message: "Public key saved.", style: .informational)
                } catch {
                    self?.showAlert(title: "Error", message: error.localizedDescription, style: .critical)
                }
            case .failure(let error):
                self?.showAlert(title: "Export Failed", message: error.localizedDescription, style: .critical)
            case .none:
                break
            }
        }
    }

    @objc private func deleteKey() {
        guard let key = selectedKey() else {
            showAlert(title: "No Selection", message: "Select a key to delete.", style: .warning)
            return
        }

        if key.hasSecret {
            // Require typing fingerprint suffix for secret key deletion
            let last8 = String(key.fingerprint.suffix(8))
            let alert = NSAlert()
            alert.messageText = "Delete SECRET key: \(key.displayName)?"
            alert.informativeText = "This is irreversible! Type the last 8 characters of the fingerprint to confirm:\n\n\(key.fingerprint)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            input.placeholderString = last8
            alert.accessoryView = input

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
            guard input.stringValue.uppercased() == last8.uppercased() else {
                showAlert(title: "Cancelled", message: "Fingerprint did not match.", style: .warning)
                return
            }

            switch gpg.deleteSecretAndPublicKey(fingerprint: key.fingerprint) {
            case .success:
                reloadKeys()
            case .failure(let error):
                showAlert(title: "Delete Failed", message: error.localizedDescription, style: .critical)
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "Delete public key: \(key.displayName)?"
            alert.informativeText = "Key ID: \(key.fingerprint)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return }

            switch gpg.deletePublicKey(fingerprint: key.fingerprint) {
            case .success:
                reloadKeys()
            case .failure(let error):
                showAlert(title: "Delete Failed", message: error.localizedDescription, style: .critical)
            }
        }
    }

    @objc private func copyFingerprint() {
        guard let key = selectedKey() else {
            showAlert(title: "No Selection", message: "Select a key to copy its fingerprint.", style: .warning)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(key.fingerprint, forType: .string)
        showAlert(title: "Copied", message: "Fingerprint copied to clipboard.", style: .informational)
    }

    @objc private func refreshKeys() {
        reloadKeys()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        keys.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnID = tableColumn?.identifier.rawValue, row < keys.count else { return nil }
        let key = keys[row]

        let text: String
        switch columnID {
        case "name": text = key.name
        case "email": text = key.email
        case "keyid": text = key.shortID
        case "type": text = key.typeLabel
        case "created": text = key.creationDate
        case "expires": text = key.expiryDate.isEmpty ? "—" : key.expiryDate
        default: text = ""
        }

        let cellID = NSUserInterfaceItemIdentifier("Cell_\(columnID)")
        let cell: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
            cell = existing
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = cellID
            cell.lineBreakMode = .byTruncatingTail
        }
        cell.stringValue = text
        return cell
    }

    // MARK: - Helpers

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
}
