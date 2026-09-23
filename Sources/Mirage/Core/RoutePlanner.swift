import Foundation
import MapKit
import CoreLocation

enum TravelMode: String, CaseIterable, Identifiable, Sendable {
    case driving, transit, cycling, walking

    var id: String { rawValue }

    var label: String {
        switch self {
        case .driving: "Voiture"
        case .transit: "Transports"
        case .cycling: "Vélo"
        case .walking: "À pied"
        }
    }

    var symbol: String {
        switch self {
        case .driving: "car.fill"
        case .transit: "tram.fill"
        case .cycling: "bicycle"
        case .walking: "figure.walk"
        }
    }

    /// Types MapKit essayés dans l'ordre. Les itinéraires vélo n'existent pas
    /// partout, et MapKit ne trace jamais les transports : on se replie alors
    /// sur la géométrie la plus proche.
    var mapKitTypes: [MKDirectionsTransportType] {
        switch self {
        case .driving: [.automobile]
        case .transit: [.automobile]
        case .cycling: [.cycling, .walking]
        case .walking: [.walking]
        }
    }

    /// Vitesse moyenne de repli en m/s quand la durée MapKit ne s'applique pas.
    var fallbackSpeed: Double {
        switch self {
        case .driving: 11.1
        case .transit: 6.9
        case .cycling: 5.0
        case .walking: 1.4
        }
    }

    /// Les arrêts marqués : feux pour la voiture, stations pour les transports.
    var stopProbability: Double {
        switch self {
        case .driving: 0.35
        case .transit: 0.6
        case .cycling: 0.15
        case .walking: 0.0
        }
    }
}

struct SimulatedRoute: Sendable {
    let polyline: [CLLocationCoordinate2D]
    /// Une trame par seconde, prête à être envoyée telle quelle.
    let frames: [CLLocationCoordinate2D]
    let distance: CLLocationDistance
    let duration: TimeInterval
    let mode: TravelMode

    var averageSpeedKmh: Double { distance / max(duration, 1) * 3.6 }
}

enum RouteError: Error, LocalizedError {
    case noRoute

    var errorDescription: String? { "Aucun itinéraire trouvé entre ces deux points." }
}

enum RoutePlanner {

    static func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        mode: TravelMode
    ) async throws -> SimulatedRoute {

        var found: MKRoute?
        for type in mode.mapKitTypes where found == nil {
            let request = directionsRequest(from: origin, to: destination, type: type)
            found = try? await MKDirections(request: request).calculate().routes.first
        }
        guard let route = found else { throw RouteError.noRoute }

        let coordinates = route.polyline.coordinates
        let duration = try await resolvedDuration(route: route, mode: mode,
                                                  origin: origin, destination: destination)

        return SimulatedRoute(
            polyline: coordinates,
            frames: frames(along: coordinates, duration: duration, mode: mode),
            distance: route.distance,
            duration: duration,
            mode: mode
        )
    }

    /// Pour les transports, MapKit donne une durée mais pas de tracé : on récupère
    /// la durée séparément et on la plaque sur la géométrie routière.
    private static func resolvedDuration(
        route: MKRoute,
        mode: TravelMode,
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {

        switch mode {
        case .driving, .walking:
            return route.expectedTravelTime

        case .transit:
            let request = directionsRequest(from: origin, to: destination, type: .transit)
            if let eta = try? await MKDirections(request: request).calculateETA() {
                return eta.expectedTravelTime
            }
            return route.distance / mode.fallbackSpeed

        case .cycling:
            // Durée MapKit si le tracé est bien cyclable, sinon vitesse moyenne.
            return route.transportType == .cycling
                ? route.expectedTravelTime
                : route.distance / mode.fallbackSpeed
        }
    }

    private static func directionsRequest(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        type: MKDirectionsTransportType
    ) -> MKDirections.Request {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: origin.latitude,
                                                        longitude: origin.longitude),
                                   address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude,
                                                             longitude: destination.longitude),
                                        address: nil)
        request.transportType = type
        return request
    }

    /// Rééchantillonne le tracé à une trame par seconde avec un profil de vitesse réaliste :
    /// ralentissement dans les virages, arrêts marqués, bruit de conduite.
    static func frames(
        along path: [CLLocationCoordinate2D],
        duration: TimeInterval,
        mode: TravelMode
    ) -> [CLLocationCoordinate2D] {

        guard path.count > 1 else { return path }

        var cumulative: [CLLocationDistance] = [0]
        for pair in zip(path, path.dropFirst()) {
            let a = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let b = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            cumulative.append(cumulative.last! + a.distance(from: b))
        }

        let total = cumulative.last ?? 0
        guard total > 0 else { return path }

        let nominal = total / max(duration, 1)

        // Les virages et les arrêts ralentissent : sur un nombre fixe de
        // trames, on n'atteignait jamais l'arrivée et la dernière trame
        // téléportait l'appareil. On avance donc jusqu'au bout du tracé,
        // avec une limite de sécurité.
        var output: [CLLocationCoordinate2D] = []
        var travelled: CLLocationDistance = 0
        var generator = SystemRandomNumberGenerator()
        let limit = max(4, Int(duration.rounded()) * 3)

        while travelled < total, output.count < limit {
            output.append(interpolate(path: path, cumulative: cumulative, at: travelled))

            let curvature = curvatureFactor(path: path, cumulative: cumulative, at: travelled)
            let noise = Double.random(in: 0.92...1.08, using: &generator)
            let stopped = Double.random(in: 0...1, using: &generator) < mode.stopProbability * 0.04

            travelled = min(total, travelled + (stopped ? 0 : nominal * curvature * noise))
        }

        output.append(path[path.count - 1])
        return output
    }

    private static func interpolate(
        path: [CLLocationCoordinate2D],
        cumulative: [CLLocationDistance],
        at distance: CLLocationDistance
    ) -> CLLocationCoordinate2D {

        guard let index = cumulative.firstIndex(where: { $0 >= distance }), index > 0
        else { return path[0] }

        let span = cumulative[index] - cumulative[index - 1]
        let t = span > 0 ? (distance - cumulative[index - 1]) / span : 0
        let a = path[index - 1], b = path[index]

        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    /// Renvoie un facteur entre 0,45 et 1 selon l'angle du virage à venir.
    private static func curvatureFactor(
        path: [CLLocationCoordinate2D],
        cumulative: [CLLocationDistance],
        at distance: CLLocationDistance
    ) -> Double {

        guard let index = cumulative.firstIndex(where: { $0 >= distance }),
              index > 0, index < path.count - 1
        else { return 1 }

        let a = path[index - 1], b = path[index], c = path[index + 1]
        let inbound = atan2(b.longitude - a.longitude, b.latitude - a.latitude)
        let outbound = atan2(c.longitude - b.longitude, c.latitude - b.latitude)

        var delta = abs(outbound - inbound)
        if delta > .pi { delta = 2 * .pi - delta }

        return max(0.45, 1 - delta / .pi)
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var buffer = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid, count: pointCount
        )
        getCoordinates(&buffer, range: NSRange(location: 0, length: pointCount))
        return buffer
    }
}
