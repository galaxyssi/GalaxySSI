import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasLabeledArtwork: View {
  let asset: String
  let aspectRatio: Double
  @Binding var zoom: Double
  let currentID: String?
  let spots: [(String, Double, Double)]
  let labels: [String]
  var featureIDs: Set<String> = []
  var splitCallouts: Bool = false
  var minimumHeight: CGFloat = 300
  var subjectFocus = CGPoint(x: 0.54, y: 0.22)
  var onSubject: ((CGPoint) -> Void)? = nil
  var numbered = false
  var highlightedID: String? = nil
  var language = "en"
  let onSelect: (String) -> Void
  @State private var height: CGFloat = 360
  var body: some View {
    GalaxySSIAtlasLabeledScroll(asset: asset, aspectRatio: aspectRatio, zoom: $zoom, height: $height,
      currentID: currentID, spots: spots, labels: labels, featureIDs: featureIDs, splitCallouts: splitCallouts,
      minimumHeight: minimumHeight, subjectFocus: subjectFocus, onSubject: onSubject,
      numbered: numbered, highlightedID: highlightedID, language: language, onSelect: onSelect)
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
  let featureIDs: Set<String>
  let splitCallouts: Bool
  let minimumHeight: CGFloat
  let subjectFocus: CGPoint
  let onSubject: ((CGPoint) -> Void)?
  let numbered: Bool
  let highlightedID: String?
  let language: String
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
    private let notePosition = GalaxySSIHealthAtlasNotePosition()
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
      reportSubject(scroll)
    }
    private func reportSubject(_ scroll: UIScrollView) {
      guard parent.onSubject != nil else { return }
      let local = content.convert(content.subject(parent.subjectFocus), to: scroll)
      notePosition.report(CGPoint(x: local.x - scroll.bounds.minX, y: local.y - scroll.bounds.minY), identity: parent.asset) { [weak self] in
        self?.parent.onSubject?($0)
      }
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { reportSubject(scrollView) }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { reportSubject(scrollView) }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
      parent.zoom = Double(scale)
    }
  }
  final class Scroll: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?(self) }
    override func touchesShouldCancel(in view: UIView) -> Bool {
      view is UIButton || super.touchesShouldCancel(in: view)
    }
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
      image.isAccessibilityElement = false; backgroundColor = .clear
    }
    required init?(coder: NSCoder) { return nil }
    func configure(_ input: GalaxySSIAtlasLabeledScroll) {
      let previous = self.input
      self.input = input
      let unchanged = previous.map { old in
        old.asset == input.asset && old.aspectRatio == input.aspectRatio && old.currentID == input.currentID &&
          old.splitCallouts == input.splitCallouts && old.minimumHeight == input.minimumHeight &&
          old.numbered == input.numbered && old.language == input.language &&
          old.labels == input.labels && old.featureIDs == input.featureIDs && old.spots.map({ $0.0 }) == input.spots.map({ $0.0 }) &&
          old.spots.map({ $0.1 }) == input.spots.map({ $0.1 }) && old.spots.map({ $0.2 }) == input.spots.map({ $0.2 })
      } ?? false
      if unchanged, fontCategory == traitCollection.preferredContentSizeCategory { highlight(); return }
      fontCategory = traitCollection.preferredContentSizeCategory
      image.image = UIImage(named: input.asset)
      buttons.forEach { $0.removeFromSuperview() }; buttons = []
      let numbers = NumberFormatter()
      numbers.locale = Locale(identifier: input.language); numbers.numberStyle = .decimal; numbers.usesGroupingSeparator = false
      for (index, spot) in input.spots.enumerated() {
        let button = UIButton(type: .system)
        let feature = input.featureIDs.contains(spot.0)
        let current = !feature && spot.0 == input.currentID
        let name = input.labels.indices.contains(index) ? input.labels[index] : spot.0
        let title = input.numbered ? (numbers.string(from: NSNumber(value: index + 1)) ?? String(index + 1)) : name
        button.setTitle(title, for: .normal)
        button.titleLabel?.text = title
        button.accessibilityLabel = name
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.titleLabel?.font = input.numbered ?
          UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: current ? .semibold : .regular), compatibleWith: traitCollection) :
          .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        let split = !input.numbered && input.splitCallouts && input.spots.contains { $0.1 < 0.5 } && input.spots.contains { $0.1 >= 0.5 }
        let left = split && spot.1 < 0.5
        button.contentHorizontalAlignment = input.numbered ? .center : left ? .right : .left
        button.titleLabel?.textAlignment = input.numbered ? .center : left ? .right : .left
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: left ? 0 : 6, bottom: 8, right: split && !left ? 0 : 6)
        button.setTitleColor(.label, for: .normal); button.setTitleColor(.label, for: .disabled)
        button.setTitleColor(GalaxySSIHealthTheme.accentUIColor, for: [.selected, .disabled])
        button.isSelected = current; button.isEnabled = !button.isSelected
        if button.isSelected { button.accessibilityTraits.insert(.isSelected) }
        button.accessibilityIdentifier = (feature ? "atlas-feature-" : "atlas-structure-label-") + spot.0
        button.addAction(UIAction { [weak self] _ in self?.input?.onSelect(spot.0) }, for: .touchUpInside)
        addSubview(button); buttons.append(button)
      }
      accessibilityElements = input.numbered ? buttons : input.spots.indices.sorted {
        input.spots[$0].2 == input.spots[$1].2 ? input.spots[$0].1 < input.spots[$1].1 : input.spots[$0].2 < input.spots[$1].2
      }.map { buttons[$0] }
      highlight()
      setNeedsLayout()
    }
    private func highlight() {
      guard let input else { return }
      for (index, button) in buttons.enumerated() where input.spots.indices.contains(index) {
        let highlighted = input.spots[index].0 == input.highlightedID
        button.alpha = !input.numbered || input.highlightedID == nil || highlighted ? 1 : 0.55
        let color = highlighted || button.isSelected ? GalaxySSIHealthTheme.accentUIColor : UIColor.label
        button.setTitleColor(color, for: .normal); button.setTitleColor(color, for: .disabled)
      }
      guides.setNeedsDisplay()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
      super.traitCollectionDidChange(previousTraitCollection)
      if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory, let input {
        configure(input); superview?.setNeedsLayout()
      }
      guides.setNeedsDisplay()
    }
    private func labelHeight(_ button: UIButton, width: CGFloat) -> CGFloat {
      let insets = button.contentEdgeInsets
      return max(48, (button.titleLabel?.sizeThatFits(CGSize(width: max(1, width - insets.left - insets.right),
        height: .greatestFiniteMagnitude)).height ?? 0) + insets.top + insets.bottom)
    }
    private func plan(width: CGFloat) -> GalaxySSIHealthAtlasCalloutLayout? {
      guard let input, buttons.count == input.spots.count else { return nil }
      let preferred = buttons.map { button -> CGFloat in
        let font = button.titleLabel?.font ?? UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        let title = (button.title(for: .normal) ?? "") as NSString
        return title.size(withAttributes: [.font: font]).width +
          button.contentEdgeInsets.left + button.contentEdgeInsets.right
      }
      return GalaxySSIHealthAtlasCalloutLayout.make(width: width, aspectRatio: input.aspectRatio,
        anchors: input.spots.map { CGPoint(x: $0.1, y: $0.2) }, splitRequested: input.splitCallouts,
        accessibility: traitCollection.preferredContentSizeCategory.isAccessibilityCategory,
        preferredWidths: preferred, minimumHeight: input.minimumHeight, numbered: input.numbered,
        measureHeight: { self.labelHeight(self.buttons[$0], width: $1) })
    }
    func requiredHeight(width: CGFloat) -> CGFloat { plan(width: width)?.height ?? 300 }
    func subject(_ focus: CGPoint) -> CGPoint {
      CGPoint(x: imageRect.minX + imageRect.width * focus.x, y: imageRect.minY + imageRect.height * focus.y)
    }
    override func layoutSubviews() {
      super.layoutSubviews()
      guard let input, let plan = plan(width: bounds.width) else { return }
      imageRect = plan.imageRect
      image.frame = imageRect; guides.frame = bounds
      let points = input.spots.map { CGPoint(x: imageRect.minX + imageRect.width * CGFloat($0.1),
        y: imageRect.minY + imageRect.height * CGFloat($0.2)) }
      for index in buttons.indices { buttons[index].frame = plan.labelFrames[index] }
      let left = Set(plan.left)
      routes = points.enumerated().map { index, point in
        let frame = buttons[index].frame, onLeft = left.contains(index)
        return GalaxySSIHealthAtlasLeaderRoutes.route(start: point,
          end: CGPoint(x: onLeft ? frame.maxX : frame.minX, y: frame.midY),
          obstacles: points.enumerated().filter { $0.offset != index }.map(\.element), clearance: 8,
          minX: plan.split && !onLeft ? imageRect.midX : -.infinity,
          maxX: plan.split && onLeft ? imageRect.midX : .infinity)
      }
      guides.setNeedsDisplay()
    }
    private func drawGuides() {
      guard let input, let context = UIGraphicsGetCurrentContext() else { return }
      context.setStrokeColor((input.numbered ? UIColor.secondaryLabel.withAlphaComponent(112.0 / 255) : UIColor.label).cgColor)
      context.setLineWidth(1)
      for route in routes where route.count > 1 {
        context.addLines(between: route); context.strokePath()
      }
      for spot in input.spots {
        let point = CGPoint(x: imageRect.minX + imageRect.width * CGFloat(spot.1), y: imageRect.minY + imageRect.height * CGFloat(spot.2))
        let active = spot.0 == input.currentID || spot.0 == input.highlightedID
        let radius: CGFloat = active ? 5 : 3
        context.setFillColor(GalaxySSIHealthTheme.accentUIColor.withAlphaComponent(input.numbered && !active ? 128.0 / 255 : 1).cgColor)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
      }
    }
    private final class Guides: UIView {
      weak var owner: Content?
      override func draw(_ rect: CGRect) { owner?.drawGuides() }
    }
  }
}
