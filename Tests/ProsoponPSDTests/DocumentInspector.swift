import Foundation
@testable import ProsoponPSD

/// A minimal independent reader for the documents the writer produces.
///
/// Its job is not to decode pixels but to prove the *arithmetic*: every section in a
/// Photoshop file declares its own length, and a writer that streams content and patches
/// those lengths afterwards is exactly the kind of code where an offset drifts by two
/// bytes and nothing notices until Photoshop refuses to open the file. Walking the
/// declared lengths and checking they land where the content actually ends catches that.
struct DocumentInspector {

    struct Layer {
        var name: String
        var unicodeName: String?
        var rect: (top: Int, left: Int, bottom: Int, right: Int)
        var channelIDs: [Int]
        var channelLengths: [Int]
        var opacity: Int
        var blendMode: String
    }

    struct Report {
        var version: Int
        var channels: Int
        var width: Int
        var height: Int
        var depth: Int
        var colorMode: Int
        var resourceIDs: [Int]
        var layers: [Layer]
        var layerCountField: Int
        var taggedBlocks: [String]
        var taggedBlockLengths: [String: Int]
        var imageDataCompression: Int
        var bytesAfterImageData: Int
    }

    enum Failure: Error, CustomStringConvertible {
        case message(String)
        var description: String { if case .message(let text) = self { text } else { "" } }
    }

    private let data: Data
    private var cursor = 0

    init(_ data: Data) { self.data = data }

    static func inspect(_ url: URL) throws -> Report {
        var inspector = DocumentInspector(try Data(contentsOf: url))
        return try inspector.run()
    }

    // MARK: Primitives

    private mutating func bytes(_ count: Int) throws -> Data {
        guard cursor + count <= data.count else {
            throw Failure.message("ran past the end of the file at \(cursor) wanting \(count) bytes")
        }
        defer { cursor += count }
        return data[(data.startIndex + cursor)..<(data.startIndex + cursor + count)]
    }

    private mutating func uint(_ width: Int) throws -> Int {
        try bytes(width).reduce(0) { $0 << 8 | Int($1) }
    }

    private mutating func int16() throws -> Int {
        Int(Int16(bitPattern: UInt16(try uint(2))))
    }

    private mutating func int32() throws -> Int {
        Int(Int32(bitPattern: UInt32(try uint(4))))
    }

    private mutating func signature() throws -> String {
        String(decoding: try bytes(4), as: UTF8.self)
    }

    private mutating func expect(_ tag: String, _ context: String) throws {
        let found = try signature()
        guard found == tag else {
            throw Failure.message("expected '\(tag)' \(context) at \(cursor - 4), found '\(found)'")
        }
    }

    // MARK: Walk

    private mutating func run() throws -> Report {
        try expect("8BPS", "file signature")
        let version = try uint(2)
        guard version == 1 || version == 2 else {
            throw Failure.message("unknown version \(version)")
        }
        let psb = version == 2
        let sectionWidth = psb ? 8 : 4
        let channelLengthWidth = psb ? 8 : 4

        _ = try bytes(6)
        let channels = try uint(2)
        let height = try uint(4)
        let width = try uint(4)
        let depth = try uint(2)
        let colorMode = try uint(2)

        let colorModeLength = try uint(4)
        _ = try bytes(colorModeLength)

        let resourceIDs = try walkImageResources()

        let sectionLength = try uint(sectionWidth)
        let sectionEnd = cursor + sectionLength

        var layers: [Layer] = []
        var layerCountField = 0
        var taggedBlocks: [String] = []
        var taggedBlockLengths: [String: Int] = [:]

        let layerInfoLength = try uint(sectionWidth)
        if layerInfoLength > 0 {
            let end = cursor + layerInfoLength
            (layerCountField, layers) = try walkLayerInfo(channelLengthWidth: channelLengthWidth)
            try checkLanding(at: end, section: "layer info")
            cursor = end
        }

        let globalMaskLength = try uint(4)
        _ = try bytes(globalMaskLength)

        // Tagged blocks, which is where a 16-bit document keeps its layers.
        while cursor + 12 <= sectionEnd {
            let tag = try signature()
            guard tag == "8BIM" || tag == "8B64" else {
                throw Failure.message("unexpected tagged-block signature '\(tag)' at \(cursor - 4)")
            }
            let key = try signature()
            taggedBlocks.append(key)
            let wideKeys: Set<String> = ["LMsk", "Lr16", "Lr32", "Layr", "Mt16", "Mt32", "Mtrn",
                                         "Alph", "FMsk", "lnk2", "FEid", "FXid", "PxSD"]
            let lengthWidth = (psb && wideKeys.contains(key)) ? 8 : 4
            let blockLength = try uint(lengthWidth)
            taggedBlockLengths[key] = blockLength
            let blockEnd = cursor + blockLength

            if key == "Lr16" || key == "Lr32" {
                (layerCountField, layers) = try walkLayerInfo(channelLengthWidth: channelLengthWidth)
                // Global tagged blocks align to four, so up to three bytes may be slack.
                try checkLanding(at: blockEnd, section: "\(key) block", allowedSlack: 3)
            }
            cursor = blockEnd + ((4 - blockLength % 4) % 4)
        }

        guard cursor <= sectionEnd else {
            throw Failure.message("layer and mask section overran by \(cursor - sectionEnd) bytes")
        }
        cursor = sectionEnd

        let imageDataCompression = try uint(2)

        return Report(
            version: version, channels: channels, width: width, height: height,
            depth: depth, colorMode: colorMode, resourceIDs: resourceIDs,
            layers: layers, layerCountField: layerCountField, taggedBlocks: taggedBlocks,
            taggedBlockLengths: taggedBlockLengths,
            imageDataCompression: imageDataCompression,
            bytesAfterImageData: data.count - cursor
        )
    }

