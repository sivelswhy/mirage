import Foundation

enum PMD3Error: Error, LocalizedError {
    case binaryMissing
    case failed(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            "pymobiledevice3 introuvable dans le bundle."
        case .failed(let code, let err):
            "Échec (code \(code)) : \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

/// Exécute le backend pymobiledevice3 embarqué dans Contents/Resources/backend.
enum PMD3 {

    static var executableURL: URL? {
        if let bundled = Bundle.main.url(
            forResource: "pymobiledevice3",
            withExtension: nil,
            subdirectory: "backend/bin"
        ) { return bundled }

        for candidate in ["/opt/homebrew/bin/pymobiledevice3", "/usr/local/bin/pymobiledevice3"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// Lance la commande et renvoie stdout une fois le processus terminé.
    @discardableResult
    static func run(_ arguments: [String]) async throws -> String {
        guard let exe = executableURL else { throw PMD3Error.binaryMissing }

        let process = Process()
        process.executableURL = exe
        process.arguments = arguments

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
        guard let exe = executableURL else { throw PMD3Error.binaryMissing }

        let process = Process()
        if privileged {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", exe.path] + arguments
        } else {
            process.executableURL = exe
            process.arguments = arguments
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
