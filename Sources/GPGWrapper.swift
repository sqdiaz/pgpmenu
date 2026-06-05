import Foundation

struct GPGKey {
    let id: String
    let email: String
    let name: String

    var displayName: String {
        if name.isEmpty { return email }
        return "\(name) <\(email)>"
    }
}

class GPGWrapper {
    static let shared = GPGWrapper()

    private var gpgPath: String? {
        let paths = ["/opt/homebrew/bin/gpg", "/usr/local/bin/gpg", "/usr/bin/gpg"]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    var isAvailable: Bool { gpgPath != nil }

    func listPublicKeys() -> [GPGKey] {
        guard let gpg = gpgPath else { return [] }
        let output = run(gpg, arguments: ["--list-keys", "--with-colons", "--batch"])
        return parseKeys(output)
    }

    func listSecretKeys() -> [GPGKey] {
        guard let gpg = gpgPath else { return [] }
        let output = run(gpg, arguments: ["--list-secret-keys", "--with-colons", "--batch"])
        return parseKeys(output)
    }

    // MARK: - Detailed Key Listing

    func listDetailedKeys() -> [GPGKeyInfo] {
        guard let gpg = gpgPath else { return [] }
        let pubOutput = run(gpg, arguments: ["--list-keys", "--with-colons", "--fingerprint", "--batch"])
        let secOutput = run(gpg, arguments: ["--list-secret-keys", "--with-colons", "--fingerprint", "--batch"])

        let secretFingerprints = parseFingerprints(secOutput)
        return parseDetailedKeys(pubOutput, secretFingerprints: secretFingerprints)
    }

    func importKey(fromFile path: String) -> Result<String, GPGError> {
        guard let gpg = gpgPath else { return .failure(.gpgNotFound) }
        let output = run(gpg, arguments: ["--import", "--batch", path])
        // gpg --import outputs to stderr; check if file was processed
        let errOutput = runCapturingStderr(gpg, arguments: ["--import", "--batch", path])
        if errOutput.contains("imported") || errOutput.contains("not changed") {
            return .success(errOutput)
        }
        // Try simple run — if the key was already imported, that's fine
        return .success(output.isEmpty ? errOutput : output)
    }

    func exportKey(fingerprint: String) -> Result<String, GPGError> {
        guard let gpg = gpgPath else { return .failure(.gpgNotFound) }
        let output = run(gpg, arguments: ["--export", "--armor", "--batch", fingerprint])
        if output.contains("BEGIN PGP PUBLIC KEY BLOCK") {
            return .success(output)
        }
        return .failure(.executionFailed("Failed to export key"))
    }

    func deletePublicKey(fingerprint: String) -> Result<Void, GPGError> {
        guard let gpg = gpgPath else { return .failure(.gpgNotFound) }
        let process = Process()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: gpg)
        process.arguments = ["--batch", "--yes", "--delete-keys", fingerprint]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        do { try process.run() } catch { return .failure(.executionFailed(error.localizedDescription)) }
        process.waitUntilExit()
        if process.terminationStatus == 0 { return .success(()) }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
        return .failure(.executionFailed(errMsg))
    }

