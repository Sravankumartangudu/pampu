import CoreBluetooth
import Foundation

/// Reads the Bluetooth signal each Pampu Mac sends out and decides when the iPhone has been brought
/// close — the NameDrop moment. Signal strength is noisy, so it's smoothed, needs two strong
/// readings in a row to count as close, and has to drop well below the line to count as far again.
@MainActor
final class Proximity: NSObject, ObservableObject {
    /// Smoothed dBm per Mac, keyed by the start of the Mac's id.
    @Published private(set) var signal: [String: Double] = [:]
    @Published private(set) var isClose = false
    /// on | off | denied | unsupported | starting
    @Published private(set) var bluetooth = "starting"

    /// Which Mac to watch (first 8 characters of its id). nil watches the strongest one.
    var target: String? { didSet { evaluate() } }
    var threshold: Double = DropSettings.closeness.dBm { didSet { evaluate() } }

    private var central: CBCentralManager?
    private var seen: [String: Date] = [:]
    private var strongHits = 0
    private var sweep: Timer?

    func start() {
        if central == nil { central = CBCentralManager(delegate: self, queue: nil) }
        else { scan() }
        sweep?.invalidate()
        sweep = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.forgetStale() }
        }
    }

    func stop() {
        central?.stopScan()
        sweep?.invalidate()
        sweep = nil
        signal = [:]
        seen = [:]
        isClose = false
        strongHits = 0
    }

    /// Signal for the watched Mac, or nil if it isn't heard. iOS often hears the Mac's beacon
    /// without its name; those adverts can't say which Mac they're from, so the strongest one
    /// stands in for the watched Mac when it isn't heard by name.
    var current: Double? {
        if let target {
            return signal[target] ?? signal.filter { $0.key.hasPrefix(Self.unnamed) }.values.max()
        }
        return signal.values.max()
    }

    private static let unnamed = "?"

    /// 0…1 for a meter: −90 dBm is nothing, −35 dBm is touching.
    var strength: Double {
        guard let v = current else { return 0 }
        return min(1, max(0, (v + 90) / 55))
    }

    private func scan() {
        guard let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [CBUUID(string: Brand.proximityService)],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func heard(_ id: String, rssi: Double) {
        guard rssi < 0, rssi > -110 else { return }   // 127 means "unknown"
        let old = signal[id]
        signal[id] = old.map { $0 * 0.6 + rssi * 0.4 } ?? rssi
        seen[id] = Date()
        evaluate()
    }

    private func evaluate() {
        guard let v = current else {
            if isClose { isClose = false }
            strongHits = 0
            return
        }
        if v >= threshold {
            strongHits += 1
            if strongHits >= 2 && !isClose { isClose = true }
        } else {
            strongHits = 0
            if isClose && v < threshold - 7 { isClose = false }
        }
    }

    private func forgetStale() {
        let now = Date()
        for (id, t) in seen where now.timeIntervalSince(t) > 3 {
            seen[id] = nil
            signal[id] = nil
        }
        evaluate()
    }
}

extension Proximity: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated {
            switch state {
            case .poweredOn: bluetooth = "on"; scan()
            case .poweredOff: bluetooth = "off"
            case .unauthorized: bluetooth = "denied"
            case .unsupported: bluetooth = "unsupported"
            default: bluetooth = "starting"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // The Mac's beacon is named "P" + the start of its id. Without the name, the Bluetooth address
        // keeps each unnamed Mac apart.
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let id = name.hasPrefix("P") && name.count > 1 ? String(name.dropFirst())
                                                       : Self.unnamed + peripheral.identifier.uuidString
        let value = RSSI.doubleValue
        MainActor.assumeIsolated { heard(id, rssi: value) }
    }
}
