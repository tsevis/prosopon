import CoreGraphics
import Foundation
import ProsoponIO

extension StackWriter {

    /// Reserves a length field, writes the body, pads the body to `alignment`, and
    /// queues the measured length for patching. Returns whatever the body produced.
    static func lengthPrefixed<T>(
        _ writer: FileWriter,
        lengthBytes: Int,
        alignment: Int,
        patches: PatchList,
        body: () throws -> T
    ) throws -> T {
        let lengthOffset = try writer.reserve(lengthBytes)
        let bodyStart = writer.offset
        let result = try body()
        try writer.padSection(from: bodyStart, to: alignment)
        patches.add(at: lengthOffset, lengthData(writer.offset - bodyStart, bytes: lengthBytes))
        return result
    }

    /// Writes the layer-and-mask section and returns the merged composite's planes.
    ///
    /// A 16-bit document does not keep its layers where an 8-bit one does: the ordinary
    /// layer-info section is left empty and the whole structure moves into an `Lr16`
    /// tagged block. The contents are identical, so one routine writes both.
    static func writeLayerAndMaskSection(
        _ writer: FileWriter,
        layers: [StackLayer],
        width: Int,
        height: Int,
        options: StackOptions,
        patches: PatchList,
        progress: ((Int, Int) -> Void)?
    ) throws -> [[UInt8]] {
        let sectionBytes = options.format.sectionLengthBytes

        return try lengthPrefixed(writer, lengthBytes: sectionBytes, alignment: 2, patches: patches) {
            switch options.depth {
            case .eight:
                let merged = try lengthPrefixed(
                    writer, lengthBytes: sectionBytes, alignment: 2, patches: patches
                ) {
                    try writeLayerInfoBody(
                        writer, layers: layers, width: width, height: height,
                        options: options, patches: patches, progress: progress
                    )
                }
                try writer.write(lengthData(0, bytes: 4))     // no global layer mask
                return merged

            case .sixteen:
                try writer.write(lengthData(0, bytes: sectionBytes))  // layer info: empty
                try writer.write(lengthData(0, bytes: 4))             // no global layer mask

                var tag = Data()
                tag.appendSignature("8BIM")
                tag.appendSignature("Lr16")
                try writer.write(tag)

                // Readers align a *global* tagged block to four bytes rather than two.
                // Making the declared length itself a multiple of four means the padding
                // cannot be double-counted, whichever convention the reader follows.
                return try lengthPrefixed(
                    writer, lengthBytes: sectionBytes, alignment: 4, patches: patches
                ) {
                    try writeLayerInfoBody(
                        writer, layers: layers, width: width, height: height,
                        options: options, patches: patches, progress: progress
                    )
                }
            }
        }
    }

    /// Layer count, then every layer record, then every layer's channel data.
    ///
    /// The records must precede the pixels, and each record declares how many bytes its
    /// channels occupy — unknowable until they are compressed. So the records go out
    /// with their length fields zeroed and their offsets remembered, to be filled in
    /// once the matching channel has been streamed.
    private static func writeLayerInfoBody(
        _ writer: FileWriter,
        layers: [StackLayer],
        width: Int,
        height: Int,
        options: StackOptions,
        patches: PatchList,
        progress: ((Int, Int) -> Void)?
    ) throws -> [[UInt8]] {
        var count = Data()
        // Negative: the merged result carries transparency in its first alpha channel.
        count.appendBE(Int16(-layers.count))
        try writer.write(count)

        var channelLengthOffsets: [[UInt64]] = []
        channelLengthOffsets.reserveCapacity(layers.count)
        for layer in layers {
            channelLengthOffsets.append(
                try writeLayerRecord(writer, layer: layer, width: width, height: height, format: options.format)
            )
        }

        var accumulator = PixelBuffer.transparent(width: width, height: height, depth: options.depth)

        for (index, layer) in layers.enumerated() {
            let image = try ImageLoading.load(layer.url)
            guard image.width == width, image.height == height else {
                throw PSDWriteError.dimensionMismatch(
                    layer.url,
                    expected: "\(width)x\(height)",
                    found: "\(image.width)x\(image.height)"
                )
            }
            guard let buffer = PixelBuffer.premultipliedRGBA(from: image, depth: options.depth) else {
                throw PSDWriteError.pixelExtractionFailed(layer.url)
            }
            accumulator.composite(buffer)

            let planes = buffer.planarChannels(depth: options.depth)
            // Declared channel order is -1, 0, 1, 2; the planes come back R, G, B, A.
            for (slot, plane) in [3, 0, 1, 2].enumerated() {
                let payload = ChannelEncoder.encode(
                    plane: planes[plane], width: width, height: height,
                    bytesPerSample: options.depth.bytesPerSample,
                    compression: options.compression, format: options.format
                )
                try writer.write(payload)
                patches.add(
                    at: channelLengthOffsets[index][slot],
                    lengthData(UInt64(payload.count), bytes: options.format.channelLengthBytes)
                )
            }

            progress?(index + 1, layers.count)
        }

        return accumulator.planarChannels(depth: options.depth)
    }

    /// Returns the file offsets of the four reserved channel-length fields.
    private static func writeLayerRecord(
        _ writer: FileWriter,
        layer: StackLayer,
        width: Int,
        height: Int,
        format: DocumentFormat
    ) throws -> [UInt64] {
        var record = Data()
        record.appendBE(Int32(0))                    // top
        record.appendBE(Int32(0))                    // left
        record.appendBE(Int32(height))               // bottom
        record.appendBE(Int32(width))                // right
        record.appendBE(UInt16(4))

        var relativeOffsets: [Int] = []
        for channelID in [Int16(-1), 0, 1, 2] {
            record.appendBE(channelID)
            relativeOffsets.append(record.count)
            record.append(Data(repeating: 0, count: format.channelLengthBytes))
        }

        record.appendSignature("8BIM")
        record.appendSignature("norm")
        record.appendBE(UInt8(255))                  // opacity
        record.appendBE(UInt8(0))                    // clipping: base
        record.appendBE(UInt8(0x08))                 // bit 3 set: Photoshop 5.0 and later
        record.appendBE(UInt8(0))                    // filler

        var extra = Data()
        extra.appendBE(UInt32(0))                    // no layer mask
        extra.appendBE(UInt32(0))                    // no blending ranges
        extra.appendPascalString(layer.name, paddedTo: 4)

        // The legacy name above is single-byte, so Greek and other non-ASCII filenames
        // only survive in this Unicode block, which Photoshop prefers when present.
        var unicodeName = Data()
        unicodeName.appendUnicodeString(layer.name)
        extra.appendSignature("8BIM")
        extra.appendSignature("luni")
        extra.appendBE(UInt32(unicodeName.count))
        extra.append(unicodeName)

        record.appendBE(UInt32(extra.count))
        record.append(extra)

        let base = writer.offset
        try writer.write(record)
        return relativeOffsets.map { base + UInt64($0) }
    }

    static func lengthData(_ value: UInt64, bytes: Int) -> Data {
        var data = Data()
        if bytes == 4 {
            data.appendBE(UInt32(value))
        } else {
            data.appendBE(value)
        }
        return data
    }
}