    func deleteSecretAndPublicKey(fingerprint: String) -> Result<Void, GPGError> {
        guard let gpg = gpgPath else { return .failure(.gpgNotFound) }
        let process = Process()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: gpg)
        process.arguments = ["--batch", "--yes", "--delete-secret-and-public-key", fingerprint]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        do { try process.run() } catch { return .failure(.executionFailed(error.localizedDescription)) }
        process.waitUntilExit()
        if process.terminationStatus == 0 { return .success(()) }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
        return .failure(.executionFailed(errMsg))
    }

    func encrypt(text: String, recipientEmail: String) -> Result<String, GPGError> {
        guard let gpg = gpgPath else { return .failure(.gpgNotFound) }
        return runWithInput(
            gpg,
            arguments: ["--encrypt", "--armor", "--batch", "--trust-model", "always",
                        "--recipient", recipientEmail],
            input: text
        )
    }

    func decrypt(text: String) -> Result<String, GPGError> {
        guard let gpg = gpgPath else { return .failure(.gpgNotFound) }
        return runWithInput(
            gpg,
            arguments: ["--decrypt", "--batch"],
            input: text
        )
    }

    func sign(text: String, signingKeyID: String? = nil) -> Result<String, GPGError> {
        guard let gpg = gpgPath else { return .failure(.gpgNotFound) }
        var arguments = ["--clearsign", "--batch"]
        if let keyID = signingKeyID {
            arguments.append(contentsOf: ["--default-key", keyID])
        }
        return runWithInput(gpg, arguments: arguments, input: text)
    }

    func verify(text: String) -> Result<String, GPGError> {
        guard let gpg = gpgPath else { return .failure(.gpgNotFound) }
        return runWithInput(
            gpg,
            arguments: ["--verify", "--batch"],
            input: text
        )
    }

    // MARK: - Private

    private func parseKeys(_ output: String) -> [GPGKey] {
        var keys: [GPGKey] = []
        var currentKeyID: String?

        for line in output.components(separatedBy: "\n") {
            let fields = line.components(separatedBy: ":")
            guard fields.count > 9 else { continue }

            if fields[0] == "pub" || fields[0] == "sec" {
                currentKeyID = fields[4]
            } else if fields[0] == "uid", let keyID = currentKeyID {
                let uidField = fields[9]
                let (name, email) = parseUID(uidField)
                if !email.isEmpty {
                    keys.append(GPGKey(id: keyID, email: email, name: name))
                    currentKeyID = nil
                }
            }
        }
        return keys
    }

    private func parseUID(_ uid: String) -> (name: String, email: String) {
        // Handle multiple UID formats:
        // 1. "Name <email@example.com>"
        // 2. "email@example.com"
        // 3. "(Comment) Name <email@example.com>"
        // 4. "Name" (just name, no email)
        
        if let emailStart = uid.firstIndex(of: "<"),
           let emailEnd = uid.firstIndex(of: ">") {
            // Format: "Name <email>" or "(Comment) Name <email>"
            let email = String(uid[uid.index(after: emailStart)..<emailEnd])
            let beforeEmail = String(uid[uid.startIndex..<emailStart]).trimmingCharacters(in: .whitespaces)
            
            // Remove comment if present: "(Comment) Name" -> "Name"
            let name: String
            if beforeEmail.hasPrefix("(") {
                if let commentEnd = beforeEmail.firstIndex(of: ")") {
                    let afterComment = String(beforeEmail[beforeEmail.index(after: commentEnd)...]).trimmingCharacters(in: .whitespaces)
                    name = afterComment.isEmpty ? beforeEmail : afterComment
                } else {
                    name = beforeEmail
                }
            } else {
                name = beforeEmail
            }
            return (name, email)
        } else if uid.contains("@") {
            // Format: "email@example.com" (just email)
            return ("", uid.trimmingCharacters(in: .whitespaces))
        } else {
            // Format: "Name" (just name, no email)
            return (uid.trimmingCharacters(in: .whitespaces), "")
        }
    }

    private func run(_ path: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func runWithInput(_ path: String, arguments: [String], input: String) -> Result<String, GPGError> {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        do {
            try process.run()
        } catch {
            return .failure(.executionFailed(error.localizedDescription))
        }

        inPipe.fileHandleForWriting.write(input.data(using: .utf8)!)
        inPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus == 0 {
            let output = String(data: outData, encoding: .utf8) ?? ""
            return .success(output)
        } else {
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            return .failure(.executionFailed(errMsg))
        }
    }

    private func runCapturingStderr(_ path: String, arguments: [String]) -> String {
        let process = Process()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        try? process.run()
        process.waitUntilExit()
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseFingerprints(_ output: String) -> Set<String> {
        var fingerprints = Set<String>()
        for line in output.components(separatedBy: "\n") {
            let fields = line.components(separatedBy: ":")
            if fields.count > 9 && fields[0] == "fpr" {
                fingerprints.insert(fields[9])
            }
        }
        return fingerprints
    }

    private func parseDetailedKeys(_ output: String, secretFingerprints: Set<String>) -> [GPGKeyInfo] {
        var keys: [GPGKeyInfo] = []
        var currentFingerprint: String?
        var currentCreation: String?
        var currentExpiry: String?
        var currentTrust: String?

        for line in output.components(separatedBy: "\n") {
            let fields = line.components(separatedBy: ":")
            guard fields.count > 9 else { continue }

            if fields[0] == "pub" {
                currentCreation = formatTimestamp(fields[5])
                currentExpiry = formatTimestamp(fields[6])
                currentTrust = trustLabel(fields[1])
                currentFingerprint = nil
            } else if fields[0] == "fpr" {
                if currentFingerprint == nil {
                    currentFingerprint = fields[9]
                }
            } else if fields[0] == "uid", let fpr = currentFingerprint {
                let uidField = fields[9]
                let (name, email) = parseUID(uidField)
                if !email.isEmpty {
                    let shortID = String(fpr.suffix(16))
                    let hasSecret = secretFingerprints.contains(fpr)
                    keys.append(GPGKeyInfo(
                        fingerprint: fpr,
                        shortID: shortID,
                        email: email,
                        name: name,
                        creationDate: currentCreation ?? "",
                        expiryDate: currentExpiry ?? "",
                        hasSecret: hasSecret,
                        trustLevel: currentTrust ?? ""
                    ))
                }
            }
        }
        return keys
    }

    private func formatTimestamp(_ ts: String) -> String {
        guard !ts.isEmpty, let epoch = TimeInterval(ts) else { return "" }
        let date = Date(timeIntervalSince1970: epoch)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func trustLabel(_ code: String) -> String {
        switch code {
        case "o": return "Unknown"
        case "n": return "Never trust"
        case "m": return "Marginal"
        case "f": return "Full"
        case "u": return "Ultimate"
        case "r": return "Revoked"
        case "e": return "Expired"
        case "d": return "Disabled"
        default: return code
        }
    }
}

enum GPGError: Error, LocalizedError {
    case gpgNotFound
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .gpgNotFound:
            return "GPG not found. Install with: brew install gnupg"
        case .executionFailed(let msg):
            return msg
        }
    }
}
