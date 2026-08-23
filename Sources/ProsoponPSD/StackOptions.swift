import Foundation

public struct StackOptions: Sendable {
    public var format: DocumentFormat
    public var depth: BitDepth
    public var compression: Compression
    public var dpi: Double

    public init(
        format: DocumentFormat = .psb,
        depth: BitDepth = .eight,
        compression: Compression = .rle,
        dpi: Double = 72
    ) {
        self.format = format
        self.depth = depth
        self.compression = compression
        self.dpi = dpi
    }

    public static let `default` = StackOptions()
}

public struct StackLayer: Sendable {
    public var name: String
    public var url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }

    public init(url: URL) {
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
    }
}

public struct StackSummary: Sendable {
    public let url: URL
    public let layerCount: Int
    public let width: Int
    public let height: Int
    public let byteCount: UInt64
}
