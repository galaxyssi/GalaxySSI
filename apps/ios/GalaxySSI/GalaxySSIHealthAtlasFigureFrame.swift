import SwiftUI

enum GalaxySSIHealthAtlasFigureLayout {
  struct Columns: Equatable {
    let noteWidth: CGFloat
    let artWidth: CGFloat
    let edge: CGFloat
    let gutter: CGFloat
  }
  static func columns(width: CGFloat) -> Columns {
    let width = width.isFinite ? max(1, width) : 1
    let compact = width < 320
    let edge: CGFloat = compact ? 8 : 12, gutter: CGFloat = compact ? 8 : 16
    let noteWidth = min(width * 0.40, 328)
    return .init(noteWidth: noteWidth, artWidth: max(1, width - noteWidth - edge * 2 - gutter), edge: edge, gutter: gutter)
  }
  static func subject(in rect: CGRect, aspectRatio: Double, focus: CGPoint) -> CGPoint? {
    guard aspectRatio.isFinite, aspectRatio > 0, rect.width > 0, rect.height > 0,
      focus.x.isFinite, focus.y.isFinite else { return nil }
    let width = min(rect.width, rect.height * CGFloat(aspectRatio)), height = width / CGFloat(aspectRatio)
    return CGPoint(x: rect.midX - width / 2 + width * focus.x, y: rect.midY - height / 2 + height * focus.y)
  }
  static func leader(note: CGRect, art: CGRect, gutter: CGFloat, function: Bool, target: CGPoint?) -> [CGPoint] {
    guard art.width > 0, art.height > 0, note.width > 0, note.height > 0 else { return [] }
    let fallback = CGPoint(x: art.minX + art.width * (function ? 0.50 : 0.20), y: art.minY + art.height * 0.42)
    let point = target.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil } ?? fallback
    let end = CGPoint(x: min(art.maxX, max(art.minX, point.x)), y: min(art.maxY, max(art.minY, point.y)))
    let stem = note.maxX + gutter / 2
    return [CGPoint(x: note.maxX, y: note.midY), CGPoint(x: stem, y: note.midY), CGPoint(x: stem, y: end.y), end]
  }
}

struct GalaxySSIHealthAtlasFigureAnchors: PreferenceKey {
  static var defaultValue: [String: Anchor<CGRect>] = [:]
  static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

private struct GalaxySSIAtlasFigureSizes: PreferenceKey {
  static var defaultValue: [String: CGSize] = [:]
  static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

extension View {
  func atlasAnnotationTarget(_ scope: String, active: Bool = true) -> some View {
    anchorPreference(key: GalaxySSIHealthAtlasFigureAnchors.self, value: .bounds) { active ? [scope + ".target": $0] : [:] }
  }
  func atlasAnnotationSubject(_ scope: String) -> some View {
    anchorPreference(key: GalaxySSIHealthAtlasFigureAnchors.self, value: .bounds) { [scope + ".subject": $0] }
  }
}

struct GalaxySSIHealthAtlasFigureFrame<Header: View, Artwork: View, Legend: View>: View {
  let identifier: String
  let legendIdentifier: String
  let header: Header
  let artwork: Artwork
  let legend: Legend
  let function: Bool
  let subjectPoint: CGPoint?
  let subjectAspectRatio: Double?
  let subjectFocus: CGPoint?
  @Environment(\.colorScheme) private var colorScheme
  @State private var width: CGFloat = 320
  init(identifier: String, legendIdentifier: String = "atlas-figure-legend", function: Bool = false, subjectPoint: CGPoint? = nil,
       subjectAspectRatio: Double? = nil, subjectFocus: CGPoint? = nil,
       @ViewBuilder header: () -> Header,
       @ViewBuilder artwork: () -> Artwork, @ViewBuilder legend: () -> Legend) {
    self.identifier = identifier; self.legendIdentifier = legendIdentifier
    self.function = function
    self.subjectPoint = subjectPoint; self.subjectAspectRatio = subjectAspectRatio; self.subjectFocus = subjectFocus
    self.header = header(); self.artwork = artwork(); self.legend = legend()
  }
  var body: some View {
    let columns = GalaxySSIHealthAtlasFigureLayout.columns(width: width)
    VStack(spacing: 0) {
      header
      HStack(alignment: .center, spacing: columns.gutter) {
        note.frame(width: columns.noteWidth)
        drawing.frame(width: columns.artWidth)
      }.padding(columns.edge).frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity)
    .background(GalaxySSIHealthAtlasFilmPalette.color(GalaxySSIHealthAtlasFilmPalette.values(dark: colorScheme == .dark).ground))
    .overlayPreferenceValue(GalaxySSIHealthAtlasFigureAnchors.self) { anchors in
      GeometryReader { geometry in
        if let artAnchor = anchors[identifier + ".art"], let noteAnchor = anchors[identifier + ".note"] {
          let art = geometry[artAnchor], note = geometry[noteAnchor]
          let node = anchors[identifier + ".target"].map { geometry[$0] }
          let image = anchors[identifier + ".subject"].map { geometry[$0] }
          let normalized = subjectFocus ?? CGPoint(x: 0.36, y: 0.48)
          let imagePoint = image.flatMap { rect in subjectAspectRatio.flatMap { GalaxySSIHealthAtlasFigureLayout.subject(in: rect, aspectRatio: $0, focus: normalized) } }
          let viewport = anchors[identifier + ".viewport"].map { geometry[$0] } ?? art
          let native = subjectPoint.map { CGPoint(x: viewport.minX + $0.x, y: viewport.minY + $0.y) }
          let target = node.map { CGPoint(x: $0.minX, y: $0.midY) } ?? native ?? imagePoint
          leader(GalaxySSIHealthAtlasFigureLayout.leader(note: note, art: art, gutter: columns.gutter, function: function, target: target))
        }
      }.accessibilityHidden(true).allowsHitTesting(false)
    }
    .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityIdentifier(identifier)
    .background(measure("frame"))
    .onPreferenceChange(GalaxySSIAtlasFigureSizes.self) { values in
      if let size = values[identifier + ".frame"], size.width.isFinite, size.width > 0, width != size.width { width = size.width }
    }
  }
  private var drawing: some View {
    artwork.anchorPreference(key: GalaxySSIHealthAtlasFigureAnchors.self, value: .bounds) { [identifier + ".art": $0] }
  }
  private var note: some View {
    legend.frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 9)
      .background(Color(.secondarySystemGroupedBackground))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(GalaxySSIHealthTheme.accent, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityIdentifier(legendIdentifier)
      .anchorPreference(key: GalaxySSIHealthAtlasFigureAnchors.self, value: .bounds) { [identifier + ".note": $0] }
      .background(measure("legend"))
  }
  private func leader(_ points: [CGPoint]) -> some View {
    ZStack {
      Path { path in if let first = points.first { path.move(to: first); for point in points.dropFirst() { path.addLine(to: point) } } }
        .stroke(GalaxySSIHealthTheme.accent, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
      if let last = points.last { Circle().fill(GalaxySSIHealthTheme.accent).frame(width: 6, height: 6).position(last) }
    }
  }
  private func measure(_ key: String) -> some View {
    GeometryReader { geometry in Color.clear.preference(key: GalaxySSIAtlasFigureSizes.self, value: [identifier + "." + key: geometry.size]) }
      .allowsHitTesting(false).accessibilityHidden(true)
  }
}
