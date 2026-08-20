import CoreGraphics
import Foundation

enum CaretTarget { case none, big }

/// All the dynamic state a frame needs. Note what's absent: no font metrics, no
/// glyph layout — AvocadoView draws `big`/`status` itself with Core Text, straight
/// onto the view, so text is a true vector font and never touches this raster
/// pipeline. Just two lines now: the clock, and one action word (START/PAUSE/
/// RESUME/DONE) — no FOCUS label, no task field.
struct SpriteFrame: Equatable {
    var mood: Mood = .idle
    var big: String = "25:00"
    var status: String = "\u{21B5} START"
    var caret: CaretTarget = .none
    var caretOn: Bool = true
    var progress: Double = 0
    var accent: RGBA = Palette.accentFocus
    var accentLit: RGBA = Palette.accentFocusLit
    var showMotion: Bool = false
    var motionPhase: Double = 0
}

/// Composes the body raster: cached mood body (bands, speckle, face, sprout, plaque
/// frame) + per-frame progress ring/glint.
enum SpriteRenderer {

    static func render(_ f: SpriteFrame) -> PixelCanvas {
        var c = AvocadoArt.shared.body(mood: f.mood)
        drawRing(&c, f)
        return c
    }

    static func image(_ f: SpriteFrame) -> CGImage? { render(f).cgImage() }

    private static func drawRing(_ c: inout PixelCanvas, _ f: SpriteFrame) {
        guard f.progress > 0 || f.mood == .happy else { return }
        let p = f.mood == .happy ? 1.0 : f.progress
        let steps = 720
        let end = Int(Double(steps) * min(1, p))
        guard end > 0 else { return }
        let cx = Double(Art.plaqueC.x) + 0.5, cy = Double(Art.plaqueC.y) + 0.5
        let r0 = Double(Art.plaqueR) + 3.5, r1 = Double(Art.plaqueR) + 5.0
        for i in 0..<end {
            let a = -Double.pi / 2 + (Double(i) / Double(steps)) * 2 * .pi
            let ca = cos(a), sa = sin(a)
            c.set(Int(cx + ca * r0), Int(cy + sa * r0), f.accent)
            c.set(Int(cx + ca * r1), Int(cy + sa * r1), f.accent)
        }
        guard f.showMotion else { return }
        let a = -Double.pi / 2 + f.motionPhase * 2 * .pi
        let gx = Int(cx + cos(a) * (r0 + 0.5)), gy = Int(cy + sin(a) * (r0 + 0.5))
        c.fillRect(gx - 1, gy - 1, 3, 3, f.accentLit)
    }

    // MARK: - Menu bar glyph

    static func menuBarIcon(running: Bool) -> PixelCanvas {
        let src = AvocadoArt.shared.body(mood: .idle)
        var c = PixelCanvas(width: 16, height: 16)
        let scale = 16.0 / Double(Art.H)
        let scaledW = Double(Art.W) * scale
        let offsetX = (16.0 - scaledW) / 2.0
        for y in 0..<16 {
            for x in 0..<16 {
                let srcX = (Double(x) - offsetX) / scale
                let srcY = Double(y) / scale
                guard srcX >= 0, srcY >= 0, srcX < Double(Art.W), srcY < Double(Art.H) else { continue }
                let col = src.get(Int(srcX), Int(srcY))
                if col.a != 0 { c.set(x, y, col) }
            }
        }
        if running {
            c.fillRect(12, 1, 3, 3, Palette.accentFocus)
        }
        return c
    }
}
