import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasLabeledArtwork: View {
  let asset: String
  let aspectRatio: Double
  @Binding var zoom: Double
  let currentID: String?
  let spots: [(String, Double, Double)]
  let labels: [String]
  let onSelect: (String) -> Void
  @State private var height: CGFloat = 360
  var body: some View {
    GalaxySSIAtlasLabeledScroll(asset: asset, aspectRatio: aspectRatio, zoom: $zoom, height: $height,
      currentID: currentID, spots: spots, labels: labels, onSelect: onSelect)
      .frame(height: height)
  }
}

private struct GalaxySSIAtlasLabeledScroll: UIViewRepresentable {
  let asset: String
  let aspectRatio: Double
  @Binding var zoom: Double
  @Binding var height: CGFloat
  let currentID: String?
  let spots: [(String, Double, Double)]
  let labels: [String]
  let onSelect: (String) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> UIScrollView {
    let scroll = Scroll()
    scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4; scroll.clipsToBounds = true
    scroll.delegate = context.coordinator
    scroll.addSubview(context.coordinator.content)
    let coordinator = context.coordinator
    scroll.onLayout = { [weak coordinator] in coordinator?.layout($0) }
    return scroll
  }
  func updateUIView(_ view: UIScrollView, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    coordinator.content.configure(self)
    coordinator.layout(view)
    view.setNeedsLayout()
  }
  final class Coordinator: NSObject, UIScrollViewDelegate {
    var parent: GalaxySSIAtlasLabeledScroll
    let content = Content()
    private var layoutActive = false
    private var size = CGSize.zero
    init(_ parent: GalaxySSIAtlasLabeledScroll) { self.parent = parent }
    func layout(_ scroll: UIScrollView) {
      guard !layoutActive, scroll.bounds.width > 0 else { return }
      layoutActive = true
      defer { layoutActive = false }
      let height = content.requiredHeight(width: scroll.bounds.width)
      let next = CGSize(width: scroll.bounds.width, height: height)
      if next != size {
        scroll.setZoomScale(1, animated: false)
        size = next
        content.frame = CGRect(origin: .zero, size: next)
        scroll.contentSize = next
      }
      content.layoutIfNeeded()
      if abs(parent.height - height) > 1 {
        DispatchQueue.main.async { [weak self] in
          guard let self, abs(self.parent.height - height) > 1 else { return }
          self.parent.height = height
        }
      }
      if !scroll.isZooming, abs(Double(scroll.zoomScale) - parent.zoom) > 0.01 {
        scroll.setZoomScale(CGFloat(parent.zoom), animated: false)
      }
      if parent.zoom == 1 { scroll.setContentOffset(.zero, animated: false) }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
      parent.zoom = Double(scale)
    }
  }
  final class Scroll: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?(self) }
  }
  final class Content: UIView {
    private let image = UIImageView()
    private let guides = Guides()
    private var buttons: [UIButton] = []
    private var input: GalaxySSIAtlasLabeledScroll?
    private var imageRect = CGRect.zero
    private var routes: [[CGPoint]] = []
    private var fontCategory: UIContentSizeCategory?
    override init(frame: CGRect) {
      super.init(frame: frame); addSubview(image); image.contentMode = .scaleAspectFit
      guides.owner = self; guides.isUserInteractionEnabled = false; guides.isOpaque = false
      addSubview(guides)
      image.isAccessibilityElement = false; backgroundColor = .systemBackground
    }
    required init?(coder: NSCoder) { nil }
    func configure(_ input: GalaxySSIAtlasLabeledScroll) {
      let previous = self.input
      self.input = input
      let unchanged = previous.map { old in
        old.asset == input.asset && old.aspectRatio == input.aspectRatio && old.currentID == input.currentID &&
          old.labels == input.labels && old.spots.map({ $0.0 }) == input.spots.map({ $0.0 }) &&
          old.spots.map({ $0.1 }) == input.spots.map({ $0.1 }) && old.spots.map({ $0.2 }) == input.spots.map({ $0.2 })
      } ?? false
      if unchanged, fontCategory == traitCollection.preferredContentSizeCategory { return }
      fontCategory = traitCollection.preferredContentSizeCategory
      image.image = UIImage(named: input.asset)
      buttons.forEach { $0.removeFromSuperview() }; buttons = []
      for (index, spot) in input.spots.enumerated() {
        let button = UIButton(type: .system)
        button.setTitle(input.labels.indices.contains(index) ? input.labels[index] : spot.0, for: .normal)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.contentHorizontalAlignment = .leading
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        button.setTitleColor(.label, for: .normal); button.setTitleColor(.label, for: .disabled)
        button.isSelected = spot.0 == input.currentID; button.isEnabled = !button.isSelected
        if button.isSelected { button.accessibilityTraits.insert(.isSelected) }
        button.accessibilityIdentifier = "atlas-structure-label-" + spot.0
        button.addAction(UIAction { [weak self] _ in self?.input?.onSelect(spot.0) }, for: .touchUpInside)
        addSubview(button); buttons.append(button)
      }
      setNeedsLayout()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
      super.traitCollectionDidChange(previousTraitCollection)
      if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory, let input {
        configure(input); superview?.setNeedsLayout()
      }
      guides.setNeedsDisplay()
    }
    private func columnWidth(_ width: CGFloat) -> CGFloat {
      width * (traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 0.55 : 0.36)
    }
    private func labelHeight(_ button: UIButton, width: CGFloat) -> CGFloat {
      max(48, (button.titleLabel?.sizeThatFits(CGSize(width: max(1, width - 12), height: .greatestFiniteMagnitude)).height ?? 0) + 16)
    }
    func requiredHeight(width: CGFloat) -> CGFloat {
      let column = columnWidth(width)
      let labels = buttons.reduce(CGFloat(16)) { $0 + labelHeight($1, width: column) + 8 }
      return ceil(max(300, labels, (width - column - 12) / CGFloat(input?.aspectRatio ?? 1)))
    }
    override func layoutSubviews() {
      super.layoutSubviews()
      guard let input, bounds.width > 0 else { return }
      let column = columnWidth(bounds.width), available = CGRect(x: 0, y: 0, width: max(1, bounds.width - column - 12), height: bounds.height)
      let ratio = CGFloat(input.aspectRatio)
      let width = min(available.width, available.height * ratio), height = width / ratio
      imageRect = CGRect(x: available.midX - width / 2, y: available.midY - height / 2, width: width, height: height)
      image.frame = imageRect
      guides.frame = bounds
      let points = input.spots.map { CGPoint(x: imageRect.minX + imageRect.width * CGFloat($0.1), y: imageRect.minY + imageRect.height * CGFloat($0.2)) }
      var y: CGFloat = 8
      for index in buttons.indices {
        let height = labelHeight(buttons[index], width: column)
        buttons[index].frame = CGRect(x: bounds.width - column, y: y, width: column, height: height)
        y += height + 8
      }
      routes = points.enumerated().map { index, point in
        GalaxySSIHealthAtlasLeaderRoutes.route(start: point,
          end: CGPoint(x: buttons[index].frame.minX, y: buttons[index].frame.midY),
          obstacles: points.enumerated().filter { $0.offset != index }.map(\.element), clearance: 8)
      }
      guides.setNeedsDisplay()
    }
    private func drawGuides() {
      guard let input, let context = UIGraphicsGetCurrentContext() else { return }
      context.setStrokeColor(UIColor.label.cgColor); context.setLineWidth(1)
      for route in routes where route.count > 1 {
        context.addLines(between: route); context.strokePath()
      }
      context.setFillColor(GalaxySSIHealthTheme.accentUIColor.cgColor)
      for spot in input.spots {
        let point = CGPoint(x: imageRect.minX + imageRect.width * CGFloat(spot.1), y: imageRect.minY + imageRect.height * CGFloat(spot.2))
        let radius: CGFloat = spot.0 == input.currentID ? 5 : 3
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
      }
    }
    private final class Guides: UIView {
      weak var owner: Content?
      override func draw(_ rect: CGRect) { owner?.drawGuides() }
    }
  }
}
