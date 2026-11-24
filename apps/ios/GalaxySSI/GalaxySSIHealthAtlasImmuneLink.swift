import SwiftUI

enum GalaxySSIHealthAtlasImmuneLink: String, CaseIterable {
  case monocyte = "cell-monocyte", dendritic = "cell-dendritic-cell", plasma = "cell-plasma-cell"
  var asset: String {
    switch self {
    case .monocyte: return "HealthAtlasImmuneMonocyte"
    case .dendritic: return "HealthAtlasImmuneDendritic"
    case .plasma: return "HealthAtlasImmunePlasma"
    }
  }
  var relatedID: String {
    switch self {
    case .monocyte: return "cell-macrophage"
    case .dendritic: return "cell-t-cell"
    case .plasma: return "cell-b-cell"
    }
  }
  var relatedAsset: String {
    switch self {
    case .monocyte: return "HealthAtlasImmuneMacrophage"
    case .dendritic: return "HealthAtlasImmuneTCell"
    case .plasma: return "HealthAtlasImmuneBCell"
    }
  }
  var scopeKey: String {
    switch self {
    case .monocyte: return "monocyte_lesson_scope"
    case .dendritic: return "dendritic_lesson_scope"
    case .plasma: return "plasma_lesson_scope"
    }
  }
  struct Placement: Equatable {
    let x: Double, y: Double, size: Double
    var widthRatio: Double = 1
  }
  struct Frame: Equatable {
    let lesson: GalaxySSIHealthAtlasImmuneLink
    let scene: GalaxySSIHealthAtlasCellScene.Frame
    var stage: Int { scene.stage }
    var ease: Double { scene.ease }
    init?(_ lesson: GalaxySSIHealthAtlasImmuneLink, phase: Double) {
      guard let scene = GalaxySSIHealthAtlasCellScene.Frame(phase) else { return nil }
      self.lesson = lesson; self.scene = scene
    }
    var primary: Placement {
      switch lesson {
      case .monocyte:
        if stage == 3 { return .init(x: 91, y: 101, size: 155) }
        return .init(x: stage == 0 ? 64 + 85 * ease : stage == 1 ? 149 + 94 * ease : 243,
          y: stage < 2 ? 55 : 55 + 89 * ease, size: 103, widthRatio: stage == 2 ? 1 - 1.1 * ease * (1 - ease) : 1)
      case .dendritic:
        return stage < 2 ? .init(x: 166, y: 103, size: 202) : .init(x: 113, y: 108, size: 170)
      case .plasma:
        return stage == 0 ? .init(x: 272, y: 101, size: 164) : .init(x: 119, y: 101, size: 202)
      }
    }
    var related: Placement? {
      switch lesson {
      case .monocyte: return stage == 3 ? .init(x: 269, y: 101, size: 183) : nil
      case .dendritic: return stage >= 2 ? .init(x: 254 - 20 * ease, y: 100, size: 177) : nil
      case .plasma: return stage == 0 ? .init(x: 89, y: 101, size: 168) : nil
      }
    }
    func arrowHead(from: Double, to: Double) -> Double { from + (to - from) * (0.25 + 0.75 * ease) }
  }
}

struct GalaxySSIHealthAtlasImmuneLinkView: View {
  let atlas: GalaxySSIHealthAtlas
  let lesson: GalaxySSIHealthAtlasImmuneLink
  let phase: Double
  let stages: [String]
  let language: String
  let open: (String) -> Void
  var showsDetails = true
  var body: some View {
    if let frame = GalaxySSIHealthAtlasImmuneLink.Frame(lesson, phase: phase) {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSIHealthAtlasCellScene(frame: frame.scene, stages: stages, language: language, identifier: "atlas-immune-link-diagram") { drawing in
          GalaxySSIHealthAtlasImmuneLinkDrawing(lesson: lesson).drawScene(in: drawing, frame: frame)
        }
        if showsDetails {
          Text(GalaxySSIHealthAtlasText.get("health_atlas_" + lesson.scopeKey, language)).font(.footnote).foregroundColor(.secondary)
          GalaxySSIHealthAtlasCellSceneRelatedRow(atlas: atlas, entryID: lesson.relatedID, language: language, open: open)
        }
      }
    }
  }
}
