// Effects — the show the stack puts on when it's thrown. The iPhone plays the "send" half (the stack
// leaving the screen), the Mac the matching "arrive" half (the cards landing in the panel). Each one is
// drawn from the time since it started, with seeded random numbers, so both sides need nothing but
// the effect's name and a start time — and any single frame can be rendered for a screenshot.
//
// Compiled into the Mac app and both iPhone targets: SwiftUI only, nothing UIKit or AppKit.
import SwiftUI

enum DropEffect: String, CaseIterable, Identifiable, Codable {
    case classic, rocket, paperPlane, blackHole, confetti, fireworks, hyperspace, comet,
         bubbles, magic, lightning, portal, shatter, hearts, tornado

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .rocket: return "Rocket"
        case .paperPlane: return "Paper Plane"
        case .blackHole: return "Black Hole"
        case .confetti: return "Confetti"
        case .fireworks: return "Fireworks"
        case .hyperspace: return "Hyperspace"
        case .comet: return "Comet"
        case .bubbles: return "Bubbles"
        case .magic: return "Magic Dust"
        case .lightning: return "Lightning"
        case .portal: return "Portal"
        case .shatter: return "Shatter"
        case .hearts: return "Hearts"
        case .tornado: return "Tornado"
        }
    }

    var emoji: String {
        switch self {
        case .classic: return "✨"
        case .rocket: return "🚀"
        case .paperPlane: return "✈️"
        case .blackHole: return "🕳️"
        case .confetti: return "🎉"
        case .fireworks: return "🎆"
        case .hyperspace: return "🌌"
        case .comet: return "☄️"
        case .bubbles: return "🫧"
        case .magic: return "🪄"
        case .lightning: return "⚡️"
        case .portal: return "🌀"
        case .shatter: return "💥"
        case .hearts: return "💖"
        case .tornado: return "🌪️"
        }
    }

    /// One line for the picker.
    var blurb: String {
        switch self {
        case .classic: return "A clean flick off the top, like NameDrop"
        case .rocket: return "Rumbles, then blasts off on a plume of fire"
        case .paperPlane: return "Folds up and loops away on the breeze"
        case .blackHole: return "Spirals into a swirling void"
        case .confetti: return "Pops in a burst of party confetti"
        case .fireworks: return "Shoots up and bursts into the sky"
        case .hyperspace: return "Stars stretch and it jumps to light speed"
        case .comet: return "Streaks away with a blazing tail"
        case .bubbles: return "Floats off inside a wobbly bubble"
        case .magic: return "Dissolves into twinkling fairy dust"
        case .lightning: return "Struck by a bolt and zapped across"
        case .portal: return "Dives through a spinning portal"
        case .shatter: return "Smashes into glittering shards"
        case .hearts: return "Beats twice and floats off on hearts"
        case .tornado: return "Whirls up inside a twister"
        }
    }

    /// Seconds the iPhone's half lasts.
    var sendDuration: Double {
        switch self {
        case .classic: return 0.7
        case .lightning: return 1.1
        case .confetti, .shatter, .hyperspace: return 1.3
        case .rocket, .comet: return 1.5
        case .paperPlane, .magic, .portal, .hearts, .tornado: return 1.6
        case .blackHole, .fireworks: return 1.8
        case .bubbles: return 1.9
        }
    }

    /// Seconds the Mac's half lasts.
    var arriveDuration: Double { self == .classic ? 1.1 : 1.7 }

    /// The setting is "random" or one effect's name; this picks the one to play now.
    static func resolve(_ choice: String, after last: DropEffect? = nil) -> DropEffect {
        if let e = DropEffect(rawValue: choice) { return e }
        let pool = allCases.filter { $0 != last }
        return pool.randomElement() ?? .classic
    }
    static let randomChoice = "random"

    // MARK: Moving the stack (iPhone) and the cards (Mac)

    /// Where the stack is `t` (0…1) of the way through being thrown, relative to where it started.
    func send(_ t: Double) -> EffectMotion {
        let t = clamp(t)
        var m = EffectMotion()
        switch self {
        case .classic:
            let u = ease(clamp(t / 0.55), .in)
            m.y = -1100 * u
            m.scale = 1 - 0.55 * u
        case .rocket:
            if t < 0.3 {
                let k = t / 0.3
                m.x = sin(t * 140) * 5 * k
                m.y = 6 * k
                m.scale = 1 - 0.05 * k
            } else {
                let u = (t - 0.3) / 0.7
                m.y = 6 - 1400 * pow(u, 2.4)
                m.scale = 0.95 - 0.35 * u
                m.stretch = 1 + 0.35 * min(1, u * 3)
            }
        case .paperPlane:
            if t < 0.25 {
                let k = ease(t / 0.25, .inOut)
                m.scale = 1 - 0.62 * k
                m.angle = -35 * k
                m.flip = 60 * k
            } else {
                let p = paperPath((t - 0.25) / 0.75)
                m.x = p.x; m.y = p.y; m.angle = p.angle
                m.scale = 0.38
                m.flip = 60
                m.opacity = 0   // it's the paper plane now (drawn by EffectCanvas)
            }
        case .blackHole:
            let u = ease(clamp((t - 0.12) / 0.7), .in)
            let rad = 240 * pow(1 - u, 1.3)
            let a = u * .pi * 3.2
            m.x = CGFloat(sin(a) * rad * 0.6)
            m.y = CGFloat(-240 + cos(a) * rad)
            m.scale = CGFloat(max(0, 1 - u))
            m.angle = u * 900
            m.opacity = u > 0.97 ? 0 : 1
        case .confetti:
            if t < 0.16 {
                m.scale = 1 + 0.3 * sin(t / 0.16 * .pi / 2)
            } else {
                let u = (t - 0.16) / 0.84
                m.scale = 1.3 - 0.8 * u
                m.y = -1200 * pow(u, 1.8)
                m.angle = 25 * u
            }
        case .fireworks:
            let u = ease(clamp(t / 0.36), .out)
            m.y = -320 * u
            m.x = 6 * sin(u * 9)
            m.scale = 1 - 0.85 * u
            m.opacity = t < 0.36 ? 1 : 0
        case .hyperspace:
            if t < 0.45 {
                let k = t / 0.45
                m.x = sin(t * 160) * 2.5 * k
                m.scale = 1 - 0.1 * k
            } else {
                let u = clamp((t - 0.45) / 0.2)
                m.y = -1100 * ease(u, .in)
                m.stretch = 1 + 3 * u
                m.scale = 0.9 - 0.55 * u
                m.opacity = u >= 1 ? 0 : 1
            }
        case .comet:
            if t < 0.25 {
                m.scale = 1 - 0.7 * ease(t / 0.25, .inOut)
                m.angle = 90 * t / 0.25
            } else {
                let p = cometPath((t - 0.25) / 0.75)
                m.x = p.x; m.y = p.y
                m.scale = 0.3
                m.angle = 90 + 360 * (t - 0.25)
            }
        case .bubbles:
            let wob = sin(t * 26) * (1 - t) * 0.06
            if t < 0.2 {
                m.scale = 1 - 0.25 * ease(t / 0.2, .out) + wob
            } else {
                let u = (t - 0.2) / 0.8
                m.y = -1100 * pow(u, 1.7)
                m.x = 34 * sin(u * 7)
                m.scale = 0.75 + wob
                m.angle = 12 * sin(u * 6)
            }
        case .magic:
            let u = clamp((t - 0.08) / 0.55)
            m.opacity = 1 - u
            m.blur = 12 * u
            m.scale = 1 + 0.12 * u
            m.y = -70 * u
        case .lightning:
            let u = clamp((t - 0.1) / 0.14)
            m.scale = u < 0.4 ? 1 + 0.15 * u / 0.4 : max(0, 1.15 * (1 - (u - 0.4) / 0.6))
            m.x = t < 0.1 ? sin(t * 400) * 5 : 0
            m.opacity = u >= 1 ? 0 : 1
            m.brightness = 0.8 * clamp(t / 0.1) * (1 - u)
        case .portal:
            let u = ease(clamp((t - 0.2) / 0.55), .inOut)
            m.y = -250 * u
            m.scale = 1 - 0.85 * u
            m.angle = 200 * u
            m.opacity = u > 0.95 ? 0 : 1
        case .shatter:
            m.x = t < 0.14 ? sin(t * 300) * 6 * t / 0.14 : 0
            m.scale = t < 0.14 ? 1 + 0.08 * t / 0.14 : 1.08
            m.opacity = t < 0.15 ? 1 : 0
        case .hearts:
            if t < 0.36 {
                let k = t / 0.36
                m.scale = 1 + 0.16 * max(0, sin(k * .pi * 2)) * (k < 0.5 ? 1 : 1.3)
            } else {
                let u = (t - 0.36) / 0.64
                m.y = -1000 * pow(u, 1.7)
                m.x = 20 * sin(u * 8)
                m.scale = 1 - 0.5 * u
                m.opacity = 1 - u * 0.4
            }
        case .tornado:
            let u = ease(clamp(t / 0.92), .in)
            let rad = 70 * sin(u * .pi) + 10
            m.x = CGFloat(sin(u * .pi * 7) * rad)
            m.y = -1100 * pow(u, 1.5)
            m.angle = 1080 * u
            m.scale = 1 - 0.6 * u
        }
        return m
    }

    /// Where card `i` of the cards landing on the Mac is, `t` (0…1) of the way through.
    func arrive(_ t: Double, index i: Int, of n: Int) -> EffectMotion {
        let d = Double(i) * 0.08
        let t = clamp((t - d) / (1 - Double(max(n - 1, 0)) * 0.08))
        var m = EffectMotion()
        let side = CGFloat(Double(i) - Double(n - 1) / 2)    // −1, 0, 1 for three cards
        switch self {
        case .classic:
            let s = spring(clamp(t / 0.6))
            m.y = -90 * (1 - s)
            m.angle = Double(side) * 14 * (1 - s)
            m.opacity = clamp(t / 0.2)
        case .rocket:
            let u = ease(clamp(t / 0.7), .out)
            m.y = -150 * (1 - u)
            m.x = sin(t * 90) * 1.5 * (1 - u)
            m.opacity = clamp(t / 0.15)
        case .paperPlane:
            let u = clamp((t - 0.3) / 0.45)
            m.flip = 90 * (1 - ease(u, .out))
            m.scale = 0.4 + 0.6 * spring(u)
            m.opacity = u > 0 ? 1 : 0
        case .blackHole:
            let u = ease(clamp(t / 0.75), .out)
            let a = (1 - u) * .pi * 2.2
            let rad = Double(76 * side) * u
            m.x = CGFloat(cos(a) * rad - Double(76 * side))
            m.y = CGFloat(sin(a) * rad * 0.4)
            m.scale = u
            m.angle = -540 * (1 - u)
            m.opacity = clamp(t / 0.1)
        case .confetti:
            let u = clamp((t - 0.12) / 0.5)
            m.scale = spring(u) * (1 + 0.15 * sin(u * .pi))
            m.opacity = u > 0 ? 1 : 0
        case .fireworks:
            let u = clamp((t - 0.25 - Double(i) * 0.08) / 0.4)
            m.scale = 0.3 + 0.7 * spring(u)
            m.opacity = u
            m.brightness = 0.5 * (1 - u)
        case .hyperspace:
            let u = ease(clamp(t / 0.45), .out)
            m.scale = 0.05 + 0.95 * u
            m.stretch = 1 + 2.5 * (1 - u)
            m.y = -30 * (1 - u)
            m.opacity = clamp(t / 0.1)
        case .comet:
            let u = clamp((t - 0.35 - Double(i) * 0.1) / 0.35)
            m.scale = spring(u)
            m.opacity = u > 0 ? 1 : 0
            m.brightness = 0.6 * (1 - u)
        case .bubbles:
            let u = ease(clamp(t / 0.75), .out)
            m.y = 90 * (1 - u)
            m.x = 8 * sin(t * 18) * (1 - u)
            m.scale = 0.85 + 0.15 * u + 0.05 * sin(t * 30) * (1 - u)
            m.opacity = clamp(t / 0.15)
        case .magic:
            let u = clamp((t - 0.25) / 0.5)
            m.opacity = u
            m.blur = 10 * (1 - u)
            m.scale = 0.9 + 0.1 * u
            m.brightness = 0.4 * (1 - u)
        case .lightning:
            let hit = 0.12 + Double(i) * 0.12
            let u = clamp((t - hit) / 0.25)
            m.opacity = t >= hit ? 1 : 0
            m.x = sin(t * 300) * 4 * (1 - u) * (t >= hit ? 1 : 0)
            m.brightness = 0.9 * (1 - u)
            m.scale = 1 + 0.12 * (1 - u)
        case .portal:
            let u = clamp((t - 0.2) / 0.5)
            m.scale = spring(u)
            m.angle = -180 * (1 - ease(u, .out))
            m.opacity = u > 0 ? 1 : 0
        case .shatter:
            let u = clamp((t - 0.42) / 0.3)
            m.opacity = u > 0 ? 1 : 0
            m.scale = 0.9 + 0.1 * spring(u)
            m.brightness = 0.5 * (1 - u)
        case .hearts:
            let u = clamp((t - 0.1) / 0.4)
            let beat = t > 0.5 ? 0.12 * max(0, sin((t - 0.5) / 0.4 * .pi * 2)) : 0
            m.scale = spring(u) + beat
            m.opacity = u > 0 ? 1 : 0
        case .tornado:
            let u = ease(clamp(t / 0.75), .out)
            m.angle = -720 * (1 - u)
            m.scale = u
            m.x = CGFloat(sin((1 - u) * 8) * 40 * (1 - u))
            m.y = -60 * (1 - u)
            m.opacity = clamp(t / 0.1)
        }
        return m
    }

    // Paths shared by the stack and its trail, relative to where the stack started.
    fileprivate func paperPath(_ u: Double) -> (x: CGFloat, y: CGFloat, angle: Double) {
        let u = clamp(u)
        let loop = clamp(u / 0.6)
        let a = loop * .pi * 2
        let x = 100 * sin(a) + 220 * pow(clamp((u - 0.55) / 0.45), 1.5)
        let y = -110 * (1 - cos(a)) * 0.9 - 80 * u - 900 * pow(clamp((u - 0.55) / 0.45), 1.6)
        let dx = 100 * cos(a) * 2 * .pi / 0.6 + (u > 0.55 ? 300 : 0)
        let dy = -110 * sin(a) * 0.9 * 2 * .pi / 0.6 - 80 - (u > 0.55 ? 1400 * (u - 0.55) : 0)
        return (CGFloat(x), CGFloat(y), atan2(dy, dx) * 180 / .pi + 45)
    }

    fileprivate func cometPath(_ u: Double) -> (x: CGFloat, y: CGFloat) {
        let u = ease(clamp(u), .in)
        // A quadratic curve: start → control (out to the left) → off the top right.
        let p0 = CGPoint(x: 0, y: 0), c = CGPoint(x: -240, y: -320), p1 = CGPoint(x: 300, y: -1000)
        let x = (1 - u) * (1 - u) * p0.x + 2 * (1 - u) * u * c.x + u * u * p1.x
        let y = (1 - u) * (1 - u) * p0.y + 2 * (1 - u) * u * c.y + u * u * p1.y
        return (x, y)
    }
}