    private mutating func checkLanding(at end: Int, section: String, allowedSlack: Int = 1) throws {
        let slack = end - cursor
        guard slack >= 0 else {
            throw Failure.message("\(section) overran its declared length by \(-slack) bytes")
        }
        guard slack <= allowedSlack else {
            throw Failure.message("\(section) declared \(slack) more bytes than it used")
        }
    }

    private mutating func walkImageResources() throws -> [Int] {
        let length = try uint(4)
        let end = cursor + length
        var ids: [Int] = []
        while cursor < end {
            try expect("8BIM", "image resource")
            ids.append(try uint(2))
            let nameLength = try uint(1)
            _ = try bytes(nameLength + ((nameLength + 1) % 2 == 0 ? 0 : 1))
            let size = try uint(4)
            _ = try bytes(size + size % 2)
        }
        guard cursor == end else {
            throw Failure.message("image resources overran by \(cursor - end) bytes")
        }
        return ids
    }

    private mutating func walkLayerInfo(channelLengthWidth: Int) throws -> (Int, [Layer]) {
        let countField = try int16()
        let count = abs(countField)
        var layers: [Layer] = []

        for index in 0..<count {
            let top = try int32(), left = try int32(), bottom = try int32(), right = try int32()
            let channelCount = try uint(2)
            var ids: [Int] = []
            var lengths: [Int] = []
            for _ in 0..<channelCount {
                ids.append(try int16())
                lengths.append(try uint(channelLengthWidth))
            }
            try expect("8BIM", "blend mode signature of layer \(index)")
            let blendMode = try signature()
            let opacity = try uint(1)
            _ = try uint(1)                                     // clipping
            _ = try uint(1)                                     // flags
            _ = try uint(1)                                     // filler

            let extraLength = try uint(4)
            let extraEnd = cursor + extraLength
            let maskLength = try uint(4)
            _ = try bytes(maskLength)
            let rangesLength = try uint(4)
            _ = try bytes(rangesLength)

            let nameLength = try uint(1)
            let name = String(decoding: try bytes(nameLength), as: UTF8.self)
            let padded = (nameLength + 1) % 4
            if padded != 0 { _ = try bytes(4 - padded) }

            var unicodeName: String?
            while cursor + 12 <= extraEnd {
                try expect("8BIM", "layer tagged block")
                let key = try signature()
                let blockLength = try uint(4)
                let blockEnd = cursor + blockLength
                if key == "luni" {
                    let units = try uint(4)
                    var scalars: [UInt16] = []
                    for _ in 0..<units { scalars.append(UInt16(try uint(2))) }
                    unicodeName = String(decoding: scalars, as: UTF16.self)
                }
                cursor = blockEnd + (blockLength % 2)
            }
            guard cursor <= extraEnd else {
                throw Failure.message("layer \(index) extra data overran by \(cursor - extraEnd) bytes")
            }
            cursor = extraEnd

            layers.append(Layer(
                name: name, unicodeName: unicodeName,
                rect: (top, left, bottom, right),
                channelIDs: ids, channelLengths: lengths,
                opacity: opacity, blendMode: blendMode
            ))
        }

        // Channel data follows every record, in the same order.
        for (index, layer) in layers.enumerated() {
            for (channel, length) in zip(layer.channelIDs, layer.channelLengths) {
                guard length >= 2 else {
                    throw Failure.message("layer \(index) channel \(channel) declares only \(length) bytes")
                }
                _ = try bytes(length)
            }
        }
        return (countField, layers)
    }
}
