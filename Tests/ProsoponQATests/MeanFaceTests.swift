import Foundation
import ProsoponCore
import Testing
@testable import ProsoponQA

@Suite("Mean face")
struct MeanFaceTests {

    private var options: QAOptions { QAOptions(spec: SyntheticStack.spec) }

    @Test("a correctly aligned stack shows no displacement")
    func alignedStackIsQuiet() async throws {
        let jitters = [Point2D](repeating: .zero, count: 6)
        let (directory, urls) = try SyntheticStack.write(jitters: jitters)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await MeanFaceBuilder.analyse(tiles: urls, options: options)
        #expect(result.report.tileCount == 6)
        for tile in result.report.tiles {
            #expect(tile.worstDisplacement < 0.3,
                    "\(tile.name) drifted \(tile.worstDisplacement) px with nothing injected")
            #expect(tile.lowestCorrelation > 0.9)
        }
    }

    @Test("injected jitter comes back out as the measured displacement")
    func jitterIsRecovered() async throws {
        // The reference is the stack's own average, so what any one tile can be measured
        // against is its distance from the average jitter, not its absolute offset.
        let jitters = [
            Point2D.zero, Point2D(4, 0), Point2D(0, -3), Point2D(-5, 2),
            Point2D.zero, Point2D(2.5, 1.5), Point2D.zero, Point2D.zero,
        ]
        let (directory, urls) = try SyntheticStack.write(jitters: jitters)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await MeanFaceBuilder.analyse(tiles: urls, options: options)
        let centre = SyntheticStack.meanJitter(jitters)

        for (index, tile) in result.report.tiles.enumerated() {
            let expected = jitters[index] - centre
            let measured = tile.offsets[.viewerLeftEye] ?? .none
            #expect(abs(measured.dx - expected.x) < 0.5,
                    "\(tile.name): dx \(measured.dx), expected \(expected.x)")
            #expect(abs(measured.dy - expected.y) < 0.5,
                    "\(tile.name): dy \(measured.dy), expected \(expected.y)")
        }
    }

    @Test("the worst tile is the one that was moved furthest")
    func worstTileIsIdentified() async throws {
        var jitters = [Point2D](repeating: .zero, count: 8)
        jitters[5] = Point2D(7, -6)
        let (directory, urls) = try SyntheticStack.write(jitters: jitters)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await MeanFaceBuilder.analyse(tiles: urls, options: options)
        let suspects = result.report.suspects(beyond: 2)
        #expect(suspects.first?.name == "t05", "expected t05 at the top, got \(suspects.first?.name ?? "none")")
        #expect(suspects.count == 1, "only one tile was moved, \(suspects.count) were reported")
    }

    @Test("landmarks survive averaging better than the rest of the canvas")
    func registrationContrastExceedsOne() async throws {
        // This is the headline claim the whole view rests on: with the stack registered,
        // the parts held in common stay crisp while everything individual averages away.
        let (directory, urls) = try SyntheticStack.write(jitters: [Point2D](repeating: .zero, count: 12))
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await MeanFaceBuilder.analyse(tiles: urls, options: options)
        // Measured at 1.45 on this stack. Retention sits below 1 even when perfectly
        // registered, because the patches take in surrounding detail that does average
        // away; what carries the signal is the ratio against the whole canvas.
        #expect(result.report.registrationContrast > 1.3,
                "contrast was \(result.report.registrationContrast)")
        for landmark in Landmark.allCases {
            let retention = try #require(result.report.landmarkSharpness[landmark]).retention
            #expect(retention > 0.75, "\(landmark.shortName) retained only \(retention)")
        }
    }

    @Test("misalignment shows up as a loss of contrast in the average")
    func jitterReducesContrast() async throws {
        let aligned = [Point2D](repeating: .zero, count: 6)
        let scattered = [
            Point2D(-6, 4), Point2D(5, -5), Point2D(0, 6), Point2D(-4, -4),
            Point2D(6, 1), Point2D(-2, -6),
        ]

        let (directoryA, urlsA) = try SyntheticStack.write(jitters: aligned)
        defer { try? FileManager.default.removeItem(at: directoryA) }
        let (directoryB, urlsB) = try SyntheticStack.write(jitters: scattered)
        defer { try? FileManager.default.removeItem(at: directoryB) }

        let good = try await MeanFaceBuilder.analyse(tiles: urlsA, options: options).report
        let bad = try await MeanFaceBuilder.analyse(tiles: urlsB, options: options).report

        #expect(bad.registrationContrast < good.registrationContrast,
                "scattered \(bad.registrationContrast) should sit below aligned \(good.registrationContrast)")
        #expect(bad.percentile(0.5) > good.percentile(0.5),
                "scattered tiles should sit further from consensus")
    }

    @Test("the mean and deviation images come out at canvas size")
    func imagesAreProduced() async throws {
        let (directory, urls) = try SyntheticStack.write(jitters: [Point2D](repeating: .zero, count: 3))
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await MeanFaceBuilder.analyse(tiles: urls, options: options)
        let side = Int(SyntheticStack.side)
        #expect(result.mean.width == side && result.mean.height == side)
        #expect(result.deviation.width == side && result.deviation.height == side)
        #expect(result.mean.makeCGImage() != nil)
        #expect(result.deviation.makeCGImage() != nil)
    }

    @Test("a tile of the wrong size is rejected by name")
    func sizeMismatchIsRejected() async throws {
        let (directory, urls) = try SyntheticStack.write(jitters: [Point2D](repeating: .zero, count: 2))
        defer { try? FileManager.default.removeItem(at: directory) }

        await #expect(throws: QAError.self) {
            // The standard 2048 spec against 512 px tiles.
            _ = try await MeanFaceBuilder.analyse(tiles: urls, options: QAOptions())
        }
    }

    @Test("an empty stack is refused")
    func emptyStackIsRefused() async throws {
        await #expect(throws: QAError.self) {
            _ = try await MeanFaceBuilder.analyse(tiles: [], options: options)
        }
    }

    @Test("the contact sheet lays out the tiles it is given")
    func contactSheetRenders() async throws {
        let (directory, urls) = try SyntheticStack.write(jitters: [Point2D](repeating: .zero, count: 5))
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await MeanFaceBuilder.analyse(tiles: urls, options: options)
        let style = ContactSheet.Style(cell: 120, columns: 3, padding: 6, labelHeight: 20)
        let sheet = try #require(try ContactSheet.render(
            tiles: result.report.tiles, spec: SyntheticStack.spec, style: style
        ))
        // Five tiles across three columns is two rows.
        #expect(sheet.width == 3 * (120 + 6) + 6)
        #expect(sheet.height == 2 * (120 + 20 + 6) + 6)
    }
}
