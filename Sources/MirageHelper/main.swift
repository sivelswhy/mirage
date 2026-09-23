import Foundation

// MARK: - Localisation du backend

/// Le démon vit dans Contents/MacOS du bundle de l'app : l'interpréteur
/// embarqué se trouve donc deux niveaux au-dessus, dans Resources.
private var searchedPaths: [String] = []

private func embeddedPython() -> URL? {
    searchedPaths = []
    let executable = (Bundle.main.executableURL
                      ?? URL(fileURLWithPath: CommandLine.arguments[0]))
        .resolvingSymlinksInPath()
    var directory = executable.deletingLastPathComponent()
    for _ in 0..<4 {
        let candidate = directory.appendingPathComponent("Resources/backend/bin/python3")
        searchedPaths.append(candidate.path)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        directory = directory.deletingLastPathComponent()
    }
    return nil
}


// MARK: - Boîtes verrouillées

/// XPC exige qu'un bloc de réponse soit appelé exactement une fois, or
/// plusieurs chemins peuvent y prétendre : ce garde-fou les départage.
private final class SingleReply: @unchecked Sendable {
    private let lock = NSLock()
    private var block: ((String?, Int, String?) -> Void)?

    init(_ block: @escaping (String?, Int, String?) -> Void) { self.block = block }

    func send(_ address: String?, _ port: Int, _ error: String?) {
        lock.lock()
        let pending = block
        block = nil
        lock.unlock()
        pending?(address, port, error)
    }
}

/// Adresse accumulée entre deux lectures successives du tuyau.
private final class ParseState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func set(_ new: String) { lock.lock(); value = new; lock.unlock() }
    func current() -> String? { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: - Service

final class TunnelService: NSObject, TunnelControlProtocol, @unchecked Sendable {

    private let queue = NSLock()
    private var process: Process?
    private var address: String?
    private var port: Int = 0

    func helperVersion(reply: @escaping (String) -> Void) {
        reply(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
    }

    func tunnelStatus(reply: @escaping (Bool, String?, Int) -> Void) {
        queue.lock(); defer { queue.unlock() }
        reply(process?.isRunning == true, address, port)
    }

    func stopTunnel(reply: @escaping (Bool) -> Void) {
        queue.lock()
        let running = process
        process = nil
        address = nil
        port = 0
        queue.unlock()

        running?.terminate()
        reply(true)
    }

    func startTunnel(udid: String, reply: @escaping (String?, Int, String?) -> Void) {
        let answer = SingleReply(reply)

        // Le paramètre vient d'un client : on le contraint à un UDID plausible
        // plutôt que de le passer tel quel à un processus lancé en root.
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        guard !udid.isEmpty, udid.count <= 64,
              udid.unicodeScalars.allSatisfy(allowed.contains)
        else {
            answer.send(nil, 0, "Identifiant d'appareil invalide")
            return
        }

        guard let python = embeddedPython() else {
            answer.send(nil, 0, "Interpréteur embarqué introuvable")
            return
        }

        stopTunnel { _ in }

        let task = Process()
        task.executableURL = python
        task.arguments = ["-m", "pymobiledevice3", "lockdown", "start-tunnel", "--udid", udid]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let parsed = ParseState()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let text = String(line)

                if let value = Self.capture(#"RSD Address:\s*([0-9a-fA-F:.]+)"#, in: text) {
                    parsed.set(value)
                }
                if let value = Self.capture(#"RSD Port:\s*(\d+)"#, in: text),
                   let number = Int(value), let resolved = parsed.current() {
                    self?.record(address: resolved, port: number)
                    answer.send(resolved, number, nil)
                }
            }
        }

        task.terminationHandler = { _ in
            answer.send(nil, 0, "Le tunnel s'est fermé avant d'annoncer son adresse")
        }

        do {
            try task.run()
            queue.lock(); process = task; queue.unlock()
        } catch {
            answer.send(nil, 0, error.localizedDescription)
            return
        }

        // Filet de sécurité : sans réponse en trente secondes, on abandonne.
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            answer.send(nil, 0, "Délai dépassé à l'ouverture du tunnel")
        }
    }

    private func record(address value: String, port number: Int) {
        queue.lock()
        address = value
        port = number
        queue.unlock()
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}

// MARK: - Écoute XPC

final class ListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {

    private let service = TunnelService()

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // L'exigence de signature est posée sur l'écouteur : macOS écarte les
        // clients non conformes avant même d'arriver ici.
        connection.exportedInterface = NSXPCInterface(with: TunnelControlProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

// MARK: - Démarrage

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: kHelperMachServiceName)
listener.delegate = delegate

// API publique depuis macOS 13. Elle évite de manipuler le jeton d'audit à la
// main, ce qui passe par une propriété privée de NSXPCConnection.
// Sans identité Developer ID, l'exigence se limite à l'identifiant de bundle,
// donc reste plus faible qu'un contrôle par Team ID.
listener.setConnectionCodeSigningRequirement("identifier \"io.pivo.Mirage\"")

listener.resume()

NSLog("Mirage helper démarré")
RunLoop.main.run()
