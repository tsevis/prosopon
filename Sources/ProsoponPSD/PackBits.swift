import Foundation

/// PackBits run-length coding, the scheme Photoshop labels compression mode 1.
///
/// Each scanline is coded independently: a control byte in 0...127 introduces that many
/// plus one literal bytes, and a control byte in -1...-127 introduces a run of one byte
/// repeated `1 - control` times. -128 is skipped, as every decoder is expected to ignore it.
enum PackBits {

    static func encode(_ input: UnsafeBufferPointer<UInt8>) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(input.count + input.count / 128 + 2)
        encode(input, into: &output)
        return output
    }

    /// Appends the coded form of `input` to `output`.
    ///
    /// The in-place form lets an entire channel be coded into one buffer, rather than
    /// returning a fresh array for each of a tile's two thousand scanlines.
    static func encode(_ input: UnsafeBufferPointer<UInt8>, into output: inout [UInt8]) {
        // Runs shorter than three are left inside literals on purpose. A two-byte run
        // costs two bytes either way, but breaking a literal to emit one adds a control
        // byte for the remainder -- so on noisy data, where adjacent pairs occur by
        // chance roughly every 256 bytes, splitting on pairs inflates the output well
        // past the one-byte-per-128 worst case PackBits is supposed to guarantee.
        var index = 0
        while index < input.count {
            var run = 1
            while index + run < input.count, run < 128, input[index + run] == input[index] {
                run += 1
            }

            if run >= 3 {
                output.append(UInt8(bitPattern: Int8(-(run - 1))))
                output.append(input[index])
                index += run
                continue
            }

            var literal = 0
            while index + literal < input.count, literal < 128 {
                if index + literal + 2 < input.count,
                   input[index + literal] == input[index + literal + 1],
                   input[index + literal] == input[index + literal + 2] {
                    break
                }
                literal += 1
            }
            literal = max(literal, 1)
            output.append(UInt8(literal - 1))
            output.append(contentsOf: input[index..<(index + literal)])
            index += literal
        }
    }

    static func encode(_ input: ArraySlice<UInt8>) -> [UInt8] {
        Array(input).withUnsafeBufferPointer { encode($0) }
    }

    /// Present so tests can prove the encoder round-trips; nothing in the writer decodes.
    static func decode(_ input: [UInt8], expecting count: Int) -> [UInt8]? {
        var output: [UInt8] = []
        output.reserveCapacity(count)
        var index = 0
        while index < input.count, output.count < count {
            let control = Int8(bitPattern: input[index])
            index += 1
            if control >= 0 {
                let length = Int(control) + 1
                guard index + length <= input.count else { return nil }
                output.append(contentsOf: input[index..<(index + length)])
                index += length
            } else if control != -128 {
                let length = 1 - Int(control)
                guard index < input.count else { return nil }
                output.append(contentsOf: [UInt8](repeating: input[index], count: length))
                index += 1
            }
        }
        return output.count == count ? output : nil
    }
}
