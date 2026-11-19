#if os(iOS)
import SwiftUI
import UIKit

/// A page image that zooms like Photos: pinch, double tap at a point (again to zoom out), pan while zoomed.
/// Backed by `UIScrollView`, which does the zooming, the bounce and the panning itself. Reports whether it is
/// zoomed, and returns to its normal size when `isZoomed` turns false (another page, another mode).
struct ZoomablePageImage: UIViewRepresentable {
    /// The page as the server sent it; decoded again only when it changes.
    let data: Data
    /// Read by VoiceOver for the image.
    let label: String
    let hint: String
    let isZoomed: Bool
    let zoomDidChange: (Bool) -> Void

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        ZoomingImageScrollView()
    }

    func updateUIView(_ view: ZoomingImageScrollView, context: Context) {
        view.show(data)
        view.imageView.accessibilityLabel = label
        view.imageView.accessibilityHint = hint
        view.zoomDidChange = zoomDidChange
        if !isZoomed { view.resetZoom() }
    }
}

/// The scroll view behind `ZoomablePageImage`: the image fits the screen at scale 1 and stays centred.
final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var zoomDidChange: ((Bool) -> Void)?
    private var data: Data?
    private var laidOutSize: CGSize = .zero
    private var reportedZoom = false
    private static let doubleTapScale: CGFloat = 2.5

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show(_ data: Data) {
        guard data != self.data else { return }
        self.data = data
        imageView.image = UIImage(data: data)
        laidOutSize = .zero
        setNeedsLayout()
    }

    /// Back to the size that fits, without reporting it: the model already says "not zoomed". Not while the
    /// user is pinching (their zoom has not been reported yet).
    func resetZoom() {
        guard zoomScale != minimumZoomScale, !isZooming, !isZoomBouncing else { return }
        reportedZoom = false
        setZoomScale(minimumZoomScale, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A new size (rotation, first layout): start again at the size that fits.
        if bounds.size != laidOutSize {
            laidOutSize = bounds.size
            setZoomScale(minimumZoomScale, animated: false)
            imageView.frame = CGRect(origin: .zero, size: fittedSize)
            contentSize = imageView.frame.size
        }
        centre()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
        let zoomed = zoomScale > minimumZoomScale + 0.01
        guard zoomed != reportedZoom else { return }
        reportedZoom = zoomed
        // Reported after the current layout or view update, never inside it.
        Task { @MainActor [zoomDidChange] in zoomDidChange?(zoomed) }
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let point = recognizer.location(in: imageView)
        let scale = min(maximumZoomScale, Self.doubleTapScale)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        let target = CGRect(
            x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height
        )
        zoom(to: target, animated: true)
    }

    /// The image at its largest size that fits the bounds, keeping its proportions.
    private var fittedSize: CGSize {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0,
              bounds.height > 0
        else { return bounds.size }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Keeps a page smaller than the screen in the middle instead of in the top left corner.
    private func centre() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
}
#endif
