import Foundation

/// Turns channel planes into the byte payloads Photoshop expects, including the
/// two-byte compression marker that precedes them.
///
/// Each channel is coded into a single growable buffer rather than one array per
/// scanline: at 2048 x 2048 that is a couple of allocations per channel instead of two
/// thousand. It is a modest win -- the working set is dominated by the pixel buffers,
/// not by these -- but it keeps the allocation count proportional to channels rather
/// than to pixels.
enum ChannelEncoder {

    /// A single layer channel: marker, then either the raw rows, or a scanline
    /// byte-count table followed by the PackBits rows.
    static func encode(
        plane: [UInt8],
        width: Int,
        height: Int,
        bytesPerSample: Int,
        compression: Compression,
        format: DocumentFormat
    ) -> Data {
        switch compression {
        case .raw:
            var payload = Data(capacity: plane.count + 2)
            payload.appendBE(compression.marker)
            payload.append(contentsOf: plane)
            return payload

        case .rle:
            var body = [UInt8]()
            var counts = [Int]()
            pack(plane: plane, width: width, height: height, bytesPerSample: bytesPerSample,
                 into: &body, counts: &counts)

            var payload = Data(capacity: body.count + counts.count * format.rleCountBytes + 2)
            payload.appendBE(compression.marker)
            appendCounts(counts, to: &payload, format: format)
            payload.append(contentsOf: body)
            return payload
        }
    }

    /// The merged composite is laid out differently: one marker for the whole section,
    /// then every channel's scanline counts together, then every channel's data together.
    static func encodeMerged(
        planes: [[UInt8]],
        width: Int,
        height: Int,
        bytesPerSample: Int,
        compression: Compression,
        format: DocumentFormat
    ) -> Data {
        switch compression {
        case .raw:
            var payload = Data(capacity: planes.reduce(2) { $0 + $1.count })
            payload.appendBE(compression.marker)
            for plane in planes { payload.append(contentsOf: plane) }
            return payload

        case .rle:
            var bodies: [[UInt8]] = []
            var counts: [Int] = []
            bodies.reserveCapacity(planes.count)
            counts.reserveCapacity(planes.count * height)

            for plane in planes {
                var body = [UInt8]()
                pack(plane: plane, width: width, height: height, bytesPerSample: bytesPerSample,
                     into: &body, counts: &counts)
                bodies.append(body)
            }

            var payload = Data(capacity: bodies.reduce(2) { $0 + $1.count } + counts.count * format.rleCountBytes)
            payload.appendBE(compression.marker)
            appendCounts(counts, to: &payload, format: format)
            for body in bodies { payload.append(contentsOf: body) }
            return payload
        }
    }

    /// Codes every scanline of `plane` into `body`, appending each row's length to `counts`.
    private static func pack(
        plane: [UInt8],
        width: Int,
        height: Int,
        bytesPerSample: Int,
        into body: inout [UInt8],
        counts: inout [Int]
    ) {
        let rowBytes = width * bytesPerSample
        // PackBits' worst case is one control byte per 128 literals.
        body.reserveCapacity(body.count + plane.count + plane.count / 128 + height + 2)
        plane.withUnsafeBufferPointer { buffer in
            for row in 0..<height {
                let start = row * rowBytes
                let before = body.count
                PackBits.encode(UnsafeBufferPointer(rebasing: buffer[start..<(start + rowBytes)]), into: &body)
                counts.append(body.count - before)
            }
        }
    }

    /// Scanline byte counts are 16-bit in a `.psd` and 32-bit in a `.psb`.
    private static func appendCounts(_ counts: [Int], to payload: inout Data, format: DocumentFormat) {
        for count in counts {
            if format.rleCountBytes == 2 {
                payload.appendBE(UInt16(count))
            } else {
                payload.appendBE(UInt32(count))
            }
        }
    }
}
