import XCTest
@testable import EasyShoot

final class ImageStitcherTests: XCTestCase {
    private let width = 120

    /// Rows of pseudo-random pixels so every row is distinguishable.
    private func makeContent(rows: Int, seed: UInt64) -> [UInt8] {
        var state = seed
        var out = [UInt8](repeating: 255, count: rows * width * 4)
        for i in stride(from: 0, to: out.count, by: 4) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            out[i] = UInt8(truncatingIfNeeded: state >> 33)
            out[i + 1] = UInt8(truncatingIfNeeded: state >> 41)
            out[i + 2] = UInt8(truncatingIfNeeded: state >> 49)
            out[i + 3] = 255
        }
        return out
    }

    private func rows(_ pixels: [UInt8], _ range: Range<Int>) -> [UInt8] {
        Array(pixels[(range.lowerBound * width * 4)..<(range.upperBound * width * 4)])
    }

    func testStitchesScrolledFrames() {
        let content = makeContent(rows: 1200, seed: 42)
        let frameHeight = 300
        let offsets = [0, 70, 150, 260, 400, 520, 700]
        let stitcher = ImageStitcher()
        for (i, offset) in offsets.enumerated() {
            let result = stitcher.add(pixels: rows(content, offset..<(offset + frameHeight)), width: width, height: frameHeight)
            if i == 0 {
                XCTAssertEqual(result, .first)
            } else {
                XCTAssertEqual(result, .appended(offset - offsets[i - 1]))
            }
        }
        XCTAssertEqual(stitcher.height, offsets.last! + frameHeight)
        let image = stitcher.makeImage()
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.height, offsets.last! + frameHeight)
    }

    func testIgnoresIdenticalFrames() {
        let content = makeContent(rows: 400, seed: 7)
        let stitcher = ImageStitcher()
        let frame = rows(content, 0..<200)
        XCTAssertEqual(stitcher.add(pixels: frame, width: width, height: 200), .first)
        XCTAssertEqual(stitcher.add(pixels: frame, width: width, height: 200), .unchanged)
        XCTAssertEqual(stitcher.height, 200)
    }

    func testStickyHeaderAndFooterAppearOnce() {
        let content = makeContent(rows: 1000, seed: 99)
        let header = makeContent(rows: 24, seed: 1)
        let footer = makeContent(rows: 30, seed: 2)
        let body = 250
        let offsets = [0, 90, 200, 330]
        let stitcher = ImageStitcher()
        for offset in offsets {
            let frame = header + rows(content, offset..<(offset + body)) + footer
            _ = stitcher.add(pixels: frame, width: width, height: header.count / (width * 4) + body + footer.count / (width * 4))
        }
        XCTAssertEqual(stitcher.height, 24 + offsets.last! + body + 30)

        let expected = header + rows(content, 0..<(offsets.last! + body)) + footer
        let image = stitcher.makeImage()!
        let pixels = ImageStitcher.rgba(image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        XCTAssertEqual(pixels, expected)
    }

    func testRejectsFramesWithoutOverlap() {
        let content = makeContent(rows: 1000, seed: 5)
        let stitcher = ImageStitcher()
        _ = stitcher.add(pixels: rows(content, 0..<200), width: width, height: 200)
        XCTAssertEqual(stitcher.add(pixels: rows(content, 600..<800), width: width, height: 200), .noOverlap)
    }
}
