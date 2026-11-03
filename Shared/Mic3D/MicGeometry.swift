import AppKit
import SceneKit

/// Procedural shapes and textures for the 3D mic.
enum MicGeometry {
    /// A rounded slab whose front (+z) half bulges forward by `crown` in the middle, falling off towards the sides.
    /// Texture coordinates are planar along the dominant normal, in units of `tile` (cm), so a repeating
    /// texture keeps the same physical size on every face.
    static func crownedSlab(width w: Double, height h: Double, depth d: Double, chamfer r: Double, crown: Double,
                            tile: CGSize) -> SCNGeometry {
        let half = SIMD3(w, h, d) / 2, inner = half - r
        // Grid lines per axis: dense across the rounded edges, sparser on the flat parts.
        func steps(_ a: Double) -> [Double] {
            let edge = (0...8).map { -a - r + r * Double($0) / 8 }
            let flat = (1..<12).map { -a + 2 * a * Double($0) / 12 }
            return edge + flat + edge.reversed().map { -$0 }
        }
        let axes = [steps(inner.x), steps(inner.y), steps(inner.z)]
        var positions: [SIMD3<Double>] = [], normals: [SIMD3<Double>] = [], uvs: [CGPoint] = [], indices: [Int32] = []
        // Each cube face is a grid over two axes; points are pushed onto the rounded surface.
        for (fixed, a, b) in [(2, 0, 1), (0, 2, 1), (1, 0, 2)] {
            for sign in [-1.0, 1.0] {
                let start = Int32(positions.count), (us, vs) = (axes[a], axes[b])
                for v in vs {
                    for u in us {
                        var p = SIMD3<Double>()
                        (p[fixed], p[a], p[b]) = (sign * half[fixed], u, v)
                        let core = simd_clamp(p, -inner, inner), n = simd_normalize(p - core)
                        positions.append(core + n * r)
                        normals.append(n)
                    }
                }
                // Keep triangles counter-clockwise seen from outside: the a × b order faces out where `flip`.
                let flip = (sign > 0) == (fixed == 2) // a × b points along +fixed only for the z faces
                let cols = Int32(us.count)
                for j in 0..<Int32(vs.count - 1) {
                    for i in 0..<(cols - 1) {
                        let q = start + j * cols + i
                        indices += flip ? [q, q + 1, q + cols + 1, q, q + cols + 1, q + cols]
                                        : [q, q + cols + 1, q + 1, q, q + cols, q + cols + 1]
                    }
                }
            }
        }
        let (hw, hd) = (half.x, half.z)
        for i in positions.indices {
            let (p, n) = (positions[i], normals[i])
            let front = max(0, p.z / hd), across = 1 - (p.x / hw) * (p.x / hw)
            // Displace z, then fix normals with the inverse transpose of the displacement's Jacobian.
            let a = crown * (-2 * p.x / (hw * hw)) * front, b = 1 + (p.z > 0 ? crown * across / hd : 0)
            positions[i].z += crown * across * front
            normals[i] = simd_normalize(SIMD3(n.x - a * n.z / b, n.y, n.z / b))
            let q = positions[i], m = abs(normals[i])
            let (u, v) = m.x >= max(m.y, m.z) ? (q.z, q.y) : m.y >= m.z ? (q.x, q.z) : (q.x, q.y)
            uvs.append(CGPoint(x: u / tile.width, y: v / tile.height))
        }
        let sources = [SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) }),
                       SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) }),
                       SCNGeometrySource(textureCoordinates: uvs)]
        return SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    // MARK: Textures (drawn once, sRGB)

    static func image(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return ctx.makeImage()!
    }

    /// One staggered cell of the grille mesh: opaque metal, clear holes (tile is 1 : 2; power of two so it repeats).
    static let meshHoles = image(64, 128) { ctx in
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 128))
        ctx.setBlendMode(.clear)
        for (x, y) in [(0, 0), (64, 0), (0, 128), (64, 128), (32, 64)] {
            ctx.fillEllipse(in: CGRect(x: x - 21, y: y - 21, width: 42, height: 42))
        }
    }

    /// One cell of the rear grid: a single round hole.
    static let rearHole = image(64, 64) { ctx in
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        ctx.setBlendMode(.clear)
        ctx.fillEllipse(in: CGRect(x: 10, y: 10, width: 44, height: 44))
    }

    /// Dark hole with a lighter lip, for the side perforations (fakes depth on a flat disc).
    static let sideHole = image(64, 64) { ctx in
        let colors = [CGColor(gray: 0.0, alpha: 1), CGColor(gray: 0.02, alpha: 1), CGColor(gray: 0.25, alpha: 1)] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.75, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 34, y: 30), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }

    /// Normal map of fine vertical ribs, for the knurled knob and roller rims.
    static let knurl = image(256, 8) { ctx in
        for x in 0..<256 {
            let nx = sin(Double(x) / 256 * 2 * .pi * 32) * 0.6
            ctx.setFillColor(CGColor(srgbRed: (nx + 1) / 2, green: 0.5, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: 8))
        }
    }

    /// Premultiplied white-to-clear falloff, tinted per LED.
    static let glow = image(64, 64) { ctx in
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.3), CGColor(gray: 1, alpha: 0)] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.25, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }

    /// Equirectangular studio: dark floor, bright ceiling, two big softboxes and a strip light for the metal to reflect.
    static let studio = image(1024, 512) { ctx in
        let colors = [CGColor(gray: 0.06, alpha: 1), CGColor(gray: 0.3, alpha: 1), CGColor(gray: 0.85, alpha: 1)] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.48, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 120, y: 280, width: 200, height: 140))
        ctx.fill(CGRect(x: 640, y: 300, width: 140, height: 160))
        ctx.fill(CGRect(x: 0, y: 470, width: 1024, height: 20))
    }
}
