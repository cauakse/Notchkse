import AppKit
import IOBluetooth
import IOKit.ps
import Observation

// MARK: - Bateria / carregador (evento do IOKit, sem polling)

nonisolated private func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.read(notify: true) }
}

@Observable
final class BatteryMonitor {
    private(set) var level = 100
    private(set) var isCharging = false
    private(set) var onAC = false
    private(set) var hasBattery = false

    @ObservationIgnored var onPowerConnected: ((Int) -> Void)?
    @ObservationIgnored private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource(powerSourceChanged, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        source = src
        read(notify: false)
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    func read(notify: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        let wasOnAC = onAC
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            hasBattery = true
            level = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
            onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        }
        if notify && onAC && !wasOnAC { onPowerConnected?(level) }
    }
}

// MARK: - Bluetooth (notificação de conexão do IOBluetooth)

struct ConnectedDevice {
    var name: String
    var symbol: String
    var battery: String?
    var shortBattery: String?
}

final class BluetoothMonitor: NSObject {
    var onConnect: ((ConnectedDevice) -> Void)?
    var onBattery: ((ConnectedDevice) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date()

    func start() {
        guard connectNotification == nil else { return }
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Ao registrar, o sistema avisa sobre o que já estava conectado: ignorar.
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        let name = device.name ?? "Dispositivo"
        let info = ConnectedDevice(name: name, symbol: Self.symbol(for: device, name: name))
        onConnect?(info)

        // A bateria só aparece no sistema alguns segundos depois de conectar.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) { [weak self] in
            let battery = Self.batteryLevels(for: name)
            DispatchQueue.main.async {
                guard let battery else { return }
                var updated = info
                updated.battery = battery.full
                updated.shortBattery = battery.short
                self?.onBattery?(updated)
            }
        }
    }

    private static func symbol(for device: IOBluetoothDevice, name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("watch") { return "applewatch" }
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if lower.contains("keyboard") || lower.contains("teclado") { return "keyboard" }
        if lower.contains("mouse") { return "magicmouse" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if lower.contains("controller") || lower.contains("dualsense") || lower.contains("xbox") { return "gamecontroller" }
        switch device.deviceClassMajor {
        case UInt32(kBluetoothDeviceClassMajorAudio): return "headphones"
        case UInt32(kBluetoothDeviceClassMajorPeripheral): return "keyboard"
        case UInt32(kBluetoothDeviceClassMajorPhone): return "iphone"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    /// Lê a bateria pelo system_profiler (roda só quando algo conecta).
    nonisolated private static func batteryLevels(for name: String) -> (full: String, short: String)? {
        guard let json = Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                guard let props = entry[name] as? [String: Any] else { continue }
                let left = props["device_batteryLevelLeft"] as? String
                let right = props["device_batteryLevelRight"] as? String
                let caseLevel = props["device_batteryLevelCase"] as? String
                let main = props["device_batteryLevelMain"] as? String ?? props["device_batteryLevel"] as? String
                if left != nil || right != nil {
                    var parts: [String] = []
                    if let left { parts.append("E \(left)") }
                    if let right { parts.append("D \(right)") }
                    if let caseLevel { parts.append("Estojo \(caseLevel)") }
                    let levels = [left, right].compactMap { $0?.replacingOccurrences(of: "%", with: "") }.compactMap(Int.init)
                    let short = levels.min().map { "\($0)%" } ?? left ?? right ?? ""
                    return (parts.joined(separator: " · "), short)
                }
                if let main { return (main, main) }
            }
        }
        return nil
    }
}

// MARK: - Downloads (eventos da pasta + NSProgress publicado pelos navegadores)

@Observable
final class DownloadsMonitor {
    struct Active: Identifiable, Equatable {
        var id: String { path }
        let path: String
        var name: String
        var progress: Double?
    }

    private(set) var active: [Active] = []

    @ObservationIgnored var onChange: (([Active]) -> Void)?
    @ObservationIgnored var onFinished: ((URL) -> Void)?

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var subscriber: Any?
    @ObservationIgnored private var progressByName: [String: Double] = [:]
    @ObservationIgnored private var observations: [String: NSKeyValueObservation] = [:]
    @ObservationIgnored private var lastEmit = Date.distantPast

    private static let partialExtensions: Set<String> = ["download", "crdownload", "part", "opdownload", "partial"]
    private let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    func start() {
        guard source == nil else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src

        subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            let name = Self.baseName(progress.fileURL ?? URL(fileURLWithPath: "/"))
            let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
                let value = p.fractionCompleted
                DispatchQueue.main.async { self?.updateProgress(name: name, value: value) }
            }
            DispatchQueue.main.async { self?.observations[name] = observation }
            return {
                DispatchQueue.main.async {
                    self?.observations[name] = nil
                    self?.progressByName[name] = nil
                }
            }
        }
        scan()
    }

    func stop() {
        source?.cancel()
        source = nil
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        observations.removeAll()
        active = []
        onChange?(active)
    }

    private func updateProgress(name: String, value: Double) {
        progressByName[name] = value
        // No máximo ~4 atualizações de interface por segundo.
        guard Date().timeIntervalSince(lastEmit) > 0.25 else { return }
        lastEmit = Date()
        apply(active.map { item in
            var copy = item
            copy.progress = progressByName[item.name] ?? copy.progress
            return copy
        })
    }

    private func scan() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let partial = contents.filter { Self.partialExtensions.contains($0.pathExtension.lowercased()) }
        let currentPaths = Set(partial.map(\.path))

        for finished in active where !currentPaths.contains(finished.path) {
            let final = URL(fileURLWithPath: finished.path).deletingPathExtension()
            if FileManager.default.fileExists(atPath: final.path) { onFinished?(final) }
        }
        apply(partial.map { url in
            let name = Self.baseName(url)
            return Active(path: url.path, name: name, progress: progressByName[name])
        })
    }

    private func apply(_ list: [Active]) {
        guard list != active else { return }
        active = list
        onChange?(list)
    }

    nonisolated private static func baseName(_ url: URL) -> String {
        partialExtensions.contains(url.pathExtension.lowercased())
            ? url.deletingPathExtension().lastPathComponent
            : url.lastPathComponent
    }
}

// MARK: - Capturas de tela (Spotlight marca kMDItemIsScreenCapture)

final class ScreenshotMonitor {
    var onNew: ((URL) -> Void)?

    private var query: NSMetadataQuery?
    private var seen = Set<String>()
    private var tokens: [NSObjectProtocol] = []

    func start() {
        guard query == nil else { return }
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate >= %@", Date() as NSDate)
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.notificationBatchingInterval = 0.5
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.collect() }
            })
        }
        q.start()
        query = q
    }

    func stop() {
        query?.stop()
        query = nil
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
    }

    private func collect() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !seen.contains(path) else { continue }
            seen.insert(path)
            onNew?(URL(fileURLWithPath: path))
        }
    }
}
