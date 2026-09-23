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
                         ? "Option-clic sur la carte, ou ⌥ Entrée dans la recherche, pour poser l'arrivée"
                         : "Arrivée posée")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }

                if let error = session.routeError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }

                HStack(spacing: 8) {
                    if session.route == nil {
                        Button {
                            Task { await session.planRoute() }
                        } label: {
                            Label(session.isPlanning ? "Calcul…" : "Lancer le trajet",
                                  systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.routeDestination == nil || session.isPlanning)
                    } else {
                        if session.progress < 1 {
                            Button {
                                session.isPlaying ? session.pause() : session.resume()
                            } label: {
                                Label(session.isPlaying ? "Pause" : "Reprendre",
                                      systemImage: session.isPlaying ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Toggle(isOn: $session.followsRoute) {
                            Image(systemName: "location.north.line.fill")
                        }
                        .toggleStyle(.button)
                        .help("La carte suit la position")

                        Button {
                            session.cancelRoute()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Arrêter et effacer le trajet")
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
                Text(Measurement(value: route.distance * (1 - session.progress), unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated, usage: .road)))
                Text("·")
                Text(session.progress >= 1
                     ? "Arrivé"
                     : Duration.seconds(session.remainingTime)
                        .formatted(.units(allowed: [.hours, .minutes, .seconds],
                                          width: .narrow, maximumUnitCount: 2)))
                Text("·")
                Text("\(Int(route.averageSpeedKmh.rounded())) km/h")
            }
            .font(.system(.callout, design: .rounded))
            .monospacedDigit()

            ProgressView(value: session.progress)
                .progressViewStyle(.linear)
                .frame(width: 220)
        }
    }
}
