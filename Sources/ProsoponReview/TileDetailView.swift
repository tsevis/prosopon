import CoreGraphics
import ProsoponCore
import SwiftUI

/// The working view: one tile at preview scale with the target grid over it and the
/// three landmarks draggable.
///
/// Dragging a marker says "the feature you are aiming at is actually here". The point
/// travels back through the transform to become the corrected source landmark, and on
/// release the image moves so that feature lands on the crosshair — the marker returns
/// to its target, because in canvas space that is where the landmarks always are.
///
/// The image deliberately does not follow the marker mid-drag. Re-solving live would
/// slide the feature away from under the cursor as it was being aimed at.
public struct TileDetailView: View {
    public let session: ReviewSession
    public let renderer: PreviewRenderer

    @State private var preview: CGImage?
    @State private var dragging: Landmark?
    @State private var dragCanvasPoint: Point2D?
    @State private var renderFailure: String?

    public init(session: ReviewSession, renderer: PreviewRenderer) {
        self.session = session
        self.renderer = renderer
    }

    private var entry: ReviewEntry? { session.selected }

    /// What the metrics should describe: the prospective solve while dragging, so the
    /// numbers move with the marker, and the committed one otherwise.
    private var displayedEntry: ReviewEntry? {
        guard let dragging, let point = dragCanvasPoint else { return entry }
        return session.prospectiveEntry(dragging, atCanvasPoint: point) ?? entry
    }

    public var body: some View {
        VStack(spacing: 0) {
            canvas
            Divider()
            MetricsPanel(
                entry: displayedEntry, spec: session.spec,
                yawCaveat: session.yawCaveat, isProvisional: dragging != nil
            )
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let geometry = CanvasGeometry(canvasSize: session.spec.size, availableSize: proxy.size)
            ZStack(alignment: .topLeading) {
                Theme.canvas
                if let preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .frame(width: geometry.frame.width, height: geometry.frame.height)
                        .position(x: geometry.frame.midX, y: geometry.frame.midY)
                }
                GridOverlay(geometry: geometry, spec: session.spec)
                ForEach(Landmark.allCases, id: \.self) { landmark in
                    marker(landmark, geometry: geometry)
                }
                if let renderFailure {
                    Text(renderFailure)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(8)
                }
            }
            .contentShape(Rectangle())
        }
        .task(id: renderKey) { await refreshPreview() }
    }

    /// Re-render whenever the tile or its landmarks change, but not while dragging.
    private var renderKey: String {
        guard let entry else { return "none" }
        return "\(entry.id)|\(entry.landmarks)"
    }

    private func marker(_ landmark: Landmark, geometry: CanvasGeometry) -> some View {
        let canvasPoint = (dragging == landmark ? dragCanvasPoint : nil)
            ?? landmark.target(in: session.spec)
        let position = geometry.viewPoint(canvasPoint)
        let radius = max(10.0, session.spec.gridStep * geometry.scale * 0.5)

        return LandmarkMarker(isActive: dragging == landmark, radius: radius)
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = landmark
                        dragCanvasPoint = geometry.canvasPoint(value.location)
                    }
                    .onEnded { value in
                        session.moveLandmark(landmark, toCanvasPoint: geometry.canvasPoint(value.location))
                        dragging = nil
                        dragCanvasPoint = nil
                    }
            )
            .help("Drag onto the \(landmark.displayName) as it actually appears")
    }

    private func refreshPreview() async {
        guard let entry else {
            preview = nil
            return
        }
        let renderer = renderer
        let rendered = await Task.detached(priority: .userInitiated) { () -> Result<SendableImage?, Error> in
            do { return .success(try renderer.preview(of: entry).map(SendableImage.init)) }
            catch { return .failure(error) }
        }.value

        switch rendered {
        case .success(let image):
            preview = image?.image
            renderFailure = image == nil ? "this tile cannot be solved" : nil
        case .failure(let error):
            preview = nil
            renderFailure = "\(error)"
        }
    }
}

private struct LandmarkMarker: View {
    let isActive: Bool
    let radius: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(isActive ? 0.75 : 0.45))
            Circle()
                .stroke(Color.cyan.opacity(0.9), lineWidth: isActive ? 2 : 1)
            Path { path in
                path.move(to: CGPoint(x: 0, y: radius))
                path.addLine(to: CGPoint(x: radius * 2, y: radius))
                path.move(to: CGPoint(x: radius, y: 0))
                path.addLine(to: CGPoint(x: radius, y: radius * 2))
            }
            .stroke(Color.cyan, lineWidth: 1)
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

/// The 128 px grid and the crosshairs through the three targets, matching the overlays
/// the batch tools write.
private struct GridOverlay: View {
    let geometry: CanvasGeometry
    let spec: CanvasSpec

    var body: some View {
        Path { path in
            var offset = spec.gridStep
            while offset < spec.size {
                let vertical = geometry.viewPoint(Point2D(offset, 0))
                path.move(to: vertical)
                path.addLine(to: geometry.viewPoint(Point2D(offset, spec.size)))
                let horizontal = geometry.viewPoint(Point2D(0, offset))
                path.move(to: horizontal)
                path.addLine(to: geometry.viewPoint(Point2D(spec.size, offset)))
                offset += spec.gridStep
            }
        }
        .stroke(Color.purple.opacity(0.25), lineWidth: 0.5)
        .overlay {
            Path { path in
                for x in [spec.viewerLeftEye.x, spec.mouth.x, spec.viewerRightEye.x] {
                    path.move(to: geometry.viewPoint(Point2D(x, 0)))
                    path.addLine(to: geometry.viewPoint(Point2D(x, spec.size)))
                }
                for y in [spec.eyeLineY, spec.mouth.y] {
                    path.move(to: geometry.viewPoint(Point2D(0, y)))
                    path.addLine(to: geometry.viewPoint(Point2D(spec.size, y)))
                }
            }
            .stroke(Color.cyan.opacity(0.55), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
