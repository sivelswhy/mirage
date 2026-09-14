import Foundation

enum PMD3Error: Error, LocalizedError {
    case binaryMissing
    case failed(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            "Backend introuvable : ni interpréteur embarqué, ni installation système."
        case .failed(let code, let err):
            "Échec (code \(code)) : \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

/// Exécute le backend pymobiledevice3 embarqué dans Contents/Resources/backend.
enum PMD3 {

    /// Interpréteur relocalisable embarqué dans le bundle.
    /// On appelle `python3 -m pymobiledevice3` plutôt que le script console,
    /// car ce dernier encode un shebang absolu qui ne survit pas au transport.
    private static var embeddedPython: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let candidate = resources.appendingPathComponent("backend/bin/python3")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    /// Repli sur une installation système, utile en développement.
    private static var systemBinary: URL? {
        ["/opt/homebrew/bin/pymobiledevice3", "/usr/local/bin/pymobiledevice3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Exécutable et préfixe d'arguments à utiliser pour toute commande.
    static func invocation(_ arguments: [String]) -> (executable: URL, arguments: [String])? {
        if let python = embeddedPython {
            return (python, ["-m", "pymobiledevice3"] + arguments)
        }
        if let binary = systemBinary {
            return (binary, arguments)
        }
        return nil
    }

    static var isAvailable: Bool { invocation([]) != nil }

    /// Lance la commande et renvoie stdout une fois le processus terminé.
    @discardableResult
    static func run(_ arguments: [String]) async throws -> String {
        guard let call = invocation(arguments) else { throw PMD3Error.binaryMissing }

        let process = Process()
        process.executableURL = call.executable
        process.arguments = call.arguments

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()

        let stdout = try out.fileHandleForReading.readToEnd() ?? Data()
        let stderr = try err.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PMD3Error.failed(
                code: process.terminationStatus,
                stderr: String(decoding: stderr, as: UTF8.self)
            )
        }
        return String(decoding: stdout, as: UTF8.self)
    }

    /// Lance un processus longue durée et diffuse ses lignes de sortie.
    static func stream(_ arguments: [String], privileged: Bool) throws -> (Process, AsyncStream<String>) {
        guard let call = invocation(arguments) else { throw PMD3Error.binaryMissing }

        let process = Process()
        if privileged {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", call.executable.path] + call.arguments
        } else {
            process.executableURL = call.executable
            process.arguments = call.arguments
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let stream = AsyncStream<String> { continuation in
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    continuation.finish()
                    return
                }
                String(decoding: data, as: UTF8.self)
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .forEach { continuation.yield(String($0)) }
            }
            continuation.onTermination = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }

        try process.run()
        return (process, stream)
    }
}
