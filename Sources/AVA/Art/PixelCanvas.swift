import CoreGraphics
import Foundation

/// 8-bit RGBA color. Pixel art is opaque-or-clear, so premultiplication is trivial.
struct RGBA: Equatable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32, alpha: UInt8 = 255) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF), alpha)
    }

    static let clear = RGBA(0, 0, 0, 0)

    func mix(_ other: RGBA, _ t: Double) -> RGBA {
        let k = max(0, min(1, t))
        func f(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(Double(x) + (Double(y) - Double(x)) * k) }
        return RGBA(f(r, other.r), f(g, other.g), f(b, other.b), f(a, other.a))
    }

    func shade(_ amount: Double) -> RGBA {
        amount < 0 ? mix(RGBA(0, 0, 0), -amount) : mix(RGBA(255, 255, 255), amount)
    }
}

/// A raw RGBA8 pixel buffer. Every draw call writes bytes directly — no CoreGraphics
/// rasterization, so nothing is ever antialiased and the art stays true pixel art.
struct PixelCanvas {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    @inline(__always)
    mutating func set(_ x: Int, _ y: Int, _ c: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height, c.a != 0 else { return }
        let i = (y * width + x) * 4
        if c.a == 255 {
            bytes[i] = c.r; bytes[i + 1] = c.g; bytes[i + 2] = c.b; bytes[i + 3] = 255
            return
        }
        // Source-over with straight-alpha source onto premultiplied destination.
        let sa = Double(c.a) / 255.0
        let ia = 1.0 - sa
        bytes[i] = UInt8(Double(c.r) * sa + Double(bytes[i]) * ia)
        bytes[i + 1] = UInt8(Double(c.g) * sa + Double(bytes[i + 1]) * ia)
        bytes[i + 2] = UInt8(Double(c.b) * sa + Double(bytes[i + 2]) * ia)
        bytes[i + 3] = UInt8(min(255.0, Double(c.a) + Double(bytes[i + 3]) * ia))
    }

    @inline(__always)
    func get(_ x: Int, _ y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        let i = (y * width + x) * 4
        return RGBA(bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    mutating func clear() {
        for i in bytes.indices { bytes[i] = 0 }
    }

    mutating func fillRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGBA) {
        guard w > 0, h > 0 else { return }
        for yy in y..<(y + h) { for xx in x..<(x + w) { set(xx, yy, c) } }
    }

    mutating func fillCircle(_ cx: Double, _ cy: Double, _ r: Double, _ c: RGBA) {
        let x0 = Int(floor(cx - r)) - 1, x1 = Int(ceil(cx + r)) + 1
        let y0 = Int(floor(cy - r)) - 1, y1 = Int(ceil(cy + r)) + 1
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                if dx * dx + dy * dy <= r * r { set(x, y, c) }
            }
        }
    }

    mutating func fillEllipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: RGBA) {
        let x0 = Int(floor(cx - rx)) - 1, x1 = Int(ceil(cx + rx)) + 1
        let y0 = Int(floor(cy - ry)) - 1, y1 = Int(ceil(cy + ry)) + 1
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1 { set(x, y, c) }
            }
        }
    }

    /// Rounded rect with pixel-art corners (corner pixels simply omitted).
    mutating func roundRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ radius: Int, _ c: RGBA) {
        for yy in 0..<h {
            for xx in 0..<w {
                let dx = min(xx, w - 1 - xx), dy = min(yy, h - 1 - yy)
                if dx + dy < radius { continue }
                set(x + xx, y + yy, c)
            }
        }
    }

    /// Fill every pixel whose center satisfies `inside`, within an optional bounding box.
    mutating func fill(box: (Int, Int, Int, Int)? = nil, _ c: RGBA, _ inside: (Double, Double) -> Bool) {
        let (x0, y0, x1, y1) = box ?? (0, 0, width - 1, height - 1)
        for y in max(0, y0)...min(height - 1, y1) {
            for x in max(0, x0)...min(width - 1, x1) {
                if inside(Double(x) + 0.5, Double(y) + 0.5) { set(x, y, c) }
            }
        }
    }

    /// Composite another canvas on top at an offset.
    mutating func blit(_ src: PixelCanvas, _ ox: Int, _ oy: Int) {
        for y in 0..<src.height {
            for x in 0..<src.width {
                let c = src.get(x, y)
                if c.a != 0 { set(x + ox, y + oy, c) }
            }
        }
    }

    func cgImage() -> CGImage? {
        var data = bytes
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return data.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress,
                                      width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: cs, bitmapInfo: info.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }
}

// MARK: - Signed distance helpers (used to build the silhouette)

enum SDF {
    @inline(__always)
    static func circle(_ px: Double, _ py: Double, _ cx: Double, _ cy: Double, _ r: Double) -> Double {
        let dx = px - cx, dy = py - cy
        return (dx * dx + dy * dy).squareRoot() - r
    }

    @inline(__always)
    static func ellipse(_ px: Double, _ py: Double, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Double {
        let dx = (px - cx) / rx, dy = (py - cy) / ry
        let d = (dx * dx + dy * dy).squareRoot()
        return (d - 1.0) * min(rx, ry)
    }

    /// Smooth union — melts the neck circle into the body circle the way a real avocado bulges.
    @inline(__always)
    static func smoothUnion(_ a: Double, _ b: Double, _ k: Double) -> Double {
        let h = max(0, min(1, 0.5 + 0.5 * (b - a) / k))
        return b + (a - b) * h - k * h * (1 - h)
    }

    /// Vertical capsule (stadium shape) — a line segment thickened by `r`. Used for the
    /// hourglass neck: a straight column joining the two bulbs.
    @inline(__always)
    static func capsuleV(_ px: Double, _ py: Double, _ cx: Double, _ y0: Double, _ y1: Double, _ r: Double) -> Double {
        let cy = max(y0, min(y1, py))
        return circle(px, py, cx, cy, r)
    }
}
