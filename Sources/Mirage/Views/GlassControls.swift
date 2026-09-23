import SwiftUI
import MapKit

struct SearchPanel: View {
    @Environment(SpoofSession.self) private var session
    @Binding var camera: MapCameraPosition
    let visibleRegion: MKCoordinateRegion?
    let namespace: Namespace.ID

    @State private var query = ""
    @State private var search = PlaceSearch()
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Le champ ne porte PAS de .glassEffect : un matériau de verre ne
            // peut pas échantillonner un autre matériau de verre, et le panneau
            // qui l'entoure en est déjà un. Un simple remplissage suffit ici.
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)

                TextField("Rechercher un lieu", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        choose(highlightedSuggestion,
                               asDestination: NSEvent.modifierFlags.contains(.option))
                    }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.escape) {
                        clear()
                        return .handled
                    }

                if search.isResolving {
                    ProgressView().controlSize(.mini)
                } else if !query.isEmpty {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: .capsule)
            .onChange(of: query) {
                highlighted = 0
                search.update(query: query, near: visibleRegion)
            }

            if let failure = search.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
            }

            if !query.isEmpty, !search.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(search.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        HStack(spacing: 4) {
                            Button { choose(suggestion) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(suggestion.title)
                                        .lineLimit(1)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(index == highlighted ? AnyShapeStyle(.tint.opacity(0.18))
                                                                 : AnyShapeStyle(.clear),
                                            in: .rect(cornerRadius: 8))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)

                            Button { choose(suggestion, asDestination: true) } label: {
                                Image(systemName: "arrow.triangle.turn.up.right.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Définir comme arrivée (⌥ Entrée)")
                        }
                        .onHover { if $0 { highlighted = index } }
                    }
                }
            } else if query.isEmpty, !session.recents.isEmpty {
                Text("Récents")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 6)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.recents) { waypoint in
                        Button {
                            go(to: PlaceSearch.Place(name: waypoint.name,
                                                     coordinate: waypoint.coordinate))
                        } label: {
                            Text(waypoint.name)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 252)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .glassEffectID("panel", in: namespace)
    }

    private var highlightedSuggestion: PlaceSearch.Suggestion? {
        search.suggestions.indices.contains(highlighted) ? search.suggestions[highlighted] : nil
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !search.suggestions.isEmpty else { return .ignored }
        highlighted = (highlighted + step + search.suggestions.count) % search.suggestions.count
        return .handled
    }

    private func clear() {
        query = ""
        search.reset()
    }

    /// Sans suggestion, le texte saisi est cherché tel quel.
    private func choose(_ suggestion: PlaceSearch.Suggestion?, asDestination: Bool = false) {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard suggestion != nil || !text.isEmpty else { return }

        Task {
            do {
                let place = try await search.resolve(suggestion, query: text, near: visibleRegion)
                clear()
                focused = false
                if asDestination {
                    setDestination(place)
                } else {
                    go(to: place)
                }
            } catch {
                search.failure = error.localizedDescription
            }
        }
    }

    /// Centre la carte sur le lieu, puis y déplace l'iPhone.
    private func go(to place: PlaceSearch.Place) {
        focus(on: place.coordinate)
        remember(place)
        Task { await session.setLocation(place.coordinate, throttled: false) }
    }

    /// Pose l'arrivée sans déplacer l'iPhone, prête pour « Lancer le trajet ».
    private func setDestination(_ place: PlaceSearch.Place) {
        focus(on: place.coordinate)
        remember(place)
        session.setDestination(place.coordinate)
    }

    private func focus(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.smooth(duration: 0.6)) {
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
        }
    }

    private func remember(_ place: PlaceSearch.Place) {
        session.recents.removeAll { $0.name == place.name }
        session.recents.insert(Waypoint(coordinate: place.coordinate, name: place.name), at: 0)
        session.recents = Array(session.recents.prefix(5))
    }
}

struct ControlCluster: View {
    @Binding var camera: MapCameraPosition
    let namespace: Namespace.ID

    var body: some View {
        Group {
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
                if let error = session.locationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(maxWidth: 320, alignment: .leading)
                } else {
                    Text("\(session.selected?.name ?? "aucun appareil") · \(session.tunnel.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
