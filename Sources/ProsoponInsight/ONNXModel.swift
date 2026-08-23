import Foundation
import OnnxRuntimeBindings

public enum InsightError: Error, CustomStringConvertible {
    case modelsNotFound([String])
    case modelLoadFailed(String, String)
    case inferenceFailed(String)
    case unexpectedOutputs(String)

    public var description: String {
        switch self {
        case .modelsNotFound(let searched):
            """
            could not find the buffalo_l models. Looked in:
            \(searched.map { "  \($0)" }.joined(separator: "\n"))
            Point --model-path at a directory holding det_10g.onnx and 2d106det.onnx.
            """
        case .modelLoadFailed(let path, let reason):
            "could not load \((path as NSString).lastPathComponent): \(reason)"
        case .inferenceFailed(let reason):
            "inference failed: \(reason)"
        case .unexpectedOutputs(let detail):
            "the model produced outputs this code does not know how to read: \(detail)"
        }
    }
}

/// One tensor coming back from a model.
struct ONNXTensor {
    let name: String
    let shape: [Int]
    let values: [Float]

    /// Elements per row, for the `[rows, channels]` outputs the detector produces.
    var channels: Int { shape.count >= 2 ? shape[shape.count - 1] : 1 }
    var rows: Int { channels > 0 ? values.count / channels : 0 }
}

/// A thin wrapper over one ONNX Runtime session.
///
/// Sessions are documented as thread-safe for `Run`, so a batch can drive one loaded
/// model from several tasks at once; the class is a reference type for that reason.
final class ONNXModel: @unchecked Sendable {
    private let environment: ORTEnv
    private let session: ORTSession
    let inputName: String
    let outputNames: [String]

    init(path: String, useCoreML: Bool = true) throws {
        do {
            environment = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            try options.setGraphOptimizationLevel(.all)
            if useCoreML {
                // Falls back to CPU for anything the Neural Engine cannot take.
                try? options.appendCoreMLExecutionProvider(with: ORTCoreMLExecutionProviderOptions())
            }
            session = try ORTSession(env: environment, modelPath: path, sessionOptions: options)
            inputName = try session.inputNames().first ?? "input"
            outputNames = try session.outputNames()
        } catch {
            throw InsightError.modelLoadFailed(path, "\(error)")
        }
    }

    /// Runs the model on a single NCHW float tensor.
    func run(_ input: [Float], shape: [Int]) throws -> [ONNXTensor] {
        do {
            let data = NSMutableData(
                bytes: input, length: input.count * MemoryLayout<Float>.size
            )
            let value = try ORTValue(
                tensorData: data,
                elementType: .float,
                shape: shape.map { NSNumber(value: $0) }
            )
            let outputs = try session.run(
                withInputs: [inputName: value],
                outputNames: Set(outputNames),
                runOptions: nil
            )
            return try outputNames.compactMap { name -> ONNXTensor? in
                guard let output = outputs[name] else { return nil }
                let info = try output.tensorTypeAndShapeInfo()
                let bytes = try output.tensorData() as Data
                let floats = bytes.withUnsafeBytes { raw in
                    Array(raw.bindMemory(to: Float.self))
                }
                return ONNXTensor(
                    name: name, shape: info.shape.map(\.intValue), values: floats
                )
            }
        } catch let error as InsightError {
            throw error
        } catch {
            throw InsightError.inferenceFailed("\(error)")
        }
    }
}
