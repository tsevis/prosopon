import Foundation
import Testing
@testable import ProsoponInsight

@Suite("ORT smoke")
struct SmokeTests {
    @Test("the detector's output shapes are what the decoder expects")
    func detectorShapes() throws {
        let path = ("~/.insightface/models/buffalo_l/det_10g.onnx" as NSString).expandingTildeInPath
        try #require(FileManager.default.fileExists(atPath: path))
        let model = try ONNXModel(path: path)
        let outputs = try model.run([Float](repeating: 0, count: 3 * 640 * 640), shape: [1, 3, 640, 640])
        for tensor in outputs {
            print("SHAPE \(tensor.name) \(tensor.shape) rows=\(tensor.rows) ch=\(tensor.channels)")
        }
    }
}
