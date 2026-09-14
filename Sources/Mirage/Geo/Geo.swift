import Foundation
import CoreLocation

enum Geodesy {
    static let earthRadius = 6_371_000.0

    /// Point situé à `metres` d'`origin` selon un cap en degrés.
    static func destination(
        from origin: CLLocationCoordinate2D,
        bearing: Double,
        metres: Double
    ) -> CLLocationCoordinate2D {
        let angular = metres / earthRadius
        let theta = bearing * .pi / 180
        let phi1 = origin.latitude * .pi / 180
        let lambda1 = origin.longitude * .pi / 180

        let phi2 = asin(sin(phi1) * cos(angular) + cos(phi1) * sin(angular) * cos(theta))
        let lambda2 = lambda1 + atan2(
            sin(theta) * sin(angular) * cos(phi1),
            cos(angular) - sin(phi1) * sin(phi2)
        )

        return CLLocationCoordinate2D(
            latitude: phi2 * 180 / .pi,
            longitude: lambda2 * 180 / .pi
        )
    }

    /// Interpole une trace pour obtenir un point par seconde à la vitesse donnée.
    static func densify(_ route: [CLLocationCoordinate2D], speedKmh: Double) -> [CLLocationCoordinate2D] {
        guard route.count > 1 else { return route }
        let step = speedKmh / 3.6
        var output: [CLLocationCoordinate2D] = [route[0]]

        for pair in zip(route, route.dropFirst()) {
            let a = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let b = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            let distance = a.distance(from: b)
            let count = max(1, Int(distance / step))

            for i in 1...count {
                let t = Double(i) / Double(count)
                output.append(CLLocationCoordinate2D(
                    latitude: pair.0.latitude + (pair.1.latitude - pair.0.latitude) * t,
                    longitude: pair.0.longitude + (pair.1.longitude - pair.0.longitude) * t
                ))
            }
        }
        return output
    }
}

enum GPXImporter {
    static func waypoints(at url: URL) throws -> [CLLocationCoordinate2D] {
        let xml = try String(contentsOf: url, encoding: .utf8)
        let pattern = #"lat="(-?\d+\.?\d*)"\s+lon="(-?\d+\.?\d*)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(xml.startIndex..., in: xml)

        return regex.matches(in: xml, range: range).compactMap { match in
            guard let lat = Range(match.range(at: 1), in: xml).flatMap({ Double(xml[$0]) }),
                  let lon = Range(match.range(at: 2), in: xml).flatMap({ Double(xml[$0]) })
            else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }
}
