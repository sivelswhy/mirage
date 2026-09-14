import Foundation
import ServiceManagement
import Observation

/// Enregistrement du démon privilégié et dialogue XPC avec lui.
///
/// Le démon existe parce que l'ouverture du tunnel vers iOS 17 et plus exige
/// la création d'une interface réseau, opération réservée à root. L'app, elle,
/// tourne sous le compte de l'utilisateur et ne peut pas s'élever seule.
@MainActor
@Observable
final class HelperClient {

    enum State: Equatable {
        case unknown
        case notRegistered
        case needsApproval
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .unknown: "vérification du démon"
            case .notRegistered: "démon non installé"
            case .needsApproval: "autorisation requise dans Réglages"
            case .ready: "démon actif"
            case .failed(let message): message
            }
        }
    }

    var state: State = .unknown

    private var connection: NSXPCConnection?
    private var service: SMAppService {
        SMAppService.daemon(plistName: "io.pivo.Mirage.Helper.plist")
    }

    // MARK: Cycle de vie

    func refresh() {
        switch service.status {
        case .enabled: state = .ready
        case .requiresApproval: state = .needsApproval
        case .notRegistered: state = .notRegistered
        case .notFound: state = .failed("Démon absent du bundle")
        @unknown default: state = .unknown
        }
    }

    /// Déclenche l'invite d'autorisation système. À n'appeler que sur action
    /// explicite de l'utilisateur, jamais silencieusement au lancement.
    func register() {
        do {
            try service.register()
            refresh()
        } catch {
            // L'erreur 1 signifie que l'utilisateur doit approuver dans Réglages.
            state = (error as NSError).code == 1
                ? .needsApproval
                : .failed(error.localizedDescription)
        }
    }

    func unregister() async {
        try? await service.unregister()
        invalidate()
        refresh()
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: Connexion

    private func proxy() throws -> TunnelControlProtocol {
        if connection == nil {
            let new = NSXPCConnection(machServiceName: kHelperMachServiceName,
                                      options: .privileged)
            new.remoteObjectInterface = NSXPCInterface(with: TunnelControlProtocol.self)
            new.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            new.resume()
            connection = new
        }

        guard let remote = connection?.remoteObjectProxyWithErrorHandler({ _ in })
                as? TunnelControlProtocol
        else { throw HelperError.unavailable }

        return remote
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    // MARK: Opérations

    func startTunnel(udid: String) async throws -> RSDEndpoint {
        let remote = try proxy()
        return try await withCheckedThrowingContinuation { continuation in
            remote.startTunnel(udid: udid) { address, port, error in
                if let address, error == nil {
                    continuation.resume(returning: RSDEndpoint(address: address, port: port))
                } else {
                    continuation.resume(throwing: HelperError.tunnel(error ?? "échec inconnu"))
                }
            }
        }
    }

    func stopTunnel() async {
        guard let remote = try? proxy() else { return }
        await withCheckedContinuation { continuation in
            remote.stopTunnel { _ in continuation.resume() }
        }
    }
}

enum HelperError: Error, LocalizedError {
    case unavailable
    case tunnel(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Démon injoignable."
        case .tunnel(let message): message
        }
    }
}
