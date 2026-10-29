import CoreBluetooth

/// Advertises a small Bluetooth LE signal. The iPhone reads its strength to know when it's been
/// brought right up to the Mac — that's the NameDrop-style "hold it close" moment. Nothing connects
/// over Bluetooth here; files travel over MultipeerConnectivity.
final class ProximityBeacon: NSObject, CBPeripheralManagerDelegate {
    static let shared = ProximityBeacon()

    private var manager: CBPeripheralManager?
    private var shortId = ""
    private var serviceAdded = false

    /// on | off | denied | unsupported | starting
    private(set) var state = "starting"
    var onChange: (() -> Void)?

    func start(shortId: String) {
        self.shortId = shortId
        if let manager {
            if manager.state == .poweredOn { advertise() }
            return
        }
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func stop() {
        manager?.stopAdvertising()
        manager?.removeAllServices()
        manager = nil
        serviceAdded = false
    }

    private func advertise() {
        guard let manager, manager.state == .poweredOn else { return }
        let uuid = CBUUID(string: Brand.proximityService)
        if !serviceAdded {
            manager.add(CBMutableService(type: uuid, primary: true))
            serviceAdded = true
        }
        manager.stopAdvertising()
        // The local name carries the start of this Mac's id, so a phone near two Macs knows which is which.
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [uuid],
                                  CBAdvertisementDataLocalNameKey: "P\(shortId)"])
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn: state = "on"; advertise()
        case .poweredOff: state = "off"; serviceAdded = false
        case .unauthorized: state = "denied"
        case .unsupported: state = "unsupported"
        default: state = "starting"
        }
        onChange?()
    }
}
