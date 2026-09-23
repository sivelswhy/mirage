import Foundation

/// Connexion persistante au service de simulation de position.
///
/// `simulate-location set` ne rend jamais la main : il garde sa connexion
/// ouverte jusqu'à recevoir un signal, car iOS abandonne la position simulée
/// dès qu'elle se ferme. Lancer un processus par position les accumulait donc
/// sans jamais signaler d'échec. Ici, un seul processus garde la connexion et
/// reçoit les positions ligne à ligne ; chacune est confirmée par l'appareil.
final class LocationChannel: @unchecked Sendable {

    enum Target: Equatable, Sendable {
        case rsd(RSDEndpoint)
        case usbmux(udid: String)
    }

    let target: Target

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()

    private let lock = NSLock()
    /// Réponses attendues, dans l'ordre d'envoi : « ready » puis un « ok »
    /// ou « error » par commande.
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var buffer = ""
    private var transcript: [String] = []
    private var finished = false

    var isAlive: Bool {
        lock.lock(); defer { lock.unlock() }
        return !finished
    }

    init(target: Target) {
        self.target = target
    }

    /// Lance le processus et attend que la connexion au service soit ouverte.
    func open() async throws {
        guard let python = PMD3.python else { throw PMD3Error.binaryMissing }

        process.executableURL = python
        process.arguments = ["-B", "-c", Self.script] + {
            switch target {
            case .rsd(let endpoint): ["rsd", endpoint.address, String(endpoint.port)]
            case .usbmux(let udid): ["usbmux", udid]
            }
        }()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.receive(String(decoding: data, as: UTF8.self))
        }
        process.terminationHandler = { [weak self] _ in self?.terminate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            waiters.append(continuation)
            lock.unlock()
            do {
                try process.run()
            } catch {
                fail(error)
            }
        }
    }

    func set(latitude: Double, longitude: Double) async throws {
        try await send("\(latitude) \(longitude)")
    }

    func clear() async throws {
        try await send("clear")
    }

    func close() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        terminate()
    }

    // MARK: Protocole

    private func send(_ command: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: failure())
                return
            }
            waiters.append(continuation)
            lock.unlock()

            do {
                try input.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8))
            } catch {
                fail(error)
            }
        }
    }

    private func receive(_ text: String) {
        lock.lock()
        buffer += text
        var resolved: [(CheckedContinuation<Void, Error>, Error?)] = []

        while let newline = buffer.firstIndex(of: "\n") {
            let line = buffer[..<newline].trimmingCharacters(in: .whitespaces)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }

            if line == "ready" || line == "ok" {
                if !waiters.isEmpty { resolved.append((waiters.removeFirst(), nil)) }
            } else if line.hasPrefix("error ") {
                let message = String(line.dropFirst("error ".count))
                if !waiters.isEmpty {
                    resolved.append((waiters.removeFirst(), PMD3Error.failed(code: 0, stderr: message)))
                }
            } else {
                // Journal de pymobiledevice3 : gardé pour expliquer un échec.
                transcript.append(line)
                transcript = Array(transcript.suffix(20))
            }
        }
        lock.unlock()

        for (waiter, error) in resolved {
            if let error { waiter.resume(throwing: error) } else { waiter.resume() }
        }
    }

    /// Fin du processus : toute réponse encore attendue n'arrivera jamais.
    private func terminate() {
        lock.lock()
        finished = true
        let pending = waiters
        waiters = []
        lock.unlock()

        let error = failure()
        pending.forEach { $0.resume(throwing: error) }
    }

    private func fail(_ error: Error) {
        lock.lock()
        finished = true
        let pending = waiters
        waiters = []
        lock.unlock()

        pending.forEach { $0.resume(throwing: error) }
    }

    private func failure() -> Error {
        lock.lock(); defer { lock.unlock() }
        // La dernière ligne significative du journal est en général l'erreur.
        let reason = transcript.last { !$0.hasPrefix("- ") && !$0.hasPrefix(">") }
        return PMD3Error.failed(
            code: process.isRunning ? 0 : process.terminationStatus,
            stderr: reason ?? "Connexion au service de simulation perdue"
        )
    }

    private static let script = """
    import asyncio
    import sys

    from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
    from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation


    async def open_provider():
        if sys.argv[1] == "rsd":
            from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
            rsd = RemoteServiceDiscoveryService((sys.argv[2], int(sys.argv[3])))
            await rsd.connect()
            return rsd
        from pymobiledevice3.lockdown import create_using_usbmux
        return await create_using_usbmux(serial=sys.argv[2])


    async def main():
        provider = await open_provider()
        loop = asyncio.get_running_loop()
        async with DvtProvider(provider) as dvt, LocationSimulation(dvt) as simulation:
            print("ready", flush=True)
            while line := await loop.run_in_executor(None, sys.stdin.readline):
                parts = line.split()
                try:
                    if parts == ["clear"]:
                        await simulation.clear()
                    else:
                        await simulation.set(float(parts[0]), float(parts[1]))
                    print("ok", flush=True)
                except Exception as error:
                    print("error", error, flush=True)


    asyncio.run(main())
    """
}
