import SwiftUI

/// Voile affiché tant qu'aucun iPhone n'est détecté sur le bus USB.
struct DeviceGate: View {
    @Environment(SpoofSession.self) private var session
    let namespace: Namespace.ID

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()

            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 16) {
                    Image(systemName: "cable.connector.horizontal")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse)

                    VStack(spacing: 6) {
                        Text("Aucun iPhone détecté")
                            .font(.title3)

                        Text(hint)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }

                    if let error = session.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }

                    HStack(spacing: 10) {
                        Button("Réessayer") {
                            Task { await session.discoverDevices() }
                        }
                        .buttonStyle(.glassProminent)

                        Button("Mode développeur") {
                            NSWorkspace.shared.open(
                                URL(string: "https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device")!
                            )
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.top, 4)
                }
                .padding(32)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .glassEffectID("gate", in: namespace)
            }
        }
        .transition(.opacity)
    }

    private var hint: String {
        session.lastError == nil
        ? "Branche ton iPhone en USB, déverrouille-le, puis approuve la connexion si macOS le demande."
        : "Vérifie le câble, le déverrouillage de l'écran et l'activation du mode développeur."
    }
}
