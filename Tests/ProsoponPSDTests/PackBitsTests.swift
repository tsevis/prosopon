import Foundation
import Testing
@testable import ProsoponPSD

@Suite("PackBits")
struct PackBitsTests {

    private func roundTrip(_ bytes: [UInt8], _ comment: Comment) {
        let encoded = bytes.withUnsafeBufferPointer { PackBits.encode($0) }
        let decoded = PackBits.decode(encoded, expecting: bytes.count)
        #expect(decoded == bytes, comment)
    }

    @Test("empty input")
    func empty() {
        #expect([UInt8]().withUnsafeBufferPointer { PackBits.encode($0) }.isEmpty)
    }

    @Test("a single byte")
    func singleByte() { roundTrip([42], "one literal") }

    @Test("a long run collapses and round-trips")
    func longRun() {
        let bytes = [UInt8](repeating: 7, count: 1000)
        let encoded = bytes.withUnsafeBufferPointer { PackBits.encode($0) }
        #expect(encoded.count < 32, "1000 identical bytes should cost about 8 runs, got \(encoded.count)")
        roundTrip(bytes, "long run")
    }

    @Test("short repeats stay inside literals rather than splitting them")
    func shortRepeatsDoNotSplitLiterals() {
        // Pairs every third byte: splitting on each would cost a control byte apiece.
        let bytes: [UInt8] = (0..<900).map { UInt8(($0 / 2) % 251) }
        let encoded = bytes.withUnsafeBufferPointer { PackBits.encode($0) }
        #expect(encoded.count <= bytes.count + (bytes.count + 127) / 128)
        roundTrip(bytes, "repeated pairs")
    }

    @Test("a run of exactly 128 stays within the control-byte range")
    func maximalRun() {
        roundTrip([UInt8](repeating: 3, count: 128), "128-byte run")
        roundTrip([UInt8](repeating: 3, count: 129), "129-byte run spills into a second control byte")
    }

    @Test("incompressible data round-trips and never expands much")
    func incompressible() {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<5000).map { _ in UInt8.random(in: 0...255, using: &generator) }
        let encoded = bytes.withUnsafeBufferPointer { PackBits.encode($0) }
        // PackBits guarantees at most one control byte per 128 literal bytes.
        #expect(encoded.count <= bytes.count + (bytes.count + 127) / 128,
                "\(encoded.count) bytes out for \(bytes.count) in")
        roundTrip(bytes, "random data")
    }

    @Test("runs and literals interleaved")
    func mixed() {
        var bytes: [UInt8] = []
        for block in 0..<40 {
            bytes.append(contentsOf: [UInt8](repeating: UInt8(block % 251), count: block % 7 + 1))
            bytes.append(contentsOf: (0..<(block % 5 + 1)).map { UInt8(($0 &* 37 &+ block) % 251) })
        }
        roundTrip(bytes, "alternating runs and literals")
    }

    @Test("a randomised sweep over run-heavy data")
    func randomisedSweep() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            var bytes: [UInt8] = []
            while bytes.count < Int.random(in: 1...600, using: &generator) {
                let value = UInt8.random(in: 0...4, using: &generator)
                bytes.append(contentsOf: [UInt8](repeating: value, count: Int.random(in: 1...200, using: &generator)))
            }
            roundTrip(bytes, "random run-heavy data")
        }
    }
}
