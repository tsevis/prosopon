import Foundation

/// Photoshop documents are big-endian throughout.
extension Data {
    mutating func appendBE(_ value: UInt8) { append(value) }

    mutating func appendBE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func appendBE(_ value: Int16) { appendBE(UInt16(bitPattern: value)) }

    mutating func appendBE(_ value: UInt32) {
        appendBE(UInt16(truncatingIfNeeded: value >> 16))
        appendBE(UInt16(truncatingIfNeeded: value))
    }

    mutating func appendBE(_ value: Int32) { appendBE(UInt32(bitPattern: value)) }

    mutating func appendBE(_ value: UInt64) {
        appendBE(UInt32(truncatingIfNeeded: value >> 32))
        appendBE(UInt32(truncatingIfNeeded: value))
    }

    /// A fixed-length ASCII tag such as `8BPS` or `norm`.
    mutating func appendSignature(_ tag: String) {
        let bytes = Array(tag.utf8)
        precondition(bytes.count == 4, "signatures are four bytes: \(tag)")
        append(contentsOf: bytes)
    }

    /// A length-prefixed byte string, padded so the total occupies a multiple of `padding`.
    mutating func appendPascalString(_ string: String, paddedTo padding: Int) {
        // The legacy name field is a single-byte string; anything outside ASCII is
        // carried by the Unicode `luni` block instead, which is written alongside it.
        let bytes = Array(string.unicodeScalars.map { $0.isASCII ? UInt8($0.value) : 0x5F }.prefix(255))
        append(UInt8(bytes.count))
        append(contentsOf: bytes)
        let total = bytes.count + 1
        let remainder = total % padding
        if remainder != 0 {
            append(contentsOf: [UInt8](repeating: 0, count: padding - remainder))
        }
    }

    /// Photoshop's Unicode string: a UTF-16 code-unit count followed by big-endian UTF-16.
    mutating func appendUnicodeString(_ string: String) {
        let units = Array(string.utf16)
        appendBE(UInt32(units.count))
        for unit in units { appendBE(unit) }
    }
}
