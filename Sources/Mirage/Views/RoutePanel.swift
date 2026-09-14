import SwiftUI
import MapKit

/// Sélecteur de mode + lancement du trajet, façon Plans.
struct RoutePanel: View {
    @Environment(SpoofSession.self) private var session
    let namespace: Namespace.ID

    var body: some View {
        @Bindable var session = session

        Group {
            VStack(spacing: 12) {
                Picker("", selection: $session.mode) {
                    ForEach(TravelMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol)
                            .labelStyle(.iconOnly)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)

                if let route = session.route {
                    summary(route)
                } else {
                    Text(session.routeDestination == nil
                         ? "Option-clic sur la carte pour poser l'arrivée"
                         : "Arrivée posée")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await session.planRoute() }
                    } label: {
                        Label(session.isPlanning ? "Calcul…" : "Lancer le trajet",
                              systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.routeDestination == nil || session.isPlanning)

                    if session.route != nil {
                        Button {
                            session.cancelRoute()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .glassEffectID("route", in: namespace)
        }
    }

    @ViewBuilder
    private func summary(_ route: SimulatedRoute) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(Measurement(value: route.distance, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated, usage: .road)))
                Text("·")
                Text(Duration.seconds(route.duration)
                    .formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
                Text("·")
                Text("\(Int(route.averageSpeedKmh.rounded())) km/h")
            }
            .font(.system(.callout, design: .rounded))

            ProgressView(value: session.progress)
                .progressViewStyle(.linear)
                .frame(width: 200)
        }
    }
}