/// A transform for the stack or a card.
struct EffectMotion {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var scale: CGFloat = 1
    var angle: Double = 0
    var opacity: Double = 1
    var blur: CGFloat = 0
    /// Extra vertical stretch (speed lines).
    var stretch: CGFloat = 1
    /// Degrees of turn about the vertical axis.
    var flip: Double = 0
    /// Added whiteness, 0…1.
    var brightness: Double = 0
}

extension View {
    func effectMotion(_ m: EffectMotion) -> some View {
        self
            .brightness(m.brightness)
            .blur(radius: m.blur)
            // A flat squash rather than rotation3DEffect: it renders the same everywhere, snapshots included.
            .scaleEffect(x: m.scale * max(0.04, cos(m.flip * .pi / 180)), y: m.scale * m.stretch)
            .rotationEffect(.degrees(m.angle))
            .offset(x: m.x, y: m.y)
            .opacity(m.opacity)
    }
}

// MARK: - Drawing

/// The particles, glows and bolts for one run of an effect, on top of everything else.
///  - `.send`: the stack leaves from `origin` (the iPhone screen).
///  - `.arrive`: cards land at `slots` (centres, in this view's space) inside the Mac's panel.
struct EffectCanvas: View {
    enum Side { case send, arrive }
    var effect: DropEffect
    var side: Side
    var start: Date
    var origin: CGPoint = .zero
    var slots: [CGPoint] = []
    /// Draw one fixed moment (seconds in) instead of playing — for screenshots.
    var frozen: Double? = nil

