import Foundation

/// Which of the two Photoshop container formats to emit.
///
/// They are the same format with wider length fields. The distinction matters here
/// because a stack of aligned portraits overruns `.psd` quickly: a 2048 x 2048 RGBA
/// layer is about 16 MB at 8-bit, and photographic data barely compresses, so a few
/// hundred layers pass the 2 GB ceiling that `.psd` cannot express.
public enum DocumentFormat: String, Sendable, CaseIterable {
    case psd
    case psb

    var version: UInt16 { self == .psd ? 1 : 2 }

    /// Width of the length prefix on the layer-and-mask section, the layer-info
    /// section, and the `Lr16` tagged block.
    var sectionLengthBytes: Int { self == .psd ? 4 : 8 }

    /// Width of each channel's declared data length inside a layer record.
    var channelLengthBytes: Int { self == .psd ? 4 : 8 }

    /// Width of each per-scanline byte count in RLE-compressed channel data.
    var rleCountBytes: Int { self == .psd ? 2 : 4 }

    var maxDimension: Int { self == .psd ? 30_000 : 300_000 }

    /// `.psd` stores its section lengths in 32 bits, so 2 GB is a hard ceiling.
    var maxFileSize: UInt64? { self == .psd ? 2 << 30 : nil }
}

public enum BitDepth: Int, Sendable, CaseIterable {
    case eight = 8
    case sixteen = 16

    var bytesPerSample: Int { self == .eight ? 1 : 2 }
}

public enum Compression: String, Sendable, CaseIterable {
    /// Uncompressed. Larger, but the fastest to write and to open.
    case raw
    /// PackBits, which is what Photoshop itself writes.
    case rle

    var marker: UInt16 { self == .raw ? 0 : 1 }
}
