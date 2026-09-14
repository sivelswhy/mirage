import Foundation

/// Nom du service Mach exposé par le démon, et étiquette launchd.
public let kHelperMachServiceName = "io.pivo.Mirage.Helper"

/// Contrat XPC entre l'interface et le démon privilégié.
///
/// Toutes les méthodes sont asynchrones avec bloc de réponse, contrainte
/// imposée par XPC. Les types échangés restent volontairement primitifs :
/// tout objet complexe élargirait la surface d'attaque du démon.
@objc public protocol TunnelControlProtocol {

    /// Version du démon, pour détecter une app et un démon désynchronisés.
    func helperVersion(reply: @escaping (String) -> Void)

    /// Ouvre le tunnel vers l'appareil et renvoie l'adresse RSD.
    /// - Parameter reply: adresse, port, message d'erreur.
    func startTunnel(udid: String, reply: @escaping (String?, Int, String?) -> Void)

    /// Ferme le tunnel courant. Idempotent.
    func stopTunnel(reply: @escaping (Bool) -> Void)

    /// Indique si un tunnel est actuellement ouvert.
    func tunnelStatus(reply: @escaping (Bool, String?, Int) -> Void)
}
