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
        layers: [PSDLayer],
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
        layers: [PSDLayer],
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
                try writeLayerRecord(writer, layer: layer, format: options.format)
            )
        }

        var accumulator = PixelBuffer.transparent(width: width, height: height, depth: options.depth)

        for (index, layer) in layers.enumerated() {
            let buffer = try pixels(for: layer, depth: options.depth)

            // A hidden layer keeps its pixels but must not reach the flattened result:
            // Photoshop computes the composite from what is visible, and a stored
            // composite that disagreed with it would be wrong in whichever program
            // trusted it.
            if layer.isVisible {
                accumulator.composite(buffer, atX: layer.frame.x, atY: layer.frame.y)
            }

            let planes = buffer.planarChannels(depth: options.depth)
            // Declared channel order is -1, 0, 1, 2; the planes come back R, G, B, A.
            for (slot, plane) in [3, 0, 1, 2].enumerated() {
                let payload = ChannelEncoder.encode(
                    plane: planes[plane], width: layer.frame.width, height: layer.frame.height,
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

    /// One layer's pixels, read or drawn, always at its frame's size.
    private static func pixels(for layer: PSDLayer, depth: BitDepth) throws -> PixelBuffer {
        let frame = layer.frame
        guard !frame.isEmpty else { throw PSDWriteError.emptyLayerFrame(layer.name) }

        switch layer.content {
        case .image(let url):
            let image = try ImageLoading.load(url)
            guard image.width == frame.width, image.height == frame.height else {
                throw PSDWriteError.dimensionMismatch(
                    url,
                    expected: "\(frame.width)x\(frame.height)",
                    found: "\(image.width)x\(image.height)"
                )
            }
            guard let buffer = PixelBuffer.premultipliedRGBA(from: image, depth: depth) else {
                throw PSDWriteError.pixelExtractionFailed(url)
            }
            return buffer

        case .croppedImage(let url, let x, let y):
            let image = try ImageLoading.load(url)
            let region = CGRect(x: x, y: y, width: frame.width, height: frame.height)
            guard region.maxX <= CGFloat(image.width), region.maxY <= CGFloat(image.height),
                  x >= 0, y >= 0
            else {
                throw PSDWriteError.cropOutOfBounds(
                    url,
                    region: "\(frame.width)x\(frame.height) at (\(x), \(y))",
                    image: "\(image.width)x\(image.height)"
                )
            }
            guard let cropped = image.cropping(to: region) else {
                throw PSDWriteError.pixelExtractionFailed(url)
            }
            guard let buffer = PixelBuffer.premultipliedRGBA(from: cropped, depth: depth) else {
                throw PSDWriteError.pixelExtractionFailed(url)
            }
            return buffer

        case .solid(let color):
            return .solid(width: frame.width, height: frame.height, depth: depth, color: color)

        case .disc(let color):
            return .disc(width: frame.width, height: frame.height, depth: depth, color: color)
        }
    }

    /// Returns the file offsets of the four reserved channel-length fields.
    private static func writeLayerRecord(
        _ writer: FileWriter,
        layer: PSDLayer,
        format: DocumentFormat
    ) throws -> [UInt64] {
        let frame = layer.frame
        var record = Data()
        record.appendBE(Int32(frame.y))                          // top
        record.appendBE(Int32(frame.x))                          // left
        record.appendBE(Int32(frame.y + frame.height))           // bottom
        record.appendBE(Int32(frame.x + frame.width))            // right
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
        record.appendBE(layerFlags(layer))
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

    /// Bit 0 transparency protected, bit 1 **hidden** rather than visible, bit 3 always
    /// set to say the record is Photoshop 5.0 or later.
    private static func layerFlags(_ layer: PSDLayer) -> UInt8 {
        var flags: UInt8 = 0x08
        if layer.isLocked { flags |= 0x01 }
        if !layer.isVisible { flags |= 0x02 }
        return flags
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
