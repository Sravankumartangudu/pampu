import AppKit
import MultipeerConnectivity

/// Listens for iPhones over MultipeerConnectivity (peer-to-peer Wi-Fi + Bluetooth, the same links
/// AirDrop uses), checks they're paired, and files whatever they send.
final class Receiver: NSObject {
    static let shared = Receiver()

    /// Called on the main thread whenever something the menu shows changes.
    var onChange: (() -> Void)?
    /// Newest first, at most 15.
    private(set) var recent: [URL] = []

    private struct Peer {
        var nonce = Proof.random(16).base64EncodedString()
        var deviceId: String?
        var name = "iPhone"
        var authed = false
        var expected = 0
        var done = 0
        var saved: [URL] = []
        var inFlight: [String: Double] = [:]
    }

    private let me: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private let lock = NSLock()
    private var peers: [MCPeerID: Peer] = [:]
    private var observers: [String: NSKeyValueObservation] = [:]
    private var lastProgress = Date.distantPast
    private var pairing = false
    private(set) var advertiseError: String?

    let macName = Host.current().localizedName ?? "Mac"

    private override init() {
        me = Receiver.loadPeerID(named: Host.current().localizedName ?? "Mac")
        session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    // MARK: Start / stop

    var isRunning: Bool { advertiser != nil }

    func start() {
        guard advertiser == nil else { return }
        let info = ["id": Prefs.shared.macId, "v": String(Brand.protocolVersion)]
        let a = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: info, serviceType: Brand.serviceType)
        a.delegate = self
        a.startAdvertisingPeer()
        advertiser = a
        advertiseError = nil
        ProximityBeacon.shared.start(shortId: String(Prefs.shared.macId.prefix(8)))
        onChange?()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session.disconnect()
        lock.withLock { peers.removeAll(); observers.removeAll() }
        ProximityBeacon.shared.stop()
        onChange?()
    }

    /// Names of the paired iPhones connected right now.
    var connectedNames: [String] { lock.withLock { peers.values.filter(\.authed).map(\.name) } }

    /// Drops the connection of a phone you just forgot, so it has to pair again.
    func disconnect(deviceId: String?) {
        let gone = lock.withLock { peers.filter { deviceId == nil || $0.value.deviceId == deviceId }.map(\.key) }
        for p in gone { send(Wire(t: "denied"), to: p) }
        if !gone.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.session.disconnect() } }
    }

    // MARK: Helpers

    /// Reusing the same MCPeerID across launches stops phones seeing a "new" Mac every time.
    private static func loadPeerID(named name: String) -> MCPeerID {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "peerID"),
           let id = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data),
           id.displayName == name {
            return id
        }
        let id = MCPeerID(displayName: name)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: id, requiringSecureCoding: true) {
            d.set(data, forKey: "peerID")
        }
        return id
    }

    private func send(_ w: Wire, to peer: MCPeerID) {
        try? session.send(w.data, toPeers: [peer], with: .reliable)
    }

    private func changed() { DispatchQueue.main.async { self.onChange?() } }

    private func remember(_ urls: [URL]) {
        recent.insert(contentsOf: urls.reversed(), at: 0)
        if recent.count > 15 { recent.removeLast(recent.count - 15) }
    }

    private func key(_ peer: MCPeerID, _ name: String) -> String { "\(peer.hash)|\(name)" }

    // MARK: Messages

    private func handle(_ w: Wire, from peer: MCPeerID) {
        switch w.t {
        case "auth":
            guard let id = w.id, let proof = w.proof else { return }
            let nonce = lock.withLock { peers[peer]?.nonce }
            if let nonce, let device = Devices.shared.find(id), let secret = Data(base64Encoded: device.secret),
               Proof.check(proof, secret: secret, device: id, nonce: nonce) {
                let name = w.name ?? device.name
                lock.withLock {
                    peers[peer]?.authed = true
                    peers[peer]?.deviceId = id
                    peers[peer]?.name = name
                }
                Devices.shared.touch(id, name: name)
                send(Wire(t: "ok", id: Prefs.shared.macId, name: macName), to: peer)
                changed()
            } else {
                send(Wire(t: "denied"), to: peer)
            }

        case "pair":
            guard let id = w.id, let code = w.code else { return }
            let name = w.name ?? "iPhone"
            DispatchQueue.main.async { self.askToPair(peer, id: id, name: name, code: code) }

        case "near", "far", "pull", "fling", "batch", "text":
            guard let p = lock.withLock({ peers[peer] }), p.authed else { return }
            switch w.t {
            case "near": DispatchQueue.main.async { DropPanel.shared.near(from: p.name) }
            case "far": DispatchQueue.main.async { DropPanel.shared.far() }
            case "pull":
                let f = min(max(w.f ?? 0, 0), 1)
                DispatchQueue.main.async { DropPanel.shared.pull(f, from: p.name) }
            case "fling":
                let kinds = (w.kinds ?? []).prefix(3)
                let thumbs = w.thumbs ?? []
                let cards = kinds.enumerated().map { i, kind in
                    DropModel.Card(image: thumbs.indices.contains(i) ? Data(base64Encoded: thumbs[i]).flatMap(NSImage.init(data:)) : nil,
                                   symbol: kind)
                }
                let count = max(w.count ?? cards.count, 0)
                DispatchQueue.main.async { DropPanel.shared.fling(from: p.name, count: count, cards: cards) }
            case "batch":
                let count = max(w.count ?? 0, 0)
                lock.withLock {
                    peers[peer]?.expected = count
                    peers[peer]?.done = 0
                    peers[peer]?.saved = []
                    peers[peer]?.inFlight = [:]
                }
                DispatchQueue.main.async { DropPanel.shared.begin(from: p.name, count: count, names: w.names ?? []) }
            default:
                if let text = w.text { DispatchQueue.main.async { self.receivedText(text, from: p.name) } }
            }

        default:
            break
        }
    }

    private func askToPair(_ peer: MCPeerID, id: String, name: String, code: String) {
        guard !pairing else { return }   // one question at a time; the phone simply waits
        guard Prefs.shared.receiving else { send(Wire(t: "denied"), to: peer); return }
        pairing = true
        defer { pairing = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow “\(name)” to send files to this Mac?"
        alert.informativeText = "Check that the iPhone shows the code \(code). Only allow an iPhone you own: once paired, it can drop files here without asking."
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        let allowed = alert.runModal() == .alertFirstButtonReturn
        guard lock.withLock({ peers[peer] != nil }) else { return }   // the phone left while we asked
        if allowed {
            let secret = Devices.shared.add(id: id, name: name)
            lock.withLock {
                peers[peer]?.authed = true
                peers[peer]?.deviceId = id
                peers[peer]?.name = name
            }
            send(Wire(t: "paired", id: Prefs.shared.macId, name: macName, secret: secret.base64EncodedString()), to: peer)
        } else {
            send(Wire(t: "denied"), to: peer)
        }
        onChange?()
    }

    private func receivedText(_ raw: String, from: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        var link: URL?
        if !text.contains(where: \.isWhitespace), let u = URL(string: text), ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
            link = u
            if Prefs.shared.openLinks { NSWorkspace.shared.open(u) }
        }
        DropPanel.shared.text(text, link: link, from: from)
        if Prefs.shared.playSound { NSSound(named: "Pop")?.play() }
    }

    /// Overall share of the current batch that has arrived, 0…1.
    private func fraction(_ p: Peer) -> Double {
        let total = max(p.expected, p.done + p.inFlight.count, 1)
        return min(1, (Double(p.done) + p.inFlight.values.reduce(0, +)) / Double(total))
    }
}

