import Foundation

/// Static geometry of the sprite, built as a real per-pixel SDF at full resolution
/// (smooth curves, not a coarse chunky grid). Text is NOT drawn into this raster —
/// AvocadoView draws it separately with Core Text, so digits/words are true vector
/// glyphs, never bitmap pixels.
enum Art {
    static let W = 150
    static let H = 200
    static let cx = 75.0

    static let neck = (x: cx, y: 64.0, r: 39.0)
    static let bulb = (x: cx, y: 124.0, r: 60.0)
    static let blend = 18.0

    // A modest, mostly-circular pit, centered where an avocado's actual seed sits —
    // near the middle of the bulb, not sunk down toward the bottom skin.
    static let plaqueC = (x: Int(cx), y: 126)
    static let plaqueR = 30

    static let outlineDepth: Double = 3
    static let rimDepth: Double = 9
    static let innerDepth: Double = 12

    static let eyeY = 78
    static let eyeLeftX = 48
    static let eyeRightX = 91
    static let eyeW = 11
    static let eyeH = 14

    static let mouthY = 91

    // Text layout, in FINAL coordinates — the Y values are line CENTERS, shared with
    // AvocadoView's Core Text draw. Gap is sized for rendered font height (which
    // scales with view zoom), not raw digit count.
    static let bigCenterY    = plaqueC.y - 13
    static let statusCenterY = plaqueC.y + 9
}

enum Mood {
    case idle, blink, focused, resting, happy, paused
}
extension Mood: Equatable {}

final class AvocadoArt {
    static let shared = AvocadoArt()

    private(set) var dist: [Float]
    private var bodyCache: [Mood: PixelCanvas] = [:]

