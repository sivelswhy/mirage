import SwiftUI
import MapKit

struct SearchPanel: View {
    @Environment(SpoofSession.self) private var session
    let namespace: Namespace.ID
    @State private var query = ""

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Rechercher un lieu", text: $query)
                        .textFieldStyle(.plain)
                        .onSubmit { Task { await geocode() } }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("search", in: namespace)

                if !session.recents.isEmpty {
                    Text("Récents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)

                    ForEach(session.recents) { waypoint in
                        Button {
                            Task { await session.setLocation(waypoint.coordinate, throttled: false) }
                        } label: {
                            Text(waypoint.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                    }
                }
            }
            .padding(14)
            .frame(width: 260)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .glassEffectID("panel", in: namespace)
        }
    }

    private func geocode() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first
        else { return }
        await session.setLocation(item.placemark.coordinate, throttled: false)
        session.recents.insert(
            Waypoint(coordinate: item.placemark.coordinate, name: item.name ?? query),
            at: 0
        )
        session.recents = Array(session.recents.prefix(5))
    }
}

struct ControlCluster: View {
    @Binding var camera: MapCameraPosition
    let namespace: Namespace.ID

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 0) {
                clusterButton("plus") { zoom(0.5) }
                Divider().frame(width: 26)
                clusterButton("minus") { zoom(2) }
                Divider().frame(width: 26)
                clusterButton("view.3d") {}
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("cluster", in: namespace)
        }
    }

    private func clusterButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    private func zoom(_ factor: Double) {
        guard let region = camera.region else { return }
        camera = .region(MKCoordinateRegion(
            center: region.center,
            span: .init(
                latitudeDelta: region.span.latitudeDelta * factor,
                longitudeDelta: region.span.longitudeDelta * factor
            )
        ))
    }
}

struct StatusPill: View {
    @Environment(SpoofSession.self) private var session
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.simulated == nil ? "location.slash" : "location.fill")
                .foregroundStyle(session.simulated == nil
                                 ? AnyShapeStyle(.secondary)
                                 : AnyShapeStyle(.tint))

            VStack(alignment: .leading, spacing: 1) {
                Text(session.simulated?.formatted ?? "aucune position simulée")
                    .font(.system(.body, design: .monospaced))
                Text("\(session.selected?.name ?? "aucun appareil") · \(session.tunnel.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if session.simulated != nil {
                Button {
                    Task { await session.clearLocation() }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .glassEffect(
            session.simulated == nil ? .regular : .regular.tint(.accentColor),
            in: .capsule
        )
        .glassEffectID("status", in: namespace)
    }
}

/// Gimbal : l'angle du geste donne le cap, la distance module la vitesse.
struct JoystickPad: View {
    @Environment(SpoofSession.self) private var session
    let namespace: Namespace.ID
    @State private var offset: CGSize = .zero

    private let radius: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.4), lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(.tint)
                .frame(width: 22, height: 22)
                .offset(offset)
        }
        .frame(width: 88, height: 88)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let clamped = min(radius, hypot(value.translation.width, value.translation.height))
                    let angle = atan2(value.translation.width, -value.translation.height)
                    offset = CGSize(
                        width: sin(angle) * clamped,
                        height: -cos(angle) * clamped
                    )
                    session.speed = Double(clamped / radius) * 12
                    session.drive(bearing: angle * 180 / .pi)
                }
                .onEnded { _ in
                    offset = .zero
                    session.stopDriving()
                }
        )
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("gimbal", in: namespace)
    }
}