    var body: some View {
        let duration = side == .send ? effect.sendDuration : effect.arriveDuration
        TimelineView(.animation(minimumInterval: nil, paused: frozen != nil)) { tl in
            let elapsed = frozen ?? tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let t = elapsed / duration
                guard t >= 0, t <= 1.25 else { return }
                var g = ctx
                if side == .send {
                    EffectArt.send(effect, &g, size: size, at: origin, t: t)
                } else {
                    EffectArt.arrive(effect, &g, size: size, slots: slots, t: t)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum EffectArt {
    static let blue = Color(red: 0.16, green: 0.56, blue: 1.0)
    static let violet = Color(red: 0.5, green: 0.34, blue: 0.96)
    static let party: [Color] = [.init(red: 1, green: 0.27, blue: 0.4), .init(red: 1, green: 0.76, blue: 0.1),
                                 .init(red: 0.2, green: 0.85, blue: 0.5), .init(red: 0.2, green: 0.6, blue: 1),
                                 .init(red: 0.7, green: 0.4, blue: 1), .init(red: 1, green: 0.5, blue: 0.15)]
    static let fire: [Color] = [.white, .init(red: 1, green: 0.9, blue: 0.4), .init(red: 1, green: 0.55, blue: 0.1),
                                .init(red: 0.95, green: 0.25, blue: 0.1)]
    static let gold: [Color] = [.white, .init(red: 1, green: 0.85, blue: 0.4), .init(red: 1, green: 0.6, blue: 0.85),
                                .init(red: 0.7, green: 0.8, blue: 1)]

    // MARK: iPhone: the stack leaving

    static func send(_ e: DropEffect, _ g: inout GraphicsContext, size: CGSize, at o: CGPoint, t: Double) {
        let m = e.send(min(t, 1))
        let p = CGPoint(x: o.x + m.x, y: o.y + m.y)   // where the stack is now
        switch e {
        case .classic:
            streaks(&g, from: p, count: 10, length: 160 * fade(t, 0, 0.5), spread: 60, color: blue, alpha: 0.5 * (1 - t))
        case .rocket:
            // Rumble: smoke puffs; lift-off: a flame plume under the stack and smoke left behind.
            let thrust = t < 0.3 ? 0.4 * t / 0.3 : 1 - clamp((t - 0.9) / 0.3)
            let nozzle = CGPoint(x: p.x, y: p.y + 70 * m.scale * m.stretch)
            for i in 0..<70 {
                let age = (t / 0.3 + r(i, 1)).truncatingRemainder(dividingBy: 1)
                let spread = (r(i, 2) - 0.5) * 70 * age
                let q = CGPoint(x: nozzle.x + spread, y: nozzle.y + 220 * age * (0.6 + r(i, 3)))
                let c = fire[min(fire.count - 1, Int(age * Double(fire.count)))]
                dot(&g, q, radius: (6 + 16 * age) * (0.6 + r(i, 4)), color: c, alpha: thrust * (1 - age))
            }
            for i in 0..<26 {   // smoke that stays where the rocket left from
                let born = r(i, 5) * 0.5 + 0.2
                let age = (t - born) / 0.9
                guard age > 0, age < 1 else { continue }
                let q = CGPoint(x: o.x + (r(i, 6) - 0.5) * 220 * age, y: o.y + 90 + (r(i, 7) - 0.5) * 40 - 30 * age)
                dot(&g, q, radius: 18 + 40 * age, color: Color(white: 0.75), alpha: 0.35 * (1 - age), blur: 6)
            }
            glow(&g, nozzle, radius: 70, color: .orange, alpha: 0.6 * thrust)
        case .paperPlane:
            if t > 0.25 {
                // A dashed contrail along the loop.
                var path = Path()
                let u = (t - 0.25) / 0.75
                for k in 0...60 {
                    let s = u * Double(k) / 60
                    let q = e.paperPath(s)
                    let pt = CGPoint(x: o.x + q.x, y: o.y + q.y)
                    k == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                g.stroke(path, with: .color(.white.opacity(0.85 * (1 - clamp((t - 0.9) / 0.3)))),
                         style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 10]))
                g.stroke(path, with: .color(blue.opacity(0.25)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                // The plane itself.
                let q = e.paperPath(u)
                var c = g
                c.translateBy(x: o.x + q.x, y: o.y + q.y)
                c.rotate(by: .degrees(q.angle))
                c.draw(c.resolve(Text(Image(systemName: "paperplane.fill")).font(.system(size: 54)).foregroundColor(.white)), at: .zero)
            }
        case .blackHole:
            let hole = CGPoint(x: o.x, y: o.y - 240)
            let open = ease(clamp(t / 0.2), .out) * (1 - ease(clamp((t - 0.9) / 0.25), .in))
            glow(&g, hole, radius: 190 * open, color: violet, alpha: 0.7)
            for i in 0..<140 {   // the accretion disk, spiralling in
                let phase = r(i, 1)
                let s = (phase + t * 1.6).truncatingRemainder(dividingBy: 1)
                let rad = (1 - s) * 170 * open + 12
                let a = r(i, 2) * .pi * 2 + t * 9 + s * 5
                let q = CGPoint(x: hole.x + cos(a) * rad, y: hole.y + sin(a) * rad * 0.42)
                let c = i % 3 == 0 ? Color.white : (i % 3 == 1 ? violet : Color(red: 1, green: 0.55, blue: 0.3))
                dot(&g, q, radius: 1.5 + 2.5 * s, color: c, alpha: open * (0.3 + 0.7 * s))
            }
            dot(&g, hole, radius: 46 * open, color: .black, alpha: 0.95)
            ring(&g, hole, radius: 50 * open, width: 3, color: .white, alpha: 0.7 * open)
            if t > 0.84 { glow(&g, hole, radius: 260 * fade(t, 0.84, 1), color: .white, alpha: 0.9 * (1 - fade(t, 0.84, 1.1))) }
        case .confetti:
            confettiBurst(&g, from: o, t: clamp((t - 0.1) / 0.9), count: 150, up: true)
        case .fireworks:
            let top = CGPoint(x: o.x, y: o.y - 320)
            if t < 0.38 {   // the rising spark
                for k in 0..<14 {
                    let s = max(0, t - Double(k) * 0.012)
                    let q = e.send(s)
                    dot(&g, CGPoint(x: o.x + q.x, y: o.y + q.y), radius: 4 - Double(k) * 0.25,
                        color: fire[k % fire.count], alpha: 1 - Double(k) / 14)
                }
            }
            let shells: [(at: CGPoint, when: Double, size: Double, colors: [Color])] = [
                (top, 0.36, 190, [party[4], party[1], .white]),
                (CGPoint(x: o.x - 100, y: o.y - 230), 0.5, 130, [party[0], party[1], .white]),
                (CGPoint(x: o.x + 100, y: o.y - 250), 0.62, 130, [party[2], party[3], .white]),
            ]
            for (n, s) in shells.enumerated() {
                burst(&g, at: s.at, t: (t - s.when) / 0.75, seed: n, count: 54, radius: s.size, colors: s.colors)
            }
        case .hyperspace:
            let c = CGPoint(x: o.x, y: o.y - 120)
            let warp = ease(clamp((t - 0.2) / 0.5), .in)
            for i in 0..<110 {
                let a = r(i, 1) * .pi * 2
                let d0 = 30 + r(i, 2) * 260
                let len = 6 + warp * (180 + 260 * r(i, 3))
                let push = warp * 220 * r(i, 4)
                let a0 = CGPoint(x: c.x + cos(a) * (d0 + push), y: c.y + sin(a) * (d0 + push))
                let a1 = CGPoint(x: c.x + cos(a) * (d0 + push + len), y: c.y + sin(a) * (d0 + push + len))
                var path = Path(); path.move(to: a0); path.addLine(to: a1)
                g.stroke(path, with: .color((i % 4 == 0 ? blue : Color.white).opacity(0.85 * (1 - fade(t, 0.8, 1.2)))),
                         lineWidth: 1.2 + 1.6 * r(i, 5))
            }
            if t > 0.5 { glow(&g, c, radius: 420 * fade(t, 0.5, 0.75), color: .white, alpha: 0.85 * (1 - fade(t, 0.58, 1))) }
        case .comet:
            // A glowing head and a tail that is just where it has been.
            if t > 0.05 {
                for k in 0..<40 {
                    let s = max(0, t - Double(k) * 0.008)
                    let q = e.send(s)
                    let pt = CGPoint(x: o.x + q.x, y: o.y + q.y)
                    let a = (1 - Double(k) / 40) * (t < 0.25 ? t / 0.25 : 1)
                    dot(&g, pt, radius: 28 * (1 - Double(k) / 44), color: k < 6 ? .white : (k < 18 ? Color(red: 0.6, green: 0.9, blue: 1) : blue),
                        alpha: a * 0.8, blur: 4)
                }
                glow(&g, p, radius: 90, color: Color(red: 0.6, green: 0.9, blue: 1), alpha: 0.8)
                for i in 0..<40 {   // sparks shed along the way
                    let born = r(i, 1) * 0.9 + 0.2
                    let age = (t - born) / 0.4
                    guard age > 0, age < 1 else { continue }
                    let q = e.send(born)
                    let pt = CGPoint(x: o.x + q.x + (r(i, 2) - 0.5) * 60 * age, y: o.y + q.y + 50 * age)
                    star(&g, pt, radius: 5 * (1 - age), color: .white, alpha: 1 - age)
                }
            }
        case .bubbles:
            if t < 0.95 {   // the big bubble around the stack
                let rad = 88 * m.scale
                dot(&g, p, radius: rad, color: blue, alpha: 0.08)
                ring(&g, p, radius: rad, width: 2.5, color: .white, alpha: 0.75)
                var arc = Path()
                arc.addArc(center: p, radius: rad * 0.78, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
                g.stroke(arc, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            } else {
                burst(&g, at: p, t: (t - 0.95) / 0.3, seed: 9, count: 20, radius: 90, colors: [.white, blue])
            }
            for i in 0..<36 {
                let born = r(i, 1) * 0.6
                let age = (t - born) / 0.9
                guard age > 0, age < 1 else { continue }
                let q = CGPoint(x: o.x + (r(i, 2) - 0.5) * 300 + 16 * sin(age * 10 + Double(i)), y: o.y + 160 - 700 * age)
                let rad = 5 + 15 * r(i, 3)
                ring(&g, q, radius: rad, width: 1.5, color: .white, alpha: 0.8 * (1 - age))
                dot(&g, CGPoint(x: q.x - rad * 0.35, y: q.y - rad * 0.35), radius: rad * 0.2, color: .white, alpha: 0.9 * (1 - age))
            }
        case .magic:
            for i in 0..<180 {
                let born = 0.05 + r(i, 1) * 0.5
                let age = (t - born) / 0.7
                guard age > 0, age < 1 else { continue }
                let sx = o.x + (r(i, 2) - 0.5) * 120, sy = o.y + (r(i, 3) - 0.5) * 120
                let drift = CGPoint(x: (r(i, 4) - 0.5) * 160 * age + 18 * sin(age * 8 + Double(i)), y: -320 * age * (0.5 + r(i, 5)))
                let twinkle = 0.55 + 0.45 * sin(t * 40 + Double(i))
                let c = gold[i % gold.count]
                if i % 7 == 0 { star(&g, CGPoint(x: sx + drift.x, y: sy + drift.y), radius: 7 * (1 - age * 0.5), color: c, alpha: twinkle * (1 - age)) }
                else { dot(&g, CGPoint(x: sx + drift.x, y: sy + drift.y), radius: 1.5 + 2 * r(i, 6), color: c, alpha: twinkle * (1 - age)) }
            }
            glow(&g, CGPoint(x: o.x, y: o.y - 40), radius: 160, color: Color(red: 1, green: 0.8, blue: 0.5), alpha: 0.45 * sin(clamp(t / 0.7) * .pi))
        case .lightning:
            if t < 0.32 {
                let flicker = (Int(t * 60) % 3 == 0) ? 0.4 : 1.0
                for b in 0..<3 {
                    let startX = o.x + (Double(b) - 1) * 70 + (r(b, 1) - 0.5) * 60
                    bolt(&g, from: CGPoint(x: startX, y: -20), to: o, seed: b + Int(t * 20) * 7,
                         alpha: flicker * (b == 0 ? 1 : 0.55) * (1 - t / 0.32))
                }
                glow(&g, o, radius: 150, color: Color(red: 0.75, green: 0.85, blue: 1), alpha: 0.9 * (1 - t / 0.32))
            }
            // The flash fills the screen for a blink.
            let flash = t < 0.06 ? t / 0.06 : max(0, 1 - (t - 0.06) / 0.18)
            g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.75 * flash)))
            for i in 0..<40 {   // embers falling where it was
                let age = (t - 0.2) / 0.8
                guard age > 0, age < 1 else { continue }
                let vx = (r(i, 2) - 0.5) * 260, vy = -r(i, 3) * 260
                let q = CGPoint(x: o.x + vx * age, y: o.y + vy * age + 380 * age * age)
                dot(&g, q, radius: 2.5, color: i % 2 == 0 ? .white : Color(red: 0.6, green: 0.8, blue: 1), alpha: 1 - age)
            }
        case .portal:
            let c = CGPoint(x: o.x, y: o.y - 250)
            let open = spring(clamp(t / 0.25)) * (1 - ease(clamp((t - 0.8) / 0.2), .in))
            glow(&g, c, radius: 150 * open, color: violet, alpha: 0.6)
            for k in 0..<5 {
                var ell = Path(ellipseIn: CGRect(x: -95, y: -36, width: 190, height: 72))
                ell = ell.applying(CGAffineTransform(scaleX: open * (1 - Double(k) * 0.13), y: open * (1 - Double(k) * 0.13)))
                var cc = g
                cc.translateBy(x: c.x, y: c.y)
                cc.rotate(by: .degrees(t * 300 * (k % 2 == 0 ? 1 : -1) * 0.15))
                cc.stroke(ell, with: .conicGradient(Gradient(colors: [blue, violet, .white, Color(red: 1, green: 0.4, blue: 0.8), blue]),
                                                    center: .zero, angle: .degrees(t * 720 + Double(k) * 40)),
                          lineWidth: 6 - Double(k))
            }
            dot(&g, c, radius: 30 * open, color: .black, alpha: 0.35)
            for i in 0..<60 {   // sparks being sucked in
                let s = (r(i, 1) + t * 2).truncatingRemainder(dividingBy: 1)
                let a = r(i, 2) * .pi * 2 + t * 6
                let rad = (1 - s) * 140 * open
                dot(&g, CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad * 0.38), radius: 2, color: .white, alpha: open * s)
            }
        case .shatter:
            shards(&g, center: o, t: (t - 0.14) / 0.86, count: 30, outward: true)
            if t > 0.12 { glow(&g, o, radius: 170 * fade(t, 0.12, 0.3), color: .white, alpha: 0.8 * (1 - fade(t, 0.15, 0.5))) }
        case .hearts:
            let heart = g.resolve(Text("💖").font(.system(size: 30)))
            let small = g.resolve(Text("💕").font(.system(size: 22)))
            for i in 0..<34 {
                let born = 0.25 + r(i, 1) * 0.6
                let age = (t - born) / 0.8
                guard age > 0, age < 1 else { continue }
                let q = CGPoint(x: o.x + (r(i, 2) - 0.5) * 260 + 22 * sin(age * 7 + Double(i)), y: o.y + 40 - 520 * age)
                var c = g
                c.opacity = 1 - age
                c.translateBy(x: q.x, y: q.y)
                c.scaleBy(x: 0.6 + 0.6 * r(i, 3), y: 0.6 + 0.6 * r(i, 3))
                c.draw(i % 3 == 0 ? small : heart, at: .zero)
            }
            if t < 0.38 { glow(&g, o, radius: 130, color: Color(red: 1, green: 0.4, blue: 0.6), alpha: 0.45 * max(0, sin(t / 0.36 * .pi * 2))) }
        case .tornado:
            let base = CGPoint(x: o.x, y: o.y + 40)
            let strength = ease(clamp(t / 0.2), .out) * (1 - fade(t, 0.85, 1.2))
            for i in 0..<160 {
                let h = r(i, 1)                        // 0 at the bottom of the funnel, 1 at the top
                let rad = 20 + 160 * pow(h, 1.4)
                let a = r(i, 2) * .pi * 2 + t * (14 - 6 * h)
                let q = CGPoint(x: base.x + cos(a) * rad + 30 * sin(h * 6 + t * 4), y: base.y - h * 620 + sin(a) * rad * 0.22)
                let back = sin(a) < 0
                dot(&g, q, radius: 2 + 2.5 * r(i, 3), color: i % 5 == 0 ? blue : Color(white: 0.85),
                    alpha: strength * (back ? 0.35 : 0.85))
            }
        }
    }

    // MARK: Mac: the cards landing

    static func arrive(_ e: DropEffect, _ g: inout GraphicsContext, size: CGSize, slots: [CGPoint], t: Double) {
        let row = slots.isEmpty ? CGPoint(x: size.width / 2, y: size.height * 0.55) : CGPoint(x: slots.map(\.x).reduce(0, +) / Double(slots.count), y: slots[0].y)
        let spots = slots.isEmpty ? [row] : slots
        switch e {
        case .classic:
            for (i, s) in spots.enumerated() {
                streaks(&g, from: CGPoint(x: s.x, y: s.y - 40), count: 5, length: 50 * (1 - fade(t, 0.1, 0.6)), spread: 26,
                        color: blue, alpha: 0.4 * (1 - t), seed: i, down: true)
            }
        case .rocket:
            for (i, s) in spots.enumerated() {
                let m = e.arrive(t, index: i, of: spots.count)
                let nozzle = CGPoint(x: s.x + m.x, y: s.y + m.y + 34)
                let thrust = 1 - fade(t, 0.45, 0.75)
                for k in 0..<22 {
                    let age = (t * 6 + r(k, i)).truncatingRemainder(dividingBy: 1)
                    let q = CGPoint(x: nozzle.x + (r(k, 2) - 0.5) * 20 * age, y: nozzle.y + 40 * age)
                    dot(&g, q, radius: 3 + 6 * age, color: fire[min(3, Int(age * 4))], alpha: thrust * (1 - age))
                }
                for k in 0..<12 {   // dust kicked up on touch-down
                    let age = (t - 0.55) / 0.5
                    guard age > 0, age < 1 else { continue }
                    let dir = r(k, i + 9) < 0.5 ? -1.0 : 1.0
                    let q = CGPoint(x: s.x + dir * (10 + 50 * age * r(k, 3)), y: s.y + 32 - 10 * age)
                    dot(&g, q, radius: 4 + 8 * age, color: Color(white: 0.7), alpha: 0.5 * (1 - age), blur: 3)
                }
            }
        case .paperPlane:
            let u = clamp(t / 0.55)
            var path = Path()
            let pts = (0...40).map { k -> CGPoint in
                let s = u * Double(k) / 40
                return CGPoint(x: -40 + (size.width + 80) * s, y: row.y - 10 - 60 * sin(s * .pi) + 25 * sin(s * .pi * 3))
            }
            path.addLines(pts)
            g.stroke(path, with: .color(.secondary.opacity(0.6 * (1 - fade(t, 0.6, 1)))), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
            if u < 1, let last = pts.last, pts.count > 1 {
                let prev = pts[pts.count - 2]
                var c = g
                c.translateBy(x: last.x, y: last.y)
                c.rotate(by: .radians(atan2(last.y - prev.y, last.x - prev.x) + .pi / 4))
                c.draw(c.resolve(Text(Image(systemName: "paperplane.fill")).font(.system(size: 26)).foregroundColor(blue)), at: .zero)
            }
        case .blackHole:
            let open = (1 - fade(t, 0.6, 1)) * ease(clamp(t / 0.15), .out)
            glow(&g, row, radius: 110 * open, color: violet, alpha: 0.6)
            for i in 0..<90 {
                let s = (r(i, 1) + t * 1.4).truncatingRemainder(dividingBy: 1)
                let rad = 8 + s * 150
                let a = r(i, 2) * .pi * 2 - t * 7 - s * 3
                dot(&g, CGPoint(x: row.x + cos(a) * rad, y: row.y + sin(a) * rad * 0.35), radius: 1.2 + 1.5 * (1 - s),
                    color: i % 2 == 0 ? .white : violet, alpha: open * (1 - s))
            }
            dot(&g, row, radius: 10 * open, color: .white, alpha: open)
        case .confetti:
            confettiRain(&g, size: size, t: t, count: 110)
        case .fireworks:
            for (i, s) in spots.enumerated() {
                burst(&g, at: CGPoint(x: s.x, y: s.y - 6), t: (t - 0.2 - Double(i) * 0.08) / 0.7, seed: i, count: 36, radius: 70,
                      colors: [party[i % party.count], party[(i + 2) % party.count], .white])
            }
        case .hyperspace:
            let slow = ease(clamp(t / 0.5), .out)
            for i in 0..<80 {
                let a = r(i, 1) * .pi * 2
                let d0 = 20 + r(i, 2) * 200
                let len = (1 - slow) * (60 + 140 * r(i, 3)) + 2
                let a0 = CGPoint(x: row.x + cos(a) * d0, y: row.y + sin(a) * d0 * 0.6)
                let a1 = CGPoint(x: row.x + cos(a) * (d0 + len), y: row.y + sin(a) * (d0 + len) * 0.6)
                var path = Path(); path.move(to: a0); path.addLine(to: a1)
                g.stroke(path, with: .color((i % 3 == 0 ? blue : Color.white).opacity(0.8 * (1 - fade(t, 0.5, 1)))), lineWidth: 1.2)
            }
            if t < 0.2 { glow(&g, row, radius: 160, color: .white, alpha: 0.7 * (1 - t / 0.2)) }
        case .comet:
            for (i, s) in spots.enumerated() {
                let u = clamp((t - Double(i) * 0.1) / 0.38)
                guard u > 0 else { continue }
                let from = CGPoint(x: s.x - 160, y: -30)
                for k in 0..<24 {
                    let uu = max(0, u - Double(k) * 0.02)
                    let q = CGPoint(x: from.x + (s.x - from.x) * uu, y: from.y + (s.y - from.y) * uu)
                    dot(&g, q, radius: 9 * (1 - Double(k) / 26), color: k < 4 ? .white : Color(red: 0.6, green: 0.9, blue: 1),
                        alpha: (1 - Double(k) / 24) * (1 - fade(u, 0.9, 1.3)), blur: 2)
                }
                if u >= 1 { burst(&g, at: s, t: (t - Double(i) * 0.1 - 0.38) / 0.5, seed: i + 20, count: 22, radius: 50, colors: [.white, Color(red: 0.6, green: 0.9, blue: 1)]) }
            }
        case .bubbles:
            for i in 0..<34 {
                let born = r(i, 1) * 0.5
                let age = (t - born) / 0.8
                guard age > 0, age < 1 else { continue }
                let q = CGPoint(x: r(i, 2) * size.width + 10 * sin(age * 9 + Double(i)), y: size.height + 10 - (size.height + 30) * age)
                let rad = 3 + 9 * r(i, 3)
                ring(&g, q, radius: rad, width: 1.2, color: blue, alpha: 0.7 * (1 - age))
                dot(&g, CGPoint(x: q.x - rad * 0.35, y: q.y - rad * 0.35), radius: rad * 0.22, color: .white, alpha: 1 - age)
            }
            for (i, s) in spots.enumerated() where t > 0.72 {   // each card's bubble pops
                ring(&g, s, radius: 40 + 30 * fade(t, 0.72, 1), width: 2, color: blue, alpha: 0.8 * (1 - fade(t, 0.72, 1)))
                burst(&g, at: s, t: (t - 0.72) / 0.4, seed: i + 30, count: 14, radius: 55, colors: [.white, blue])
            }
        case .magic:
            for (n, s) in spots.enumerated() {
                for i in 0..<50 {
                    let k = i + n * 50
                    let u = ease(clamp((t - r(k, 1) * 0.25) / 0.55), .inOut)
                    let a = r(k, 2) * .pi * 2
                    let d = 90 * (0.4 + r(k, 3))
                    let q = CGPoint(x: s.x + cos(a + u * 2) * d * (1 - u), y: s.y + sin(a + u * 2) * d * (1 - u))
                    let twinkle = 0.5 + 0.5 * sin(t * 40 + Double(k))
                    if k % 6 == 0 { star(&g, q, radius: 5, color: gold[k % gold.count], alpha: twinkle * (1 - fade(t, 0.7, 1))) }
                    else { dot(&g, q, radius: 1.6, color: gold[k % gold.count], alpha: twinkle * (1 - fade(t, 0.7, 1))) }
                }
            }
        case .lightning:
            for (i, s) in spots.enumerated() {
                let hit = 0.12 + Double(i) * 0.12
                guard t > hit - 0.05, t < hit + 0.18 else { continue }
                bolt(&g, from: CGPoint(x: s.x + (r(i, 1) - 0.5) * 60, y: -10), to: s, seed: i + Int(t * 30) * 5, alpha: 1 - clamp((t - hit) / 0.18), width: 2.5)
                glow(&g, s, radius: 70, color: Color(red: 0.75, green: 0.85, blue: 1), alpha: 0.8 * (1 - clamp((t - hit) / 0.2)))
            }
            let flash = t < 0.05 ? t / 0.05 : max(0, 1 - (t - 0.05) / 0.2)
            g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.55 * flash)))
        case .portal:
            for (i, s) in spots.enumerated() {
                let open = spring(clamp((t - Double(i) * 0.06) / 0.25)) * (1 - ease(clamp((t - 0.65) / 0.25), .in))
                var cc = g
                cc.translateBy(x: s.x, y: s.y)
                for k in 0..<3 {
                    let ell = Path(ellipseIn: CGRect(x: -44, y: -44, width: 88, height: 88))
                        .applying(CGAffineTransform(scaleX: open * (1 - Double(k) * 0.15), y: open * (1 - Double(k) * 0.15)))
                    cc.stroke(ell, with: .conicGradient(Gradient(colors: [blue, violet, .white, Color(red: 1, green: 0.4, blue: 0.8), blue]),
                                                        center: .zero, angle: .degrees(t * 900 + Double(k) * 60)), lineWidth: 3.5 - Double(k))
                }
            }
        case .shatter:
            for (i, s) in spots.enumerated() {
                shards(&g, center: s, t: 1 - clamp(t / 0.45), count: 12, outward: true, seed: i * 50, scale: 0.4)
                if t > 0.4 { glow(&g, s, radius: 60, color: .white, alpha: 0.7 * (1 - fade(t, 0.42, 0.75))) }
            }
        case .hearts:
            let heart = g.resolve(Text("💖").font(.system(size: 18)))
            for i in 0..<26 {
                let born = r(i, 1) * 0.5
                let age = (t - born) / 0.8
                guard age > 0, age < 1 else { continue }
                let q = CGPoint(x: r(i, 2) * size.width + 10 * sin(age * 6 + Double(i)), y: size.height - (size.height + 20) * age)
                var c = g
                c.opacity = 1 - age
                c.translateBy(x: q.x, y: q.y)
                c.scaleBy(x: 0.6 + 0.6 * r(i, 3), y: 0.6 + 0.6 * r(i, 3))
                c.draw(heart, at: .zero)
            }
        case .tornado:
            let strength = 1 - fade(t, 0.55, 0.9)
            for i in 0..<110 {
                let h = r(i, 1)
                let rad = 30 + 150 * h
                let a = r(i, 2) * .pi * 2 + t * 12
                dot(&g, CGPoint(x: row.x + cos(a) * rad, y: row.y + sin(a) * rad * 0.3 - (h - 0.5) * 30), radius: 1.5 + 1.5 * r(i, 3),
                    color: i % 4 == 0 ? blue : .secondary, alpha: strength * (sin(a) < 0 ? 0.35 : 0.8))
            }
        }
    }

    // MARK: Pieces

    static func dot(_ g: inout GraphicsContext, _ p: CGPoint, radius: Double, color: Color, alpha: Double, blur: Double = 0) {
        guard alpha > 0.01, radius > 0.1 else { return }
        var c = g
        if blur > 0 { c.addFilter(.blur(radius: blur)) }
        c.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
               with: .color(color.opacity(min(1, alpha))))
    }

