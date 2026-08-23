import Foundation
import ProsoponCore
import Testing
@testable import ProsoponQA

/// Checks the shape of what actually reaches disk.
///
/// The bug these exist to prevent was invisible to every other test: `qa.json` was
/// written with its landmark offsets as a flat array rather than an object, and the
/// review app -- which decoded them as an object, failed, and swallowed the error --
/// silently lost a whole feature. The fixture it was tested against had been written by
/// hand in the shape the reader expected, so the tests confirmed an assumption instead
/// of the encoder. These assert against the encoder's own output.
@Suite("QA serialisation")
struct SerialisationTests {

    private func report() -> StackQA {
        StackQA(
            tileCount: 1,
            canvasSize: 2048,
            landmarkSharpness: [
                .viewerLeftEye: SharpnessRetention(meanImageAcutance: 9, averageTileAcutance: 12, retention: 0.75),
            ],
            globalSharpness: SharpnessRetention(meanImageAcutance: 3, averageTileAcutance: 9, retention: 0.33),
            tiles: [
                TileQA(name: "a", path: "/tmp/a.png", offsets: [
                    .viewerLeftEye: ConsensusOffset(dx: -1.5, dy: 2, correlation: 0.91, clipped: false),
                    .mouth: ConsensusOffset(dx: 0.25, dy: -0.5, correlation: 0.88, clipped: false),
                ]),
            ]
        )
    }

    private func encoded() throws -> [String: Any] {
        let data = try JSONEncoder().encode(report())
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("landmark-keyed offsets are written as an object, not a flat array")
    func offsetsAreAnObject() throws {
        let json = try encoded()
        let tiles = try #require(json["tiles"] as? [[String: Any]])
        let offsets = tiles[0]["offsets"]

        #expect(offsets is [String: Any],
                "offsets came out as \(type(of: offsets as Any)); a flat array here is the bug")

        let keyed = try #require(offsets as? [String: Any])
        #expect(Set(keyed.keys) == ["viewerLeftEye", "mouth"])
        let mouth = try #require(keyed["mouth"] as? [String: Any])
        #expect((mouth["dx"] as? Double).map { abs($0 - 0.25) < 1e-9 } == true)
        #expect((mouth["correlation"] as? Double).map { abs($0 - 0.88) < 1e-9 } == true)
    }

    @Test("the per-landmark sharpness map is an object too")
    func sharpnessIsAnObject() throws {
        let json = try encoded()
        #expect(json["landmarkSharpness"] is [String: Any],
                "the same dictionary-key trap applies here")
        let keyed = try #require(json["landmarkSharpness"] as? [String: Any])
        #expect(keyed["viewerLeftEye"] != nil)
    }

    @Test("a report survives a round trip through JSON")
    func roundTrip() throws {
        let data = try JSONEncoder().encode(report())
        let back = try JSONDecoder().decode(StackQA.self, from: data)
        #expect(back.tileCount == 1)
        #expect(back.tiles[0].offsets[.mouth]?.correlation == 0.88)
        #expect(back.tiles[0].offsets[.viewerLeftEye]?.dx == -1.5)
        #expect(back.landmarkSharpness[.viewerLeftEye]?.retention == 0.75)
    }

    @Test("every landmark key survives being used as a dictionary key")
    func allLandmarksRoundTrip() throws {
        let offsets = Dictionary(uniqueKeysWithValues: Landmark.allCases.map {
            ($0, ConsensusOffset(dx: 1, dy: 2, correlation: 0.5, clipped: false))
        })
        let tile = TileQA(name: "n", path: "/p", offsets: offsets)
        let back = try JSONDecoder().decode(TileQA.self, from: try JSONEncoder().encode(tile))
        #expect(Set(back.offsets.keys) == Set(Landmark.allCases))
    }
}
