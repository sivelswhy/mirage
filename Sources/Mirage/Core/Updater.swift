import Foundation
import Observation
import AppKit

struct Release: Sendable {
    let version: SemanticVersion
    let tag: String
    let notes: String
    let downloadURL: URL
    let size: Int
}

struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    let components: [Int]

    init?(_ string: String) {
        let cleaned = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let head = cleaned.split(separator: "-").first.map(String.init) ?? cleaned
        let parts = head.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        components = parts
    }

    static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        for i in 0..<max(a.components.count, b.components.count) {
            let lhs = i < a.components.count ? a.components[i] : 0
            let rhs = i < b.components.count ? b.components[i] : 0
            if lhs != rhs { return lhs < rhs }
        }
        return false
    }

    var description: String { components.map(String.init).joined(separator: ".") }
}

@MainActor
@Observable
final class Updater {

    enum Phase: Equatable {
        case idle
        case checking
        case available(Release)
        case downloading(Double)
        case ready(URL)
        case failed(String)

        static func == (a: Phase, b: Phase) -> Bool {
            String(describing: a) == String(describing: b)
        }
    }

    var phase: Phase = .idle

    private let repository = "sivelswhy/mirage"
    private let skippedKey = "MirageSkippedVersion"

    var currentVersion: SemanticVersion {
        SemanticVersion(
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        ) ?? SemanticVersion("0")!
    }

    /// Appelé au lancement. Silencieux si aucune mise à jour, jamais bloquant.
    func checkAtLaunch() async {
        guard case .idle = phase else { return }
        phase = .checking

        do {
            guard let release = try await latestRelease() else {
                phase = .idle
                return
            }
            let skipped = UserDefaults.standard.string(forKey: skippedKey)
            guard release.version > currentVersion, release.tag != skipped else {
                phase = .idle
                return
            }
            phase = .available(release)
        } catch {
            phase = .idle
        }
    }

    func skip(_ release: Release) {
        UserDefaults.standard.set(release.tag, forKey: skippedKey)
        phase = .idle
    }

    private func latestRelease() async throws -> Release? {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let version = SemanticVersion(tag),
              let assets = json["assets"] as? [[String: Any]]
        else { return nil }

        guard let dmg = assets.first(where: {
            ($0["name"] as? String)?.hasSuffix(".dmg") == true
        }),
              let urlString = dmg["browser_download_url"] as? String,
              let url = URL(string: urlString)
        else { return nil }

        return Release(
            version: version,
            tag: tag,
            notes: json["body"] as? String ?? "",
            downloadURL: url,
            size: dmg["size"] as? Int ?? 0
        )
    }

    /// Télécharge le DMG puis le monte. Le remplacement reste manuel,
    /// car écraser un bundle en cours d'exécution demande un helper dédié.
    func download(_ release: Release) async {
        phase = .downloading(0)
        do {
            let (temporary, _) = try await URLSession.shared.download(from: release.downloadURL)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("Mirage-\(release.tag).dmg")

            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)

            phase = .ready(destination)
            NSWorkspace.shared.open(destination)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
