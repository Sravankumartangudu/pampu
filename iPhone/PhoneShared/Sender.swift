import Foundation
import MultipeerConnectivity
import UIKit

/// Finds Pampu Macs over MultipeerConnectivity (peer-to-peer Wi-Fi + Bluetooth — no shared network
/// needed), proves this iPhone is paired, and sends files and text.
@MainActor
final class Sender: NSObject, ObservableObject {
    struct Mac: Identifiable, Equatable {
        let id: String
        var name: String
        var peer: MCPeerID
        var paired: Bool
        var shortId: String { String(id.prefix(8)) }
    }

    enum Link: Equatable {
        case off, searching, connecting, needsPair, pairing(code: String), ready
        case denied(String)
    }

    enum Job: Equatable {
        case idle
        case sending(done: Int, total: Int)
        case sent(Int)
        case failed(String)
    }

    @Published private(set) var macs: [Mac] = []
    @Published private(set) var link: Link = .off
    @Published private(set) var job: Job = .idle
    @Published private(set) var progress = 0.0
    @Published private(set) var targetId: String?
    @Published var notice: String?

    private let me = MCPeerID(displayName: Identity.name)
    private lazy var session: MCSession = {
        let s = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()
    private var browser: MCNearbyServiceBrowser?
    private var connected: MCPeerID?
    private var retry: DispatchWorkItem?
    private var progressWatch: NSKeyValueObservation?

    var target: Mac? { macs.first { $0.id == targetId } }

    // MARK: Lifecycle

    func start() {
        guard browser == nil else { return }
        let b = MCNearbyServiceBrowser(peer: me, serviceType: Brand.serviceType)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
        if link == .off { link = .searching }
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        browser = nil
        retry?.cancel()
        session.disconnect()
        connected = nil
        macs = []
        link = .off
    }

    /// Picks which Mac to send to when more than one is around.
    func choose(_ mac: Mac) {
        guard mac.id != targetId else { return }
        targetId = mac.id
        Identity.lastMac = mac.id
        session.disconnect()
        connected = nil
        link = .searching
        connectSoon(0.3)
    }

    func pair() {
        guard let peer = connected else { return }
        let code = Proof.pairCode()
        send(Wire(t: "pair", id: Identity.deviceId, name: Identity.name, code: code), to: peer)
        link = .pairing(code: code)
    }

    func forget(_ mac: Mac) {
        Identity.setSecret(nil, for: mac.id)
        if let i = macs.firstIndex(of: mac) { macs[i].paired = false }
        if mac.id == targetId { session.disconnect(); connected = nil; link = .searching; connectSoon(0.5) }
    }

    /// Tells the Mac the phone was brought close, so it can show its own glow.
    func near(_ close: Bool) {
        guard link == .ready, let peer = connected else { return }
        send(Wire(t: close ? "near" : "far"), to: peer)
    }

    /// How far the stack has been swiped up (0…1), so the Mac's cards can follow along.
    func pull(_ f: Double, reliable: Bool) {
        guard link == .ready, let peer = connected else { return }
        try? session.send(Wire(t: "pull", f: f).data, toPeers: [peer], with: reliable ? .reliable : .unreliable)
    }

    // MARK: Sending

    var isSending: Bool { if case .sending = job { return true }; return false }

    @discardableResult
    func send(_ items: [Tray.Item], effect: DropEffect = .classic) async -> Bool {
        guard link == .ready, let peer = connected, !items.isEmpty, !isSending else { return false }
        let files = items.filter { $0.url != nil }
        let texts = items.compactMap(\.text)
        let total = files.count + texts.count
        job = .sending(done: 0, total: total)
        progress = 0
        var done = 0

        // The Mac slides these cards in straight away, before any bytes arrive.
        let shown = Array(items.prefix(3))
        send(Wire(t: "fling", count: total, kinds: shown.map(\.symbol), thumbs: shown.map { Self.card($0.thumb) }, effect: effect.rawValue), to: peer)
        for text in texts {
            send(Wire(t: "text", text: text), to: peer)
            done += 1
        }
        if !files.isEmpty {
            send(Wire(t: "batch", count: files.count, bytes: files.reduce(0) { $0 + $1.size }, names: files.map(\.name)), to: peer)
        }
        let bytesTotal = Double(max(files.reduce(0) { $0 + $1.size }, 1))
        var bytesDone = 0.0
        for f in files {
            guard let url = f.url else { continue }
            do {
                let size = Double(max(f.size, 1))
                try await sendFile(url, name: f.name, to: peer) { [weak self] frac in
                    self?.progress = min(1, (bytesDone + frac * size) / bytesTotal)
                }
                bytesDone += size
                done += 1
                job = .sending(done: done, total: total)
            } catch {
                job = .failed(connected == nil ? "The connection to the Mac dropped." : error.localizedDescription)
                return false
            }
        }
        progress = 1
        job = .sent(total)
        if let id = targetId { Identity.lastMac = id }
        return true
    }

    func clearJob() { if !isSending { job = .idle; progress = 0 } }

    /// A 120 px square JPEG of a thumbnail, base64 — a few KB.
    private static func card(_ image: UIImage?) -> String {
        guard let image, image.size.width > 0, image.size.height > 0 else { return "" }
        let side: CGFloat = 120
        let scale = side / min(image.size.width, image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        return small.jpegData(compressionQuality: 0.6)?.base64EncodedString() ?? ""
    }

    private func sendFile(_ url: URL, name: String, to peer: MCPeerID, update: @escaping (Double) -> Void) async throws {
        var finished = false
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = session.sendResource(at: url, withName: name, toPeer: peer) { error in
                Task { @MainActor in
                    guard !finished else { return }
                    finished = true
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
            progressWatch = p?.observe(\.fractionCompleted) { prog, _ in
                let f = prog.fractionCompleted
                Task { @MainActor in update(f) }
            }
            if p == nil {
                finished = true
                cont.resume(throwing: NSError(domain: Brand.name, code: 1,
                                              userInfo: [NSLocalizedDescriptionKey: "Couldn’t start sending \(name)."]))
            }
        }
        progressWatch = nil
    }

    // MARK: Connection

    private func send(_ w: Wire, to peer: MCPeerID) {
        try? session.send(w.data, toPeers: [peer], with: .reliable)
    }

    private func pickTarget() {
        if let t = targetId, macs.contains(where: { $0.id == t }) { return }
        let pick = macs.first { $0.id == Identity.lastMac && $0.paired }
            ?? macs.first(where: \.paired)
            ?? (macs.count == 1 ? macs.first : nil)
        targetId = pick?.id
    }

    private func connectSoon(_ delay: Double) {
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.connectIfNeeded() }
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func connectIfNeeded() {
        guard browser != nil, connected == nil, let t = target else { return }
        guard link == .searching || link == .connecting || link == .off else { return }
        link = .connecting
        browser?.invitePeer(t.peer, to: session, withContext: nil, timeout: 15)
        // If the invite goes nowhere, try again.
        connectSoon(17)
    }

    private func handle(_ w: Wire, from peer: MCPeerID) {
        guard peer == connected else { return }
        switch w.t {
        case "hello":
            guard let macId = w.id, let nonce = w.nonce else { return }
            if let i = macs.firstIndex(where: { $0.id == macId }), let n = w.name { macs[i].name = n }
            if let secret = Identity.secret(for: macId) {
                send(Wire(t: "auth", id: Identity.deviceId, name: Identity.name,
                          proof: Proof.make(secret: secret, device: Identity.deviceId, nonce: nonce)), to: peer)
            } else {
                link = .needsPair
            }
        case "ok":
            link = .ready
        case "paired":
            guard let macId = w.id ?? targetId, let s = w.secret, let secret = Data(base64Encoded: s) else { return }
            Identity.setSecret(secret, for: macId)
            Identity.lastMac = macId
            if let i = macs.firstIndex(where: { $0.id == macId }) { macs[i].paired = true }
            link = .ready
        case "denied":
            if let t = targetId, Identity.secret(for: t) != nil {
                Identity.setSecret(nil, for: t)
                if let i = macs.firstIndex(where: { $0.id == t }) { macs[i].paired = false }
                notice = "The Mac doesn’t know this iPhone any more. Pair again."
                link = .needsPair
            } else {
                link = .denied("Not allowed on the Mac.")
            }
        default:
            break
        }
    }
}

// MARK: - MultipeerConnectivity

extension Sender: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let id = info?["id"] else { return }
        Task { @MainActor in
            let mac = Mac(id: id, name: peerID.displayName, peer: peerID, paired: Identity.secret(for: id) != nil)
            if let i = macs.firstIndex(where: { $0.id == id }) { macs[i] = mac } else { macs.append(mac) }
            pickTarget()
            if id == targetId, connected == nil { link = .searching; connectSoon(0.2) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard peerID != connected else { return }
            macs.removeAll { $0.peer == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            notice = "Can’t look for Macs: \(error.localizedDescription). Allow Local Network for Pampu in Settings."
        }
    }
}

extension Sender: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                connected = peerID
                retry?.cancel()
            case .notConnected:
                if connected == nil || connected == peerID {
                    connected = nil
                    if browser != nil {
                        if case .denied = link {} else { link = .searching }
                        connectSoon(1.5)
                    }
                }
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let w = Wire.decode(data) else { return }
        Task { @MainActor in handle(w, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    nonisolated func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}
