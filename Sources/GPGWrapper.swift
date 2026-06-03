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

    func sign(text: String) -> Result<String, GPGError> {
        guard let gpg = gpgPath else { return .failure(.gpgNotFound) }
        return runWithInput(
            gpg,
            arguments: ["--clearsign", "--batch"],
            input: text
        )
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
        // Format: "Name <email@example.com>"
        guard let emailStart = uid.firstIndex(of: "<"),
              let emailEnd = uid.firstIndex(of: ">") else {
            return (uid, "")
        }
        let name = String(uid[uid.startIndex..<emailStart]).trimmingCharacters(in: .whitespaces)
        let email = String(uid[uid.index(after: emailStart)..<emailEnd])
        return (name, email)
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