    private init() {
        let w = Art.W, h = Art.H
        var mask = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let dNeck = SDF.circle(px, py, Art.neck.x, Art.neck.y, Art.neck.r)
                let dBulb = SDF.circle(px, py, Art.bulb.x, Art.bulb.y, Art.bulb.r)
                let d = SDF.smoothUnion(dNeck, dBulb, Art.blend)
                mask[y * w + x] = d < 0
            }
        }
        self.dist = AvocadoArt.distanceTransform(mask: mask, width: w, height: h)
    }

    private static func distanceTransform(mask: [Bool], width w: Int, height h: Int) -> [Float] {
        let big: Float = 1e9
        var d = [Float](repeating: big, count: w * h)
        for i in 0..<(w * h) where !mask[i] { d[i] = 0 }
        @inline(__always) func at(_ x: Int, _ y: Int) -> Float {
            (x < 0 || y < 0 || x >= w || y >= h) ? 0 : d[y * w + x]
        }
        let o: Float = 3, dg: Float = 4
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard d[i] != 0 else { continue }
                var v = d[i]
                v = min(v, at(x - 1, y) + o); v = min(v, at(x, y - 1) + o)
                v = min(v, at(x - 1, y - 1) + dg); v = min(v, at(x + 1, y - 1) + dg)
                d[i] = v
            }
        }
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                let i = y * w + x
                guard d[i] != 0 else { continue }
                var v = d[i]
                v = min(v, at(x + 1, y) + o); v = min(v, at(x, y + 1) + o)
                v = min(v, at(x + 1, y + 1) + dg); v = min(v, at(x - 1, y + 1) + dg)
                d[i] = v
            }
        }
        for i in 0..<(w * h) { d[i] /= 3.0 }
        return d
    }

    @inline(__always) func depth(_ x: Int, _ y: Int) -> Float {
        guard x >= 0, y >= 0, x < Art.W, y < Art.H else { return 0 }
        return dist[y * Art.W + x]
    }

    @inline(__always) func isFlesh(_ x: Int, _ y: Int) -> Bool {
        depth(x, y) >= Float(Art.innerDepth)
    }

    @inline(__always) func inPlaque(_ x: Int, _ y: Int, pad: Int = 0) -> Bool {
        let dx = x - Art.plaqueC.x, dy = y - Art.plaqueC.y
        let r = Art.plaqueR + pad
        return dx * dx + dy * dy <= r * r
    }

    // MARK: - Cached static body

    func body(mood: Mood) -> PixelCanvas {
        if let c = bodyCache[mood] { return c }
        var c = PixelCanvas(width: Art.W, height: Art.H)
        paintBands(&c)
        paintSpeckle(&c)
        paintFace(&c, mood: mood)
        paintSprout(&c)
        paintPlaqueFrame(&c)
        bodyCache[mood] = c
        return c
    }

    private func paintBands(_ c: inout PixelCanvas) {
        for y in 0..<Art.H {
            for x in 0..<Art.W {
                let d = Double(depth(x, y))
                guard d > 0 else { continue }
                let color: RGBA
                switch d {
                case ..<Art.outlineDepth: color = Palette.outline
                case ..<Art.rimDepth:
                    let lit = Double(x) * 0.6 + Double(y) * 0.4 < 100
                    color = lit ? Palette.rimGreenLit : Palette.rimGreen
                case ..<Art.innerDepth: color = Palette.rimGreenDark
                default: color = Palette.flesh
                }
                c.set(x, y, color)
            }
        }
    }

    private func paintSpeckle(_ c: inout PixelCanvas) {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        @inline(__always) func rnd() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 10000) / 10000.0
        }
        for _ in 0..<160 {
            let x = Int(rnd() * Double(Art.W))
            let y = Int(rnd() * Double(Art.H))
            guard isFlesh(x, y), !inPlaque(x, y, pad: 6) else { continue }
            c.set(x, y, Palette.fleshDot)
        }
    }

    private func paintFace(_ c: inout PixelCanvas, mood: Mood) {
        // Flat, matte eyes — no gloss/sparkle highlight — plus a bold brow sitting
        // close overhead. That combination is what reads neutral/masculine rather
        // than the softer glazed-eye-plus-blush look.
        func eye(_ x: Int) {
            switch mood {
            case .blink:
                c.fillRect(x, Art.eyeY + Art.eyeH / 2, Art.eyeW, 2, Palette.outline)
            case .resting:
                c.roundRect(x, Art.eyeY + 5, Art.eyeW, Art.eyeH - 6, 2, Palette.outline)
            case .happy:
                for i in 0..<Art.eyeW {
                    let k = abs(i - Art.eyeW / 2)
                    c.fillRect(x + i, Art.eyeY + 2 + k, 2, 2, Palette.outline)
                }
            case .focused:
                c.roundRect(x, Art.eyeY + 2, Art.eyeW, Art.eyeH - 4, 3, Palette.outline)
            case .paused, .idle:
                c.roundRect(x, Art.eyeY, Art.eyeW, Art.eyeH, 3, Palette.outline)
            }
        }
        eye(Art.eyeLeftX)
        eye(Art.eyeRightX)

        // Thick, low, level brows sitting close over the eyes — a much more
        // deliberate/serious cue than the earlier thin tilted line.
        func brow(_ x: Int) {
            c.fillRect(x - 1, Art.eyeY - 5, Art.eyeW + 2, 3, Palette.outline)
        }
        brow(Art.eyeLeftX)
        brow(Art.eyeRightX)

        let mx = Int(Art.cx) - 6, my = Art.mouthY
        switch mood {
        case .happy:
            for i in 0..<12 {
                let y = my + (i == 0 || i == 11 ? 0 : (i < 4 || i > 7 ? 1 : 3))
                c.fillRect(mx + i, y, 1, 2, Palette.outline)
            }
        case .resting:
            c.fillRect(mx + 3, my + 1, 6, 2, Palette.outline)
        default:
            c.fillRect(mx + 1, my, 3, 2, Palette.outline)
            c.fillRect(mx + 4, my + 2, 4, 2, Palette.outline)
            c.fillRect(mx + 8, my, 3, 2, Palette.outline)
        }
    }

    /// Two leaves only — no stem. They converge right at the crown of the head,
    /// overlapping slightly into the neck so there's no floating gap.
    private func paintSprout(_ c: inout PixelCanvas) {
        let neckTop = Art.neck.y - Art.neck.r
        let junctionY = neckTop + 5

        func leaf(cx: Double, cy: Double, rx: Double, ry: Double, deg: Double) {
            let a = deg * .pi / 180
            let ca = cos(a), sa = sin(a)
            let x0 = Int(cx - rx - 3), x1 = Int(cx + rx + 3)
            let y0 = Int(cy - ry - 10), y1 = Int(cy + ry + 10)
            for y in max(0, y0)...min(Art.H - 1, y1) {
                for x in max(0, x0)...min(Art.W - 1, x1) {
                    let px = Double(x) + 0.5 - cx, py = Double(y) + 0.5 - cy
                    let rxp = px * ca + py * sa
                    let ryp = -px * sa + py * ca
                    let outer = (rxp * rxp) / ((rx + 2) * (rx + 2)) + (ryp * ryp) / ((ry + 2) * (ry + 2))
                    let inner = (rxp * rxp) / (rx * rx) + (ryp * ryp) / (ry * ry)
                    if inner <= 1 {
                        if abs(ryp) < 0.9 { c.set(x, y, Palette.leafDark) }
                        else { c.set(x, y, ryp > 0 ? Palette.leafDark.mix(Palette.leaf, 0.55) : Palette.leaf) }
                    } else if outer <= 1 {
                        c.set(x, y, Palette.outline)
                    }
                }
            }
        }
        // Thinner and more upright than a soft rounded leaf — sharper, less
        // flower-petal-like.
        let cx = Art.cx
        leaf(cx: cx - 12, cy: junctionY + 2, rx: 17, ry: 5, deg: -22)
        leaf(cx: cx + 12, cy: junctionY + 1, rx: 17, ry: 5, deg: 22)

        c.fillCircle(cx, junctionY, 5, Palette.outline)
        c.fillCircle(cx, junctionY, 3.8, Palette.bud)
        c.fillCircle(cx + 1.3, junctionY + 1.3, 2, Palette.budShade)
    }

    private func paintPlaqueFrame(_ c: inout PixelCanvas) {
        let cx = Double(Art.plaqueC.x), cy = Double(Art.plaqueC.y), r = Double(Art.plaqueR)
        c.fillCircle(cx, cy, r + 3, Palette.rimGreenDark)
        c.fillCircle(cx, cy, r + 1.5, Palette.plaqueDark)
        c.fillCircle(cx, cy, r, Palette.plaque)
        for y in (Art.plaqueC.y - Art.plaqueR)...(Art.plaqueC.y + Art.plaqueR) {
            for x in (Art.plaqueC.x - Art.plaqueR)...(Art.plaqueC.x + Art.plaqueR) {
                guard inPlaque(x, y, pad: -3) else { continue }
                let dx = Double(x) - cx, dy = Double(y) - cy
                if dx + dy < -18 { c.set(x, y, Palette.plaqueLit) }
            }
        }
    }
}
