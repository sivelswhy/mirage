import Foundation

// MARK: - Localisation du backend

/// Le démon vit dans Contents/MacOS du bundle de l'app : l'interpréteur
/// embarqué se trouve donc deux niveaux au-dessus, dans Resources.
private func embeddedPython() -> URL? {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let contents = executable
        .deletingLastPathComponent()   // MacOS
        .deletingLastPathComponent()   // Contents
    let python = contents.appendingPathComponent("Resources/backend/bin/python3")
    return FileManager.default.isExecutableFile(atPath: python.path) ? python : nil
}

// MARK: - Service

final class TunnelService: NSObject, TunnelControlProtocol {

    private var process: Process?
    private var address: String?
    private var port: Int = 0
    private let queue = DispatchQueue(label: "io.pivo.Mirage.Helper.tunnel")

    func helperVersion(reply: @escaping (String) -> Void) {
        reply(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
    }

    func tunnelStatus(reply: @escaping (Bool, String?, Int) -> Void) {
        queue.sync {
            reply(process?.isRunning == true, address, port)
        }
    }

    func stopTunnel(reply: @escaping (Bool) -> Void) {
        queue.sync {
            process?.terminate()
            process = nil
            address = nil
            port = 0
        }
        reply(true)
    }

    func startTunnel(udid: String, reply: @escaping (String?, Int, String?) -> Void) {
        // Le paramètre vient d'un client : on le contraint à un UDID plausible
        // plutôt que de le passer tel quel à un processus lancé en root.
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        guard !udid.isEmpty, udid.count <= 64,
              udid.unicodeScalars.allSatisfy(allowed.contains)
        else {
            reply(nil, 0, "Identifiant d'appareil invalide")
            return
        }

        guard let python = embeddedPython() else {
            reply(nil, 0, "Interpréteur embarqué introuvable")
            return
        }

        stopTunnel { _ in }

        let task = Process()
        task.executableURL = python
        task.arguments = ["-m", "pymobiledevice3", "lockdown", "start-tunnel", "--udid", udid]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        var pendingAddress: String?
        var answered = false
        let answer: (String?, Int, String?) -> Void = { a, p, e in
            guard !answered else { return }
            answered = true
            reply(a, p, e)
        }

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let text = String(line)

                if let value = Self.capture(#"RSD Address:\s*([0-9a-fA-F:.]+)"#, in: text) {
                    pendingAddress = value
                }
                if let value = Self.capture(#"RSD Port:\s*(\d+)"#, in: text),
                   let number = Int(value), let resolved = pendingAddress {
                    self?.queue.sync {
                        self?.address = resolved
                        self?.port = number
                    }
                    answer(resolved, number, nil)
                }
            }
        }

        task.terminationHandler = { _ in
            answer(nil, 0, "Le tunnel s'est fermé avant d'annoncer son adresse")
        }

        do {
            try task.run()
            queue.sync { self.process = task }
        } catch {
            answer(nil, 0, error.localizedDescription)
            return
        }

        // Filet de sécurité : sans réponse en trente secondes, on abandonne.
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            answer(nil, 0, "Délai dépassé à l'ouverture du tunnel")
        }
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

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {

    private let service = TunnelService()

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {

        guard Self.isTrusted(connection) else {
            NSLog("Mirage helper : connexion refusée, client non vérifié")
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: TunnelControlProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }

    /// Vérifie que le client est bien signé par le même bundle que le démon.
    ///
    /// Sans identité Developer ID, cette exigence se limite à l'identifiant de
    /// bundle, ce qui est nettement plus faible qu'une vérification par Team ID.
    private static func isTrusted(_ connection: NSXPCConnection) -> Bool {
        var token = connection.auditToken
        let attributes = [
            kSecGuestAttributeAudit: Data(bytes: &token, count: MemoryLayout.size(ofValue: token))
        ] as CFDictionary

        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let guest = code
        else { return false }

        let requirementText = "identifier \"io.pivo.Mirage\"" +
            " and anchor apple generic" +
            " or identifier \"io.pivo.Mirage\""

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement)
                == errSecSuccess,
              let rule = requirement
        else { return false }

        return SecCodeCheckValidity(guest, [], rule) == errSecSuccess
    }
}

// MARK: - Démarrage

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: kHelperMachServiceName)
listener.delegate = delegate
listener.resume()

NSLog("Mirage helper démarré")
RunLoop.main.run()
