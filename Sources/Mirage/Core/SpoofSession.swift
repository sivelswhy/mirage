import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class SpoofSession {

    var devices: [Device] = []
    var selected: Device?
    var tunnel: TunnelState = .idle
    var simulated: CLLocationCoordinate2D?
    var speed: Double = 4.2
    var recents: [Waypoint] = []
    var isImporting = false
    var lastError: String?

    private var tunnelProcess: Process?
    private var monitor: Task<Void, Never>?
    private var motion: Task<Void, Never>?
    private var lastSent: Date = .distantPast

    // MARK: Appareils

    /// Sonde le bus USB en continu pour détecter branchement et débranchement.
    func startMonitoring() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.discoverDevices()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func discoverDevices() async {
        do {
            let json = try await PMD3.run(["usbmux", "list"])
            let found = Self.parseDevices(json)
            let appeared = devices.isEmpty && !found.isEmpty
            let vanished = !devices.isEmpty && found.isEmpty

            devices = found
            lastError = nil

            if vanished {
                stopDriving()
                stopTunnel()
                simulated = nil
                selected = nil
            }
            if selected == nil || !found.contains(where: { $0.id == selected?.id }) {
                selected = found.first
            }
            if appeared, let device = selected, device.needsTunnel {
                Task { await startTunnel() }
            }
        } catch {
            devices = []
            selected = nil
            lastError = error.localizedDescription
        }
    }

    static func parseDevices(_ json: String) -> [Device] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return array.compactMap { entry in
            guard let udid = entry["Identifier"] as? String ?? entry["UniqueDeviceID"] as? String
            else { return nil }
            return Device(
                id: udid,
                name: entry["DeviceName"] as? String ?? "iPhone",
                productVersion: entry["ProductVersion"] as? String ?? "0"
            )
        }
    }

    // MARK: Tunnel

    func startTunnel() async {
        guard let device = selected else { return }
        guard device.needsTunnel else {
            tunnel = .up(RSDEndpoint(address: "", port: 0))
            return
        }

        tunnel = .starting
        do {
            _ = try? await PMD3.run(["mounter", "auto-mount"])
            let (process, lines) = try PMD3.stream(["lockdown", "start-tunnel"], privileged: true)
            tunnelProcess = process

            for await line in lines {
                if let endpoint = Self.parseRSD(from: line, current: tunnel.endpoint) {
                    tunnel = .up(endpoint)
                }
                if line.lowercased().contains("permission denied") {
                    tunnel = .failed("Privilèges root requis")
                }
            }
            if tunnel.endpoint == nil { tunnel = .failed("Tunnel interrompu") }
        } catch {
            tunnel = .failed(error.localizedDescription)
        }
    }

    private static var pendingAddress: String?

    static func parseRSD(from line: String, current: RSDEndpoint?) -> RSDEndpoint? {
        if let range = line.range(of: #"RSD Address:\s*([0-9a-fA-F:.]+)"#, options: .regularExpression) {
            pendingAddress = String(line[range]).components(separatedBy: ":").dropFirst().joined(separator: ":")
                .trimmingCharacters(in: .whitespaces)
        }
        if let range = line.range(of: #"RSD Port:\s*(\d+)"#, options: .regularExpression),
           let port = Int(String(line[range]).filter(\.isNumber)),
           let address = pendingAddress {
            return RSDEndpoint(address: address, port: port)
        }
        return nil
    }

    func stopTunnel() {
        tunnelProcess?.terminate()
        tunnelProcess = nil
        tunnel = .idle
    }

    // MARK: Localisation

    private var rsdArgs: [String] {
        guard let e = tunnel.endpoint, !e.address.isEmpty else { return [] }
        return ["--rsd", e.address, String(e.port)]
    }

    func setLocation(_ coordinate: CLLocationCoordinate2D, throttled: Bool = true) async {
        if throttled, Date().timeIntervalSince(lastSent) < 0.9 { return }
        lastSent = .now
        simulated = coordinate

        do {
            try await PMD3.run(
                ["developer", "dvt", "simulate-location", "set"] + rsdArgs
                + ["--", String(coordinate.latitude), String(coordinate.longitude)]
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearLocation() async {
        motion?.cancel()
        simulated = nil
        _ = try? await PMD3.run(["developer", "dvt", "simulate-location", "clear"] + rsdArgs)
    }

    // MARK: Déplacement continu

    /// Avance en continu selon un cap et une vitesse, une trame par seconde.
    func drive(bearing: Double) {
        motion?.cancel()
        motion = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let origin = self.simulated else { return }
                let next = Geodesy.destination(
                    from: origin,
                    bearing: bearing,
                    metres: self.speed / 3.6
                )
                await self.setLocation(next, throttled: false)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopDriving() {
        motion?.cancel()
        motion = nil
    }

    func play(route: [CLLocationCoordinate2D]) {
        motion?.cancel()
        motion = Task { [weak self] in
            for point in route {
                guard let self, !Task.isCancelled else { return }
                await self.setLocation(point, throttled: false)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
