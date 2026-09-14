import SwiftUI

/// Bandeau de diagnostic activé par la variable d'environnement
/// MIRAGE_DIAGNOSTIC. Il place côte à côte trois rendus au-dessus du même
/// fond pour déterminer lequel la machine sait afficher.
///
/// Si les matériaux classiques sont translucides mais pas le verre, le défaut
/// vient du code. Si tout est opaque, il vient de la machine.
struct MaterialProbe: View {
    @Namespace private var probe

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MIRAGE_DIAGNOSTIC"] == "1"
    }

    var body: some View {
        HStack(spacing: 12) {
            swatch("ultraThin") { $0.background(.ultraThinMaterial, in: .rect(cornerRadius: 12)) }
            swatch("regular") { $0.background(.regularMaterial, in: .rect(cornerRadius: 12)) }
            swatch("opacité") { $0.background(.white.opacity(0.35), in: .rect(cornerRadius: 12)) }
            swatch("glass") { $0.glassEffect(.regular, in: .rect(cornerRadius: 12)) }
            swatch("glass tinté") {
                $0.glassEffect(.regular.tint(.blue), in: .rect(cornerRadius: 12))
            }
        }
        .padding(10)
    }

    private func swatch<V: View>(
        _ title: String,
        _ decorate: (AnyView) -> V
    ) -> some View {
        decorate(AnyView(
            Text(title)
                .font(.caption2)
                .frame(width: 84, height: 54)
        ))
    }
}
