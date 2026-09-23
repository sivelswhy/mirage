import Foundation
import MapKit
import Observation

/// Recherche de lieux : suggestions au fil de la frappe, puis résolution de
/// la suggestion choisie en coordonnées.
@MainActor
@Observable
final class PlaceSearch: NSObject {

    struct Suggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion?
    }

    struct Place {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    enum SearchError: LocalizedError {
        case noResult(String)

        var errorDescription: String? {
            switch self {
            case .noResult(let query): "Aucun lieu trouvé pour « \(query) »"
            }
        }
    }

    private(set) var suggestions: [Suggestion] = []
    private(set) var isResolving = false
    var failure: String?

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Relance les suggestions, en privilégiant la zone visible de la carte.
    func update(query: String, near region: MKCoordinateRegion?) {
        failure = nil
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            completer.cancel()
            suggestions = []
            return
        }
        if let region { completer.region = region }
        completer.queryFragment = trimmed
    }

    func reset() {
        completer.cancel()
        suggestions = []
        failure = nil
    }

    /// Résout une suggestion, ou le texte brut si aucune n'est choisie.
    func resolve(_ suggestion: Suggestion?, query: String,
                 near region: MKCoordinateRegion?) async throws -> Place {
        isResolving = true
        defer { isResolving = false }

        let request: MKLocalSearch.Request
        if let completion = suggestion?.completion {
            request = MKLocalSearch.Request(completion: completion)
        } else {
            request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let region { request.region = region }
        }
        request.resultTypes = [.address, .pointOfInterest]

        let label = suggestion?.title ?? query
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            throw SearchError.noResult(label)
        }
        return Place(name: item.name ?? label, coordinate: item.location.coordinate)
    }
}

extension PlaceSearch: MKLocalSearchCompleterDelegate {

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            suggestions = completer.results.prefix(6).map {
                Suggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter,
                               didFailWithError error: Error) {
        MainActor.assumeIsolated {
            suggestions = []
            // Une frappe rapide annule la requête précédente : ce n'est pas un échec.
            if (error as NSError).code != MKError.Code.unknown.rawValue {
                failure = error.localizedDescription
            }
        }
    }
}
