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
    var mode: TravelMode = .driving
    var route: SimulatedRoute?
    var routeDestination: CLLocationCoordinate2D?
    var isPlanning = false
    var progress: Double = 0
    var isPaused = false
    /// La carte suit la position pendant un trajet.
    var followsRoute = true
    var routeError: String?
    var lastError: String?
    /// Dernier échec d'envoi de position, distinct de `lastError` que la
    /// détection des appareils efface toutes les deux secondes.
    var locationError: String?
    /// État du Mode développeur de l'appareil sélectionné ; nil tant qu'il
    /// n'a pas pu être lu. Sans lui, iOS refuse le service de simulation.
    var developerMode: Bool?

    private var tunnelProcess: Process?
    private var channel: LocationChannel?
    private var opening: Task<LocationChannel, Error>?
    /// Appareils pour lesquels le réglage a déjà été révélé dans Réglages.
    private var revealedDeveloperMode: Set<String> = []
    private var monitor: Task<Void, Never>?
    /// Passerelle vers le démon privilégié. Sans lui, pas d'iOS 17 et plus.
    let helper = HelperClient()
    private var motion: Task<Void, Never>?
    private var playback: [CLLocationCoordinate2D] = []
    private var playbackIndex = 0
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
                developerMode = nil
            }
            if selected == nil || !found.contains(where: { $0.id == selected?.id }) {
                selected = found.first
                developerMode = nil
            }

            // Relu à chaque passage tant qu'il n'est pas actif : l'iPhone
            // redémarre après l'activation, puis réapparaît sur le bus.
            let wasEnabled = developerMode == true
            if developerMode != true { await refreshDeveloperMode() }
            let justEnabled = !wasEnabled && developerMode == true

            if appeared || justEnabled, let device = selected, device.needsTunnel,
               developerMode != false {
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

    // MARK: Mode développeur

    private func refreshDeveloperMode() async {
        guard let device = selected else {
            developerMode = nil
            return
        }
        guard device.requiresDeveloperMode else {
            developerMode = true
            return
        }

        let output = try? await PMD3.run(["amfi", "developer-mode-status", "--udid", device.id])
        let answer = output?
            .split(separator: "\n")
            .last?
            .trimmingCharacters(in: .whitespaces)

        switch answer {
        case "true":
            developerMode = true
        case "false":
            developerMode = false
            // Le réglage reste caché dans iOS tant qu'aucun outil de
            // développement ne l'a demandé : on le fait apparaître une fois.
            if revealedDeveloperMode.insert(device.id).inserted {
                _ = try? await PMD3.run(["amfi", "reveal-developer-mode", "--udid", device.id])
            }
        default:
            developerMode = nil
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
        _ = try? await PMD3.run(["mounter", "auto-mount"])

        helper.refresh()
        guard helper.state == .ready else {
            tunnel = .failed(helper.state.label)
            return
        }

        do {
            tunnel = .up(try await helper.startTunnel(udid: device.id))
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
        closeChannel()
        tunnelProcess?.terminate()
        tunnelProcess = nil
        tunnel = .idle
        Task { await helper.stopTunnel() }
    }

    // MARK: Localisation

    /// Cible du canal de simulation : le tunnel pour iOS 17 et plus, usbmux avant.
    private var channelTarget: LocationChannel.Target? {
        guard let device = selected else { return nil }
        if let endpoint = tunnel.endpoint, !endpoint.address.isEmpty {
            return .rsd(endpoint)
        }
        return device.needsTunnel ? nil : .usbmux(udid: device.id)
    }

    /// Canal ouvert à la demande et rouvert si le tunnel a changé ou s'il est tombé.
    private func locationChannel() async throws -> LocationChannel {
        if let opening { return try await opening.value }
        guard let target = channelTarget else {
            throw PMD3Error.failed(code: 0, stderr: "Tunnel non ouvert : \(tunnel.label)")
        }
        if let channel, channel.target == target, channel.isAlive { return channel }

        closeChannel()
        let task = Task {
            let new = LocationChannel(target: target)
            try await new.open()
            return new
        }
        opening = task
        defer { opening = nil }

        let new = try await task.value
        channel = new
        return new
    }

    private func closeChannel() {
        channel?.close()
        channel = nil
    }

    /// La position n'est affichée comme simulée qu'une fois confirmée par l'appareil.
    func setLocation(_ coordinate: CLLocationCoordinate2D, throttled: Bool = true) async {
        if throttled, Date().timeIntervalSince(lastSent) < 0.9 { return }
        lastSent = .now

        do {
            try await locationChannel().set(latitude: coordinate.latitude,
                                             longitude: coordinate.longitude)
            simulated = coordinate
            locationError = nil
        } catch {
            closeChannel()
            locationError = error.localizedDescription
        }
    }

    func clearLocation() async {
        motion?.cancel()
        simulated = nil
        try? await channel?.clear()
        closeChannel()
    }

    // MARK: Déplacement continu

    /// Avance en continu selon un cap et une vitesse, une trame par seconde.
    func drive(bearing: Double) {
        motion?.cancel()
        // Le joystick prend la main : un trajet en cours passe en pause.
        if playbackIndex < playback.count { isPaused = true }
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

    // MARK: Itinéraires

    /// Calcule le trajet depuis la position simulée, puis le joue immédiatement.
    func planRoute() async {
        routeError = nil
        guard let to = routeDestination else { return }
        guard let from = simulated else {
            routeError = "Place d'abord le départ : clique sur la carte ou cherche un lieu."
            return
        }
        isPlanning = true
        defer { isPlanning = false }

        do {
            let computed = try await RoutePlanner.route(from: from, to: to, mode: mode)
            route = computed
            play(route: computed.frames)
        } catch {
            routeError = error.localizedDescription
        }
    }

    func setDestination(_ coordinate: CLLocationCoordinate2D) {
        routeDestination = coordinate
        routeError = nil
    }

    func cancelRoute() {
        stopDriving()
        route = nil
        routeDestination = nil
        playback = []
        playbackIndex = 0
        isPaused = false
        progress = 0
        routeError = nil
    }

    /// Joue les trames depuis le début (trajet calculé ou GPX importé).
    func play(route frames: [CLLocationCoordinate2D]) {
        playback = frames
        playbackIndex = 0
        resume()
    }

    func pause() {
        stopDriving()
        isPaused = true
    }

    /// Reprend là où le trajet s'était arrêté, une trame par seconde.
    func resume() {
        motion?.cancel()
        isPaused = false
        guard playbackIndex < playback.count else { return }

        motion = Task { [weak self] in
            // Cadence calée sur l'horloge : le temps d'envoi de chaque position
            // ne s'accumule pas au fil du trajet.
            let clock = ContinuousClock()
            let start = clock.now
            var tick = 0
            while let self, !Task.isCancelled, self.playbackIndex < self.playback.count {
                await self.setLocation(self.playback[self.playbackIndex], throttled: false)
                guard !Task.isCancelled else { return }
                self.playbackIndex += 1
                self.progress = Double(self.playbackIndex) / Double(self.playback.count)
                tick += 1
                try? await Task.sleep(until: start + .seconds(tick), clock: clock)
            }
        }
    }

    var isPlaying: Bool { motion != nil && !isPaused && playbackIndex < playback.count }

    /// Temps restant, une trame valant une seconde.
    var remainingTime: TimeInterval { TimeInterval(max(0, playback.count - playbackIndex)) }

}