    static func ring(_ g: inout GraphicsContext, _ p: CGPoint, radius: Double, width: Double, color: Color, alpha: Double) {
        guard alpha > 0.01, radius > 0.1 else { return }
        g.stroke(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                 with: .color(color.opacity(min(1, alpha))), lineWidth: width)
    }

    static func glow(_ g: inout GraphicsContext, _ p: CGPoint, radius: Double, color: Color, alpha: Double) {
        guard alpha > 0.01, radius > 1 else { return }
        g.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
               with: .radialGradient(Gradient(colors: [color.opacity(min(1, alpha)), color.opacity(min(1, alpha) * 0.35), .clear]),
                                     center: p, startRadius: 0, endRadius: radius))
    }

    /// A four-pointed twinkle.
    static func star(_ g: inout GraphicsContext, _ p: CGPoint, radius: Double, color: Color, alpha: Double) {
        guard alpha > 0.01, radius > 0.3 else { return }
        var s = Path()
        let w = radius * 0.28
        s.move(to: CGPoint(x: p.x, y: p.y - radius))
        s.addQuadCurve(to: CGPoint(x: p.x + radius, y: p.y), control: CGPoint(x: p.x + w, y: p.y - w))
        s.addQuadCurve(to: CGPoint(x: p.x, y: p.y + radius), control: CGPoint(x: p.x + w, y: p.y + w))
        s.addQuadCurve(to: CGPoint(x: p.x - radius, y: p.y), control: CGPoint(x: p.x - w, y: p.y + w))
        s.addQuadCurve(to: CGPoint(x: p.x, y: p.y - radius), control: CGPoint(x: p.x - w, y: p.y - w))
        g.fill(s, with: .color(color.opacity(min(1, alpha))))
    }

    static func streaks(_ g: inout GraphicsContext, from p: CGPoint, count: Int, length: Double, spread: Double,
                        color: Color, alpha: Double, seed: Int = 0, down: Bool = false) {
        guard alpha > 0.01, length > 1 else { return }
        for i in 0..<count {
            let x = p.x + (r(i, seed + 1) - 0.5) * spread * 2
            let y0 = p.y + (down ? -1 : 1) * (20 + r(i, seed + 2) * 40)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y0))
            path.addLine(to: CGPoint(x: x, y: y0 + (down ? -1 : 1) * length * (0.5 + r(i, seed + 3))))
            g.stroke(path, with: .color(color.opacity(alpha)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    /// Sparks flying out from a point and falling, with short trails.
    static func burst(_ g: inout GraphicsContext, at p: CGPoint, t: Double, seed: Int, count: Int, radius: Double, colors: [Color]) {
        guard t > 0, t < 1 else { return }
        let u = ease(t, .out)
        if t < 0.25 { glow(&g, p, radius: radius * 0.9, color: .white, alpha: 0.8 * (1 - t / 0.25)) }
        for i in 0..<count {
            let a = Double(i) / Double(count) * .pi * 2 + r(i, seed) * 0.2
            let d = radius * (0.65 + 0.35 * r(i, seed + 1))
            let fall = 60 * t * t
            let q = CGPoint(x: p.x + cos(a) * d * u, y: p.y + sin(a) * d * u + fall)
            let tail = CGPoint(x: p.x + cos(a) * d * u * 0.82, y: p.y + sin(a) * d * u * 0.82 + fall * 0.8)
            var path = Path(); path.move(to: tail); path.addLine(to: q)
            let c = colors[i % colors.count]
            let twinkle = t > 0.6 ? (0.5 + 0.5 * sin(t * 60 + Double(i))) : 1
            g.stroke(path, with: .color(c.opacity((1 - t) * twinkle)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            dot(&g, q, radius: 2.2, color: c, alpha: (1 - t) * twinkle)
        }
    }

    static func confettiBurst(_ g: inout GraphicsContext, from p: CGPoint, t: Double, count: Int, up: Bool) {
        guard t > 0, t < 1.2 else { return }
        for i in 0..<count {
            let a = -Double.pi / 2 + (r(i, 1) - 0.5) * 2.4
            let v = 600 + 700 * r(i, 2)
            let s = t * 1.2
            let q = CGPoint(x: p.x + cos(a) * v * s * 0.7, y: p.y + sin(a) * v * s + 900 * s * s)
            confettiPiece(&g, q, i: i, spin: s * 14, alpha: 1 - fade(t, 0.7, 1.15))
        }
    }

    static func confettiRain(_ g: inout GraphicsContext, size: CGSize, t: Double, count: Int) {
        for i in 0..<count {
            let born = r(i, 1) * 0.35
            let age = (t - born) / 0.9
            guard age > 0, age < 1 else { continue }
            let q = CGPoint(x: r(i, 2) * size.width + 20 * sin(age * 8 + Double(i)), y: -10 + (size.height + 30) * age * (0.7 + 0.3 * r(i, 3)))
            confettiPiece(&g, q, i: i, spin: age * 12, alpha: 1 - fade(age, 0.75, 1), scale: 0.7)
        }
    }

    static func confettiPiece(_ g: inout GraphicsContext, _ q: CGPoint, i: Int, spin: Double, alpha: Double, scale: Double = 1) {
        guard alpha > 0.01 else { return }
        var c = g
        c.translateBy(x: q.x, y: q.y)
        c.rotate(by: .radians(spin + r(i, 4) * 6))
        c.scaleBy(x: cos(spin * 1.3 + Double(i)) * scale, y: scale)   // flutter
        let shape: Path = i % 3 == 0 ? Path(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8))
                                     : Path(CGRect(x: -6, y: -3, width: 12, height: 6))
        c.fill(shape, with: .color(party[i % party.count].opacity(alpha)))
    }

    /// Glassy triangles: flying out from `center` as `t` goes 0→1 (run `t` backwards to assemble).
    static func shards(_ g: inout GraphicsContext, center p: CGPoint, t: Double, count: Int, outward: Bool, seed: Int = 0, scale: Double = 1) {
        guard t > 0, t < 1 else { return }
        for i in 0..<count {
            let k = i + seed
            let a = r(k, 1) * .pi * 2
            let speed = (250 + 450 * r(k, 2)) * scale
            let q = CGPoint(x: p.x + cos(a) * speed * t + (r(k, 6) - 0.5) * 100 * scale,
                            y: p.y + sin(a) * speed * t - 300 * t * scale + 500 * t * t * scale + (r(k, 7) - 0.5) * 100 * scale)
            var c = g
            c.translateBy(x: q.x, y: q.y)
            c.rotate(by: .radians(t * 10 * (r(k, 3) - 0.5) + r(k, 8) * 6))
            let s = (12 + 22 * r(k, 4)) * scale
            var tri = Path()
            tri.move(to: CGPoint(x: 0, y: -s))
            tri.addLine(to: CGPoint(x: s * (0.6 + 0.4 * r(k, 5)), y: s * 0.7))
            tri.addLine(to: CGPoint(x: -s * 0.8, y: s * 0.4))
            tri.closeSubpath()
            let fadeOut = 1 - fade(t, 0.6, 1)
            c.fill(tri, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.95 * fadeOut), blue.opacity(0.8 * fadeOut), violet.opacity(0.7 * fadeOut)]),
                                              startPoint: CGPoint(x: 0, y: -s), endPoint: CGPoint(x: 0, y: s)))
            c.stroke(tri, with: .color(.white.opacity(0.9 * fadeOut)), lineWidth: 1)
        }
    }

    /// A jagged bolt with a soft glow.
    static func bolt(_ g: inout GraphicsContext, from a: CGPoint, to b: CGPoint, seed: Int, alpha: Double, width: Double = 4) {
        guard alpha > 0.01 else { return }
        var path = Path()
        path.move(to: a)
        let steps = 12
        for k in 1...steps {
            let f = Double(k) / Double(steps)
            let jitter = k == steps ? 0 : (r(k, seed) - 0.5) * 70 * (1 - f * 0.5)
            path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * f + jitter, y: a.y + (b.y - a.y) * f))
        }
        var glowCtx = g
        glowCtx.addFilter(.blur(radius: 8))
        glowCtx.stroke(path, with: .color(Color(red: 0.6, green: 0.75, blue: 1).opacity(alpha)), lineWidth: width * 4)
        g.stroke(path, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Maths

/// A repeatable random number in 0..<1 for particle `i`, property `k`.
@inline(__always) fileprivate func r(_ i: Int, _ k: Int) -> Double {
    var x = UInt64(truncatingIfNeeded: (i &* 73_856_093) ^ (k &* 19_349_663)) &+ 0x9E37_79B9_7F4A_7C15
    x ^= x >> 33; x &*= 0xFF51_AFD7_ED55_8CCD
    x ^= x >> 33; x &*= 0xC4CE_B9FE_1A85_EC53
    x ^= x >> 33
    return Double(x % 1_000_000) / 1_000_000
}

@inline(__always) fileprivate func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

/// 0 before `a`, 1 after `b`, a straight ramp between.
@inline(__always) fileprivate func fade(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }

fileprivate enum Ease { case `in`, out, inOut }
fileprivate func ease(_ t: Double, _ e: Ease) -> Double {
    let t = clamp(t)
    switch e {
    case .in: return t * t * t
    case .out: return 1 - pow(1 - t, 3)
    case .inOut: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}

/// 0 → 1 with a little bounce past the end.
fileprivate func spring(_ t: Double) -> Double {
    let t = clamp(t)
    return 1 - exp(-6 * t) * cos(t * 10)
}
