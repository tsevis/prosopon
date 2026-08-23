import ProsoponCore
import SwiftUI

/// The numbers behind the picture: what the solve had to do, and whether the result
/// clears the gates.
struct MetricsPanel: View {
    let entry: ReviewEntry?
    let spec: CanvasSpec
    /// True while a drag is in flight, when these describe a solve not yet committed.
    let isProvisional: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            if let entry {
                if let quality = entry.quality, let alignment = entry.alignment {
                    column("Mouth error", value(alignment.mouthResidual.length, "px"),
                           warn: alignment.mouthResidual.length > 1)
                    column("Stretch", signed(alignment.appliedStretchPercent, "%"),
                           note: alignment.stretchWasClamped
                               ? "capped, wanted \(String(format: "%+.1f", alignment.requestedStretchPercent))%"
                               : nil,
                           warn: alignment.stretchWasClamped)
                    column("Coverage", value(quality.coverage * 100, "%"),
                           warn: quality.coverage < 1)
                    column("Magnification", value(quality.magnification, "x"),
                           note: quality.magnification > 1 ? "enlarged, will be soft" : nil,
                           warn: quality.magnification > 1.5)
                    column("Roll removed", signed(quality.rollCorrectionDegrees, "\u{00B0}"))
                    column("Yaw", quality.yawDegrees.map { signed($0, "\u{00B0}") } ?? "not measured",
                           note: quality.yawDegrees.map { abs($0) > 20 ? "turned away" : nil } ?? nil,
                           warn: (quality.yawDegrees.map { abs($0) > 20 } ?? false))
                    column("Score", value(quality.score, ""), warn: !quality.isAccepted)
                } else {
                    Text(entry.failure ?? "not solved")
                        .foregroundStyle(.orange)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if isProvisional {
                        Label("while dragging", systemImage: "hand.draw")
                            .font(.caption).foregroundStyle(.cyan)
                    } else if entry.isEdited {
                        Label("edited", systemImage: "pencil")
                            .font(.caption).foregroundStyle(.yellow)
                    }
                    if let rejections = entry.quality?.rejections, !rejections.isEmpty {
                        Text(rejections.map(\.rawValue).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            } else {
                Text("No tile selected").foregroundStyle(.secondary)
            }
        }
        .font(.system(.body, design: .monospaced))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.15))
    }

    private func column(
        _ title: String, _ text: String, note: String? = nil, warn: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text).foregroundStyle(warn ? .orange : .primary)
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func value(_ number: Double, _ unit: String) -> String {
        String(format: "%.2f%@", number, unit)
    }

    private func signed(_ number: Double, _ unit: String) -> String {
        String(format: "%+.2f%@", number, unit)
    }
}
