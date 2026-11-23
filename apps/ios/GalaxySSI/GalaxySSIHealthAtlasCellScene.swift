import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasCellScene: View {
  struct Frame: Equatable {
    let stage: Int
    let ease: Double
    init?(_ phase: Double) {
      guard let value = GalaxySSIHealthAtlasSectionLesson.Phase(phase) else { return nil }
      stage = value.stage
      let progress = value.fraction
      ease = progress * progress * (3 - 2 * progress)
    }
  }
  let frame: Frame
  let stages: [String]
  let language: String
  let identifier: String
  let draw: (GraphicsContext) -> Void
  nonisolated static func label(stage: Int, stages: [String], language: String) -> String? {
    guard stages.count == 4, stages.indices.contains(stage) else { return nil }
    return String(format: GalaxySSIHealthAtlasText.get("health_atlas_granulocyte_stage", language),
      GalaxySSIHealthAtlasText.get(stages[stage], language))
  }
  var body: some View {
    if let label = Self.label(stage: frame.stage, stages: stages, language: language) {
      Canvas { context, size in
        var drawing = context
        let scale = min(size.width / 360, size.height / 200)
        drawing.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 200 * scale) / 2)
        drawing.scaleBy(x: scale, y: scale)
        draw(drawing)
      }.aspectRatio(360.0 / 200, contentMode: .fit).frame(maxHeight: 240).clipped()
        .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
  }
  nonisolated static func portraitBounds(x: Double, y: Double, size: Double, widthRatio: Double = 1, aspectRatio: Double) -> CGRect? {
    guard [x, y, size, widthRatio, aspectRatio].allSatisfy(\.isFinite), size > 0, widthRatio > 0, aspectRatio > 0 else { return nil }
    // Match Android's centered, integer 200-unit drawable bounds before scene scaling.
    let dx = floor(100 * min(1, aspectRatio)), dy = floor(100 * min(1, 1 / aspectRatio))
    guard dx > 0, dy > 0 else { return nil }
    let width = dx * size * widthRatio / 100, height = dy * size / 100
    return CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
  }
  static func portrait(in context: GraphicsContext, asset: String, x: Double, y: Double, size: Double, widthRatio: Double = 1) {
    guard let image = UIImage(named: asset), image.size.height > 0,
      let bounds = portraitBounds(x: x, y: y, size: size, widthRatio: widthRatio, aspectRatio: Double(image.size.width / image.size.height))
    else { return }
    context.draw(Image(asset), in: bounds)
  }
}

struct GalaxySSIHealthAtlasCellSceneRelatedRow: View {
  let atlas: GalaxySSIHealthAtlas
  let entryID: String
  let language: String
  let open: (String) -> Void
  var body: some View {
    if let related = atlas.entry(entryID) {
      Button { open(related.id) } label: {
        HStack(spacing: 10) {
          if let plate = atlas.plate(for: related.id) {
            Image(plate.asset).resizable().scaledToFit().frame(width: 64, height: 52).accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: 4) {
            Text(GalaxySSIHealthAtlasText.get(related.name, language)).font(.headline)
            Text(GalaxySSIHealthAtlasText.get(related.description, language)).font(.subheadline).foregroundColor(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
          Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary).accessibilityHidden(true)
        }.frame(minHeight: 52).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("atlas-immune-related-" + related.id)
    }
  }
}
