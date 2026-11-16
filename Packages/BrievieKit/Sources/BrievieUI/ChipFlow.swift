import SwiftUI

/// Lays its subviews (chips) out left to right and wraps them over as many lines as needed. A chip wider than
/// the space is offered the full width, so its text wraps inside the chip instead of being cut.
public struct ChipFlow: Layout {
    private let spacing: CGFloat

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let maxWidth = width ?? .infinity
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            size.width = min(size.width, maxWidth)
            if origin.x > 0, origin.x + size.width > maxWidth {
                origin.x = 0
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, origin.x - spacing)
        }
        let height = frames.isEmpty ? 0 : origin.y + lineHeight
        return (frames, CGSize(width: usedWidth, height: height))
    }
}
