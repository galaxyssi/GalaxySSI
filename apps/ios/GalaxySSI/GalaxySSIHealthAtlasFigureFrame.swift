import SwiftUI

enum GalaxySSIHealthAtlasFigureLayout {
  static let overlap: CGFloat = 28
  static func sharedHeight(art: CGFloat, legend: CGFloat) -> CGFloat {
    guard art.isFinite, legend.isFinite else { return 0 }
    return max(0, min(overlap, min(art, legend)))
  }
}

private struct GalaxySSIAtlasFigureHeights: PreferenceKey {
  static var defaultValue: [String: CGFloat] = [:]
  static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

struct GalaxySSIHealthAtlasFigureFrame<Header: View, Artwork: View, Legend: View>: View {
  let identifier: String
  let legendIdentifier: String
  let header: Header
  let artwork: Artwork
  let legend: Legend
  @Environment(\.colorScheme) private var colorScheme
  @State private var artHeight: CGFloat = 28
  @State private var legendHeight: CGFloat = 28
  init(identifier: String, legendIdentifier: String = "atlas-figure-legend", @ViewBuilder header: () -> Header,
       @ViewBuilder artwork: () -> Artwork, @ViewBuilder legend: () -> Legend) {
    self.identifier = identifier; self.legendIdentifier = legendIdentifier
    self.header = header(); self.artwork = artwork(); self.legend = legend()
  }
  var body: some View {
    let ground = GalaxySSIHealthAtlasFilmPalette.color(GalaxySSIHealthAtlasFilmPalette.values(dark: colorScheme == .dark).ground)
    VStack(spacing: 0) {
      header
      artwork.frame(maxWidth: .infinity).background(measure("art"))
      legend.frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 14)
        .background {
          VStack(spacing: 0) {
            LinearGradient(colors: [ground.opacity(0), ground], startPoint: .top, endPoint: .bottom).frame(height: 18)
            ground
          }.allowsHitTesting(false)
        }.accessibilityIdentifier(legendIdentifier).background(measure("legend"))
        .padding(.top, -GalaxySSIHealthAtlasFigureLayout.sharedHeight(art: artHeight, legend: legendHeight))
    }.background(ground).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityIdentifier(identifier)
      .onPreferenceChange(GalaxySSIAtlasFigureHeights.self) { values in
        if let height = values["art"], height.isFinite, height >= 0, height != artHeight { artHeight = height }
        if let height = values["legend"], height.isFinite, height >= 0, height != legendHeight { legendHeight = height }
      }
  }
  private func measure(_ key: String) -> some View {
    GeometryReader { geometry in Color.clear.preference(key: GalaxySSIAtlasFigureHeights.self, value: [key: geometry.size.height]) }
      .allowsHitTesting(false).accessibilityHidden(true)
  }
}
