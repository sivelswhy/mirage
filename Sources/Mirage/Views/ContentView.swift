import SwiftUI
import MapKit

struct ContentView: View {
    @Environment(SpoofSession.self) private var session
    @Namespace private var glass

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: .init(latitude: 49.1829, longitude: -0.3707),
            span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    var body: some View {
        @Bindable var session = session

        MapReader { proxy in
            Map(position: $camera) {
                if let point = session.simulated {
                    Annotation("", coordinate: point) { SimulatedDot() }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControlVisibility(.hidden)
            .onTapGesture { location in
                guard let coordinate = proxy.convert(location, from: .local) else { return }
                Task { await session.setLocation(coordinate, throttled: false) }
            }
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                SearchPanel(namespace: glass).padding(20)
            }
            .overlay(alignment: .topTrailing) {
                ControlCluster(camera: $camera, namespace: glass).padding(20)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 16) {
                    StatusPill(namespace: glass)
                    JoystickPad(namespace: glass)
                }
                .padding(.bottom, 24)
            }
        }
        .fileImporter(
            isPresented: $session.isImporting,
            allowedContentTypes: [.xml, .init(filenameExtension: "gpx") ?? .xml]
        ) { result in
            guard case .success(let url) = result,
                  let points = try? GPXImporter.waypoints(at: url)
            else { return }
            session.play(route: Geodesy.densify(points, speedKmh: session.speed))
        }
    }
}

/// Pastille bleue façon Plans, halo compris.
struct SimulatedDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.tint.opacity(0.22))
                .frame(width: pulsing ? 64 : 44, height: pulsing ? 64 : 44)
            Circle()
                .fill(.tint)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(.white, lineWidth: 3.5))
        }
        .animation(.easeInOut(duration: 1.8).repeatForever(), value: pulsing)
        .onAppear { pulsing = true }
    }
}
