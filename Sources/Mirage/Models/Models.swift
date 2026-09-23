import Foundation
import CoreLocation

struct Device: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let productVersion: String

    private var majorVersion: Int {
        Int(productVersion.split(separator: ".").first ?? "0") ?? 0
    }

    var needsTunnel: Bool { majorVersion >= 17 }

    /// Le Mode développeur n'existe, et n'est exigé, qu'à partir d'iOS 16.
    var requiresDeveloperMode: Bool { majorVersion >= 16 }
}

struct RSDEndpoint: Hashable, Sendable {
    let address: String
    let port: Int
}

enum TunnelState: Equatable, Sendable {
    case idle
    case starting
    case up(RSDEndpoint)
    case failed(String)

    var endpoint: RSDEndpoint? {
        if case .up(let e) = self { return e }
        return nil
    }

    var label: String {
        switch self {
        case .idle: "tunnel inactif"
        case .starting: "ouverture du tunnel…"
        case .up: "iPhone connecté"
        case .failed(let m): m
        }
    }
}

struct Waypoint: Identifiable, Hashable, Sendable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let name: String

    static func == (a: Waypoint, b: Waypoint) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

extension CLLocationCoordinate2D {
    var formatted: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }
}
