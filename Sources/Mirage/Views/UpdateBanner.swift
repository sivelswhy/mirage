import SwiftUI

/// Bandeau discret en haut de fenêtre, jamais modal.
struct UpdateBanner: View {
    @Environment(Updater.self) private var updater
    let namespace: Namespace.ID

    var body: some View {
        Group {
            switch updater.phase {
            case .available(let release):
                banner {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.tint)

                        Text("Mirage \(release.version.description) est disponible")

                        Button("Installer") {
                            Task { await updater.download(release) }
                        }
                        .buttonStyle(.glassProminent)

                        Button("Ignorer") { updater.skip(release) }
                            .buttonStyle(.glass)
                    }
                }

            case .downloading:
                banner {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Téléchargement…")
                    }
                }

            case .ready:
                banner {
                    Text("Glisse Mirage dans Applications, puis relance l'app")
                }

            case .failed(let message):
                banner { Text(message).foregroundStyle(.red) }

            case .idle, .checking:
                EmptyView()
            }
        }
        .animation(.smooth(duration: 0.3), value: updater.phase)
    }

    private func banner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        GlassEffectContainer(spacing: 14) {
            content()
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .glassEffectID("update", in: namespace)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
