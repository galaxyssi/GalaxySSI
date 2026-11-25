import SwiftUI

struct GalaxySSIHealthAtlasCellFunctionView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  @Environment(\.displayScale) private var displayScale
  @State private var measuredWidth: CGFloat = 360
  private var macrophage: Bool { story.id == "MACROPHAGE_CLEARANCE" }
  nonisolated static func height(width: CGFloat, displayScale: CGFloat, macrophage: Bool) -> CGFloat {
    guard width.isFinite, width > 0, displayScale.isFinite, displayScale > 0 else { return 0 }
    return min(floor(width * 0.56 * displayScale) / displayScale, macrophage ? 235 : 240)
  }
  var body: some View {
    Canvas { context, size in
      context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8),
        with: .color(Color(red: 234.0 / 255, green: 244.0 / 255, blue: 241.0 / 255)))
      let scale = min(size.width / 360, size.height / 200)
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 200 * scale) / 2)
      local.scaleBy(x: scale, y: scale)
      drawScene(in: local)
    }.frame(height: Self.height(width: measuredWidth, displayScale: displayScale, macrophage: macrophage))
      .background(GeometryReader { proxy in
        Color.clear.preference(key: GalaxySSIHealthAtlasCellFunctionWidth.self, value: proxy.size.width)
      })
      .onPreferenceChange(GalaxySSIHealthAtlasCellFunctionWidth.self) { width in
        if width.isFinite, width > 0, width != measuredWidth { measuredWidth = width }
      }
      .clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-cell-" + story.id.lowercased())
  }
  private func drawScene(in context: GraphicsContext) {
    guard story.chapters.count == 4, let owner = story.owners.first else { return }
    let position = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(phase)
    let titles = story.chapters.map(\.title)
    if macrophage, owner == GalaxySSIHealthAtlasPhagocytosis.owner,
      let frame = GalaxySSIHealthAtlasPhagocytosis.Frame(position) {
      GalaxySSIHealthAtlasPhagocytosis(phase: position, stages: titles, language: language)
        .drawScene(in: context, frame: frame)
    } else if let lesson = GalaxySSIHealthAtlasGranulocyte(rawValue: owner),
      let frame = GalaxySSIHealthAtlasGranulocyte.Frame(lesson, phase: position) {
      GalaxySSIHealthAtlasGranulocyteView(lesson: lesson, phase: position, stages: titles, language: language)
        .drawScene(in: context, frame: frame)
    } else if let lesson = GalaxySSIHealthAtlasImmuneLink(rawValue: owner),
      let frame = GalaxySSIHealthAtlasImmuneLink.Frame(lesson, phase: position) {
      GalaxySSIHealthAtlasImmuneLinkDrawing(lesson: lesson).drawScene(in: context, frame: frame)
    } else if let lesson = GalaxySSIHealthAtlasBloodDefense(rawValue: owner),
      let frame = GalaxySSIHealthAtlasBloodDefense.Frame(lesson, phase: position) {
      GalaxySSIHealthAtlasBloodDefenseDrawing(lesson: lesson).drawScene(in: context, frame: frame)
    }
  }
}

private struct GalaxySSIHealthAtlasCellFunctionWidth: PreferenceKey {
  static let defaultValue: CGFloat = 360
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
