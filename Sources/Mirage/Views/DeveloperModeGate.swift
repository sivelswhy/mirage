import SwiftUI

/// Voile affiché quand l'iPhone branché n'a pas le Mode développeur actif :
/// iOS refuserait alors toute simulation, même tunnel ouvert.
struct DeveloperModeGate: View {
    @Environment(SpoofSession.self) private var session
    let namespace: Namespace.ID

    @State private var checking = false

    private let steps: [(icon: String, text: String)] = [
        ("gearshape", "Sur l'iPhone, ouvre Réglages puis Confidentialité et sécurité."),
        ("hammer", "Tout en bas, touche Mode développeur et active l'interrupteur."),
        ("arrow.clockwise", "Touche Redémarrer. Une fois l'iPhone rallumé et déverrouillé, "
            + "touche Activer puis saisis ton code."),
        ("cable.connector.horizontal", "Garde l'iPhone branché : Mirage le détectera tout seul."),
    ]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()

            Group {
                VStack(spacing: 18) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.orange)

                    VStack(spacing: 6) {
                        Text("Mode développeur désactivé")
                            .font(.title3)

                        Text("\(session.selected?.name ?? "L'iPhone") refuse la simulation "
                             + "de position tant que ce mode n'est pas activé.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.callout.monospacedDigit().weight(.semibold))
                                    .frame(width: 22, height: 22)
                                    .background(.tint.opacity(0.18), in: .circle)
                                Label(step.text, systemImage: step.icon)
                                    .labelStyle(StepLabelStyle())
                            }
                        }
                    }
                    .frame(maxWidth: 380, alignment: .leading)

                    Text("Le réglage n'apparaît pas ? Ferme complètement l'app Réglages "
                         + "et rouvre-la : Mirage vient de le rendre visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)

                    HStack(spacing: 10) {
                        Button {
                            checking = true
                            Task {
                                await session.discoverDevices()
                                checking = false
                            }
                        } label: {
                            if checking {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Revérifier")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(checking)

                        Button("Aide d'Apple") {
                            NSWorkspace.shared.open(
                                URL(string: "https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device")!
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 2)
                }
                .padding(32)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .glassEffectID("developer", in: namespace)
            }
        }
        .transition(.opacity)
    }
}

private struct StepLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .foregroundStyle(.secondary)
                .frame(width: 18)
            configuration.title
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
