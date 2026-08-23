import Foundation
import Testing
@testable import ProsoponPSD

@Suite("FileWriter")
struct FileWriterTests {

    private func temporaryURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-fw-\(UInt64.random(in: 0...UInt64.max)).bin")
    }

    @Test("patching rewrites bytes already streamed past")
    func patchingWorksAcrossTheBuffer() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // A flush threshold far below the payload forces the reserved field to be on
        // disk by the time it is patched, which is the case that actually matters.
        let writer = try FileWriter(url: url, flushThreshold: 64)
        let slot = try writer.reserve(4)
        try writer.write(Data(repeating: 0xAB, count: 5000))
        try writer.flush()
        try writer.patch(at: slot, with: StackWriter.lengthData(5000, bytes: 4))
        try writer.close()

        let data = try Data(contentsOf: url)
        #expect(data.count == 5004)
        #expect(Array(data[0..<4]) == [0x00, 0x00, 0x13, 0x88], "5000 as big-endian UInt32")
        #expect(data[4] == 0xAB)
        #expect(data[5003] == 0xAB)
    }

    @Test("section padding aligns the length, not the file offset")
    func paddingAlignsSectionLength() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // Starting at offset 3 makes the two candidate quantities disagree: aligning the
        // file offset would add nothing here, while aligning the body length adds three.
        let writer = try FileWriter(url: url)
        try writer.write(Data(repeating: 0, count: 3))
        let bodyStart = writer.offset
        try writer.write(Data(repeating: 1, count: 5))
        try writer.padSection(from: bodyStart, to: 4)
        try writer.close()

        let total = try Data(contentsOf: url).count
        #expect(total == 11, "3 byte prefix plus a body padded from 5 to 8")
        #expect((total - Int(bodyStart)) % 4 == 0)
    }

    @Test("a size limit stops the write instead of producing an unopenable file")
    func sizeLimitIsEnforcedWhileStreaming() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try FileWriter(url: url, maximumBytes: 1000, flushThreshold: 64)
        #expect(throws: PSDWriteError.self) {
            for _ in 0..<20 { try writer.write(Data(repeating: 0, count: 100)) }
        }
    }
}
