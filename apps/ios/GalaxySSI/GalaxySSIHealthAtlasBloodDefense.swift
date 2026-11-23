import Foundation

enum GalaxySSIHealthAtlasBloodDefense: String, CaseIterable {
  case tCell = "cell-t-cell", bCell = "cell-b-cell", naturalKiller = "cell-natural-killer-cell"
  case megakaryocyte = "cell-megakaryocyte", platelet = "fragment-platelet"
  var asset: String {
    switch self {
    case .tCell: return "HealthAtlasImmuneTCell"
    case .bCell: return "HealthAtlasImmuneBCell"
    case .naturalKiller: return "HealthAtlasImmuneNaturalKiller"
    case .megakaryocyte: return "HealthAtlasImmuneMegakaryocyte"
    case .platelet: return "HealthAtlasImmunePlatelet"
    }
  }
  var scopeKey: String {
    switch self {
    case .tCell: return "t_lesson_scope"
    case .bCell: return "b_lesson_scope"
    case .naturalKiller: return "nk_lesson_scope"
    case .megakaryocyte: return "mega_lesson_scope"
    case .platelet: return "platelet_lesson_scope"
    }
  }
  var relatedID: String? {
    switch self {
    case .tCell: return "cell-dendritic-cell"
    case .bCell: return "cell-plasma-cell"
    case .megakaryocyte: return "fragment-platelet"
    case .platelet: return "cell-megakaryocyte"
    case .naturalKiller: return nil
    }
  }
  var relatedAsset: String? {
    switch self {
    case .tCell: return "HealthAtlasImmuneDendritic"
    case .bCell: return "HealthAtlasImmunePlasma"
    case .megakaryocyte: return "HealthAtlasImmunePlatelet"
    case .naturalKiller, .platelet: return nil
    }
  }
  struct Placement: Equatable {
    let x: Double, y: Double, size: Double
  }
  struct Frame: Equatable {
    let lesson: GalaxySSIHealthAtlasBloodDefense
    let scene: GalaxySSIHealthAtlasCellScene.Frame
    var stage: Int { scene.stage }
    var ease: Double { scene.ease }
    init?(_ lesson: GalaxySSIHealthAtlasBloodDefense, phase: Double) {
      guard let scene = GalaxySSIHealthAtlasCellScene.Frame(phase) else { return nil }
      self.lesson = lesson; self.scene = scene
    }
    var primary: Placement {
      switch lesson {
      case .tCell, .bCell:
        switch stage {
        case 0: return .init(x: 94, y: 102, size: 163)
        case 1: return .init(x: 94, y: 102, size: 162)
        case 2: return .init(x: 180, y: 106, size: 125)
        default: return .init(x: 79, y: 103, size: 138)
        }
      case .naturalKiller:
        return .init(x: stage == 0 ? 83 + 26 * ease : 109, y: 103, size: 191)
      case .megakaryocyte:
        let size = stage == 0 ? 112 + 34 * ease : stage == 1 ? 146 + 74 * ease : 220
        let x = stage == 2 ? 137 + 20 * ease : stage == 3 ? 157 : 137
        return .init(x: x, y: 102, size: size)
      case .platelet:
        return .init(x: 181, y: stage == 0 ? 75 + ease * 48 : 135, size: stage == 0 ? 101 : (15 + 3 * ease) * 3.75)
      }
    }
    var clones: [Placement] {
      guard [.tCell, .bCell].contains(lesson), stage == 2 else { return [] }
      return [-1.0, 1.0].map { .init(x: 180 + $0 * (65 + 29 * ease), y: 104 - 22 * ease, size: 85 + 25 * ease) }
    }
    var targetRadius: Double { stage == 3 ? 48 - ease * 16 : 48 }
    var releasedPlatelets: [Placement] {
      guard lesson == .megakaryocyte, stage == 3 else { return [] }
      return [-1.0, 0, 1].map { .init(x: 236 + (42 + $0 * 7) * ease, y: 104 + $0 * (8 + 35 * ease), size: 42) }
    }
    var plateletNeighbors: [Placement] {
      guard lesson == .platelet, stage > 0 else { return [] }
      return [-1.0, 1].map { .init(x: stage == 1 ? 181 + $0 * (100 - 65 * ease) : 181 + $0 * (35 - 12 * ease),
        y: stage == 1 ? 65 + ease * 62 : 128 + $0 * 5, size: 13 * 3.75) }
    }
  }
}