// MARK: - MultipeerConnectivity

extension Receiver: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Anyone may connect; nothing is accepted until they prove they're paired (or you allow them).
        invitationHandler(Prefs.shared.receiving, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.advertiseError = error.localizedDescription
            self.onChange?()
        }
    }
}

extension Receiver: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            let p = Peer()
            lock.withLock { peers[peerID] = p }
            send(Wire(t: "hello", id: Prefs.shared.macId, name: macName, nonce: p.nonce), to: peerID)
        case .notConnected:
            let left = lock.withLock { peers.removeValue(forKey: peerID) }
            if left?.authed == true { DispatchQueue.main.async { DropPanel.shared.lost() } }
        default:
            break
        }
        changed()
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let w = Wire.decode(data) else { return }
        handle(w, from: peerID)
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName name: String, fromPeer peerID: MCPeerID,
                 with progress: Progress) {
        guard Prefs.shared.receiving, let p = lock.withLock({ peers[peerID] }), p.authed else {
            progress.cancel()
            return
        }
        let k = key(peerID, name)
        let obs = progress.observe(\.fractionCompleted) { [weak self] prog, _ in
            guard let self else { return }
            // A few updates a second is plenty for a progress bar.
            let (frac, from): (Double?, String) = self.lock.withLock {
                self.peers[peerID]?.inFlight[name] = prog.fractionCompleted
                guard Date().timeIntervalSince(self.lastProgress) > 0.15 else { return (nil, "") }
                self.lastProgress = Date()
                return (self.peers[peerID].map(self.fraction), self.peers[peerID]?.name ?? "")
            }
            guard let frac else { return }
            DispatchQueue.main.async { DropPanel.shared.progress(frac, current: name, from: from) }
        }
        lock.withLock {
            peers[peerID]?.inFlight[name] = 0
            observers[k] = obs
        }
        if p.expected == 0 { DispatchQueue.main.async { DropPanel.shared.begin(from: p.name, count: 1, names: [name]) } }
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName name: String, fromPeer peerID: MCPeerID,
                 at localURL: URL?, withError error: Error?) {
        lock.withLock { observers[key(peerID, name)] = nil }
        guard let p = lock.withLock({ peers[peerID] }), p.authed else {
            if let localURL { try? FileManager.default.removeItem(at: localURL) }
            return
        }
        var saved: URL?
        var problem = error?.localizedDescription
        if let localURL, error == nil {
            do {
                saved = try Filing.file(localURL, named: name, base: Prefs.shared.folder, sort: Prefs.shared.sortByType)
            } catch {
                problem = error.localizedDescription
            }
        }
        let now: Peer? = lock.withLock {
            peers[peerID]?.inFlight[name] = nil
            peers[peerID]?.done += 1
            if let saved { peers[peerID]?.saved.append(saved) }
            return peers[peerID]
        }
        if let saved { send(Wire(t: "saved", name: saved.lastPathComponent), to: peerID) }
        guard let now else { return }
        let finished = now.done >= max(now.expected, 1)
        let files = now.saved
        DispatchQueue.main.async {
            if let saved { self.remember([saved]) }
            if let problem { DropPanel.shared.failed("Couldn’t save \(SafeName.clean(name)): \(problem)") }
            if finished {
                if !files.isEmpty {
                    DropPanel.shared.done(files: files, from: now.name)
                    if Prefs.shared.playSound { NSSound(named: "Glass")?.play() }
                }
            } else {
                DropPanel.shared.progress(self.fraction(now), current: name, from: now.name)
            }
            self.onChange?()
        }
        if finished { lock.withLock { peers[peerID]?.expected = 0; peers[peerID]?.done = 0; peers[peerID]?.saved = [] } }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID,
                 certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}
