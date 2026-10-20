import CoreGraphics
import Foundation

/// Compact per-row fingerprints used to line up consecutive frames.
/// Each row is split into segments and the luminance of each segment is summed,
/// which tolerates small anti-aliasing differences between frames.
struct RowSignatures {
    static let segments = 16

    let height: Int
    private(set) var sums: [Int32]
    private(set) var uniform: [Bool]
    let tolerance: Int32

    init(pixels: [UInt8], width: Int, height: Int) {
        let segs = Self.segments
        let segWidth = max(1, (width + segs - 1) / segs)
        var sums = [Int32](repeating: 0, count: height * segs)
        var uniform = [Bool](repeating: true, count: height)
        pixels.withUnsafeBufferPointer { px in
            for y in 0..<height {
                let rowBase = y * width * 4
                var minL: Int32 = 255
                var maxL: Int32 = 0
                for x in 0..<width {
                    let o = rowBase + x * 4
                    let l = (Int32(px[o]) * 77 + Int32(px[o + 1]) * 150 + Int32(px[o + 2]) * 29) >> 8
                    sums[y * segs + min(x / segWidth, segs - 1)] += l
                    if l < minL { minL = l }
                    if l > maxL { maxL = l }
                }
                uniform[y] = maxL - minL <= 3
            }
        }
        self.height = height
        self.sums = sums
        self.uniform = uniform
        self.tolerance = Int32(segWidth * 2)
    }

    func rowEqual(_ a: Int, _ other: RowSignatures, _ b: Int) -> Bool {
        let segs = Self.segments
        let baseA = a * segs, baseB = b * segs
        for k in 0..<segs where abs(sums[baseA + k] - other.sums[baseB + k]) > tolerance {
            return false
        }
        return true
    }

    func allEqual(_ other: RowSignatures) -> Bool {
        guard height == other.height else { return false }
        for y in 0..<height where !rowEqual(y, other, y) { return false }
        return true
    }
}

/// Stitches frames of a scrolling region into one tall image.
/// Handles sticky headers/footers: rows that stay put between frames are kept once.
final class ImageStitcher: @unchecked Sendable {
    enum AddResult: Equatable {
        case first
        case appended(Int)
        case unchanged
        case noOverlap
        case limitReached
    }

    let maxHeight: Int
    private let lock = NSLock()
    private var canvas: [UInt8] = []
    private var width = 0
    private var storedHeight = 0
    private var previous: RowSignatures?
    private var colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init(maxHeight: Int = 60_000) {
        self.maxHeight = maxHeight
    }

    var height: Int {
        lock.lock(); defer { lock.unlock() }
        return storedHeight
    }

    func add(_ image: CGImage) -> AddResult {
        lock.lock()
        if previous == nil, let cs = image.colorSpace, cs.model == .rgb, cs.supportsOutput {
            colorSpace = cs
        }
        let space = colorSpace
        lock.unlock()
        guard let pixels = Self.rgba(image, colorSpace: space) else { return .noOverlap }
        return add(pixels: pixels, width: image.width, height: image.height)
    }

    func add(pixels: [UInt8], width w: Int, height h: Int) -> AddResult {
        lock.lock(); defer { lock.unlock() }
        let sigs = RowSignatures(pixels: pixels, width: w, height: h)
        guard let prev = previous else {
            canvas = pixels
            width = w
            storedHeight = h
            previous = sigs
            return .first
        }
        guard w == width, h == prev.height else { return .noOverlap }
        if sigs.allEqual(prev) { return .unchanged }

        // Rows that did not move are fixed headers / footers.
        var top = 0
        while top < h, sigs.rowEqual(top, prev, top) { top += 1 }
        var bottom = 0
        while bottom < h - top, sigs.rowEqual(h - 1 - bottom, prev, h - 1 - bottom) { bottom += 1 }
        let start = top, end = h - bottom
        guard end - start >= 16 else { return .unchanged }

        guard let shift = Self.findShift(prev: prev, next: sigs, start: start, end: end) else { return .noOverlap }
        guard storedHeight + shift <= maxHeight else { return .limitReached }

        // The canvas always ends with the previous frame's bottom. Drop its footer,
        // then append the newly revealed rows plus the (current) footer.
        let rowBytes = w * 4
        canvas.removeLast(bottom * rowBytes)
        canvas.append(contentsOf: pixels[((end - shift) * rowBytes)..<(h * rowBytes)])
        storedHeight += shift
        previous = sigs
        return .appended(shift)
    }

    /// Finds how many rows the content moved up between `prev` and `next`, using rows in [start, end).
    static func findShift(prev: RowSignatures, next: RowSignatures, start: Int, end: Int) -> Int? {
        let band = end - start
        let minOverlap = max(12, band / 8)
        guard band - minOverlap >= 1 else { return nil }
        var best: (shift: Int, matches: Int)?
        for s in 1...(band - minOverlap) {
            let n = band - s
            let maxMismatch = n / 20 + 1
            var matches = 0
            var mismatches = 0
            for i in 0..<n {
                let a = start + s + i, b = start + i
                if prev.rowEqual(a, next, b) {
                    if !(prev.uniform[a] && next.uniform[b]) { matches += 1 }
                } else {
                    mismatches += 1
                    if mismatches > maxMismatch { break }
                }
            }
            guard mismatches <= maxMismatch, matches >= 6 else { continue }
            if best == nil || matches > best!.matches {
                best = (s, matches)
            }
        }
        return best?.shift
    }

    func makeImage() -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard width > 0, storedHeight > 0,
              let provider = CGDataProvider(data: Data(canvas) as CFData) else { return nil }
        return CGImage(width: width, height: storedHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// RGBA8 pixels, top row first.
    static func rgba(_ image: CGImage, colorSpace: CGColorSpace) -> [UInt8]? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? data : nil
    }
}
