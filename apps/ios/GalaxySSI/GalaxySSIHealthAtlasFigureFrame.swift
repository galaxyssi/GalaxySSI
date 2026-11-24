import SwiftUI

enum GalaxySSIHealthAtlasFigureLayout {
  struct Columns: Equatable {
    let side: Bool
    let noteWidth: CGFloat
    let artWidth: CGFloat
  }
  static func columns(width: CGFloat, preferSide: Bool, overlay: Bool, maximumHeight: CGFloat? = nil,
                      headerHeight: CGFloat = 0, legendHeight: CGFloat = 0) -> Columns {
    let width = width.isFinite ? max(1, width) : 1
    var side = width >= 580 || (preferSide && width >= 280)
    var fraction: CGFloat = side ? 0.40 : (overlay ? 0.72 : 0.83)
    if let maximumHeight, maximumHeight.isFinite, !side,
      maximumHeight - headerHeight - legendHeight < 160 {
      side = true; fraction = 0.44
    }
    let noteWidth = side ? min(width * fraction, 328) : max(1, min(width * fraction, width - 24))
    return .init(side: side, noteWidth: noteWidth, artWidth: max(1, side ? width - noteWidth - 40 : width - 24))
  }
  static func overlap(legend: CGFloat, overlay: Bool, side: Bool) -> CGFloat {
    guard overlay, !side, legend.isFinite else { return 0 }
    return max(0, min(46, legend / 2))
  }
  static func subject(in rect: CGRect, aspectRatio: Double, focus: CGPoint) -> CGPoint? {
    guard aspectRatio.isFinite, aspectRatio > 0, rect.width > 0, rect.height > 0,
      focus.x.isFinite, focus.y.isFinite else { return nil }
    let width = min(rect.width, rect.height * CGFloat(aspectRatio)), height = width / CGFloat(aspectRatio)
    return CGPoint(x: rect.midX - width / 2 + width * focus.x, y: rect.midY - height / 2 + height * focus.y)
  }
  static func leader(note: CGRect, art: CGRect, side: Bool, target: CGPoint?) -> [CGPoint] {
    guard art.width > 0, art.height > 0, note.width > 0, note.height > 0 else { return [] }
    let fallback = CGPoint(x: art.minX + art.width * (side ? 0.20 : 0.70),
      y: side ? art.minY + art.height * 0.42 : max(note.maxY + 16, art.minY + art.height * 0.08))
    let point = target.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil } ?? fallback
    let end = CGPoint(x: min(art.maxX, max(art.minX, point.x)), y: min(art.maxY, max(art.minY, point.y)))
    if side {
      let stem = note.maxX + 8
      return [CGPoint(x: note.maxX, y: note.midY), CGPoint(x: stem, y: note.midY), CGPoint(x: stem, y: end.y), end]
    }
    let x = note.minX + note.width * 0.78, stem = note.maxY + 8
    return [CGPoint(x: x, y: note.maxY), CGPoint(x: x, y: stem), CGPoint(x: end.x, y: stem), end]
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
  let overlayNote: Bool
  let preferSideNote: Bool
  let maximumHeight: CGFloat?
  let subjectPoint: CGPoint?
  let subjectAspectRatio: Double?
  let subjectFocus: CGPoint?
  let onSideChanged: (Bool) -> Void
  @Environment(\.colorScheme) private var colorScheme
  @State private var width: CGFloat = 320
  @State private var legendHeight: CGFloat = 0
  @State private var headerHeight: CGFloat = 0
  init(identifier: String, legendIdentifier: String = "atlas-figure-legend", overlayNote: Bool = false,
       preferSideNote: Bool = false, maximumHeight: CGFloat? = nil, subjectPoint: CGPoint? = nil,
       subjectAspectRatio: Double? = nil, subjectFocus: CGPoint? = nil, onSideChanged: @escaping (Bool) -> Void = { _ in },
       @ViewBuilder header: () -> Header,
       @ViewBuilder artwork: () -> Artwork, @ViewBuilder legend: () -> Legend) {
    self.identifier = identifier; self.legendIdentifier = legendIdentifier
    self.overlayNote = overlayNote; self.preferSideNote = preferSideNote; self.maximumHeight = maximumHeight
    self.subjectPoint = subjectPoint; self.subjectAspectRatio = subjectAspectRatio; self.subjectFocus = subjectFocus
    self.onSideChanged = onSideChanged
    self.header = header(); self.artwork = artwork(); self.legend = legend()
  }
  var body: some View {
    let columns = GalaxySSIHealthAtlasFigureLayout.columns(width: width, preferSide: preferSideNote, overlay: overlayNote,
      maximumHeight: maximumHeight, headerHeight: headerHeight, legendHeight: legendHeight)
    VStack(spacing: 0) {
      header.background(measure("header"))
      Group {
        if columns.side {
          HStack(alignment: .center, spacing: 16) {
            note.frame(width: columns.noteWidth).zIndex(1)
            drawing.frame(width: columns.artWidth)
          }
        } else {
          VStack(alignment: .leading, spacing: 0) {
            note.frame(width: columns.noteWidth).zIndex(1)
            drawing.frame(width: columns.artWidth)
              .padding(.top, 16 - GalaxySSIHealthAtlasFigureLayout.overlap(legend: legendHeight, overlay: overlayNote, side: false))
          }
        }
      }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity)
    .background(GalaxySSIHealthAtlasFilmPalette.color(GalaxySSIHealthAtlasFilmPalette.values(dark: colorScheme == .dark).ground))
    .overlayPreferenceValue(GalaxySSIHealthAtlasFigureAnchors.self) { anchors in
      GeometryReader { geometry in
        if let artAnchor = anchors[identifier + ".art"], let noteAnchor = anchors[identifier + ".note"] {
          let art = geometry[artAnchor], note = geometry[noteAnchor]
          let node = anchors[identifier + ".target"].map { geometry[$0] }
          let image = anchors[identifier + ".subject"].map { geometry[$0] }
          let normalized = subjectFocus ?? CGPoint(x: columns.side ? 0.36 : 0.54, y: columns.side ? 0.48 : 0.22)
          let imagePoint = image.flatMap { rect in subjectAspectRatio.flatMap { GalaxySSIHealthAtlasFigureLayout.subject(in: rect, aspectRatio: $0, focus: normalized) } }
          let viewport = anchors[identifier + ".viewport"].map { geometry[$0] } ?? art
          let native = subjectPoint.map { CGPoint(x: viewport.minX + $0.x, y: viewport.minY + $0.y) }
          let target = node.map { CGPoint(x: $0.midX, y: $0.minY) } ?? native ?? imagePoint
          leader(GalaxySSIHealthAtlasFigureLayout.leader(note: note, art: art, side: columns.side, target: target))
        }
      }.accessibilityHidden(true).allowsHitTesting(false)
    }
    .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityIdentifier(identifier)
    .background(measure("frame"))
    .onAppear { onSideChanged(columns.side) }
    .onChange(of: columns.side) { onSideChanged($0) }
    .onPreferenceChange(GalaxySSIAtlasFigureSizes.self) { values in
      if let size = values[identifier + ".frame"], size.width.isFinite, size.width > 0, width != size.width { width = size.width }
      if let size = values[identifier + ".legend"], size.height.isFinite, legendHeight != size.height { legendHeight = size.height }
      if let size = values[identifier + ".header"], size.height.isFinite, headerHeight != size.height { headerHeight = size.height }
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
