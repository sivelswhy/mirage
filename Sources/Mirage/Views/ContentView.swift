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
                if let route = session.route {
                    MapPolyline(coordinates: route.polyline)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round,
                                                          lineJoin: .round))
                }
                if let destination = session.routeDestination {
                    Annotation("", coordinate: destination) { DestinationPin() }
                }
                if let point = session.simulated {
                    Annotation("", coordinate: point) { SimulatedDot() }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControlVisibility(.hidden)
            .onTapGesture { location in
                guard let coordinate = proxy.convert(location, from: .local) else { return }
                if NSEvent.modifierFlags.contains(.option) {
                    session.setDestination(coordinate)
                } else {
                    Task { await session.setLocation(coordinate, throttled: false) }
                }
            }
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    UpdateBanner(namespace: glass)
                    if MaterialProbe.isEnabled { MaterialProbe() }
                }
                .padding(.top, 14)
            }
            .overlay(alignment: .topLeading) {
                SearchPanel(namespace: glass).padding(20)
            }
            .overlay(alignment: .topTrailing) {
                ControlCluster(camera: $camera, namespace: glass).padding(20)
            }
            .overlay {
                if session.devices.isEmpty {
                    DeviceGate(namespace: glass)
                } else if session.developerMode == false {
                    DeveloperModeGate(namespace: glass)
                } else if needsHelper {
                    ZStack {
                        Rectangle().fill(.black.opacity(0.18)).ignoresSafeArea()
                        HelperGate(namespace: glass)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                GlassEffectContainer(spacing: 24) {
                    VStack(spacing: 14) {
                        RoutePanel(namespace: glass)
                        HStack(spacing: 20) {
                            StatusPill(namespace: glass)
                            JoystickPad(namespace: glass)
                        }
                    }
                }
                .padding(.bottom, 24)
                .opacity(session.devices.isEmpty ? 0 : 1)
            }
            .animation(.smooth(duration: 0.35), value: session.devices.isEmpty)
            .animation(.smooth(duration: 0.35), value: session.developerMode)
        }
        .task { session.helper.refresh() }
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


extension ContentView {
    /// Le démon n'a de sens que pour iOS 17 et plus, qui exige le tunnel.
    var needsHelper: Bool {
        session.selected?.needsTunnel == true && session.helper.state != .ready
    }
}

/// Épingle d'arrivée, rouge comme dans Plans.
struct DestinationPin: View {
    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 26))
            .foregroundStyle(.white, .red)
            .shadow(radius: 2)
    }
}
