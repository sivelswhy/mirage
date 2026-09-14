import SwiftUI

/// Invite à installer le démon, affichée uniquement quand un appareil
/// iOS 17 ou plus est branché et que le démon n'est pas encore actif.
struct HelperGate: View {
    @Environment(SpoofSession.self) private var session
    let namespace: Namespace.ID

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Autorisation requise")
                    .font(.title3)

                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                HStack(spacing: 10) {
                    switch session.helper.state {
                    case .needsApproval:
                        Button("Ouvrir les Réglages") { session.helper.openSettings() }
                            .buttonStyle(.glassProminent)
                        Button("Revérifier") { session.helper.refresh() }
                            .buttonStyle(.glass)

                    default:
                        Button("Installer le démon") { session.helper.register() }
                            .buttonStyle(.glassProminent)
                    }
                }
                .padding(.top, 2)
            }
            .padding(28)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .glassEffectID("helper", in: namespace)
        }
    }

    private var explanation: String {
        switch session.helper.state {
        case .needsApproval:
            "macOS attend ton approbation. Dans Réglages, section Général puis "
            + "Ouverture et extensions, active Mirage."
        case .failed(let message):
            message
        default:
            "Simuler une position sur iOS 17 et plus exige d'ouvrir un tunnel "
            + "réseau, opération réservée à l'administrateur. Mirage installe "
            + "pour cela un composant système que tu peux retirer à tout moment."
        }
    }
}
