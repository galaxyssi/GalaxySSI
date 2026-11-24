import Foundation

// Feature titles/normalized positions evaluated from the original Android plate declarations.
enum GalaxySSIHealthAtlasVulvarFeatures {
  struct Feature { let key: String; let x: Double; let y: Double }
  static let region: [Feature] = [
    .init(key: "vulvar_protection_outer_boundary", x: 0.2916666567325592, y: 0.27142858505249023),
    .init(key: "vulvar_protection_outer_folds", x: 0.36944442987442017, y: 0.44999998807907104),
    .init(key: "vulvar_protection_inner_folds", x: 0.5722222328186035, y: 0.42500001192092896),
    .init(key: "vulvar_protection_vestibule", x: 0.5, y: 0.5428571701049805),
  ]
  static let outer: [Feature] = [
    .init(key: "vulvar_protection_skin_surface", x: 0.31388887763023376, y: 0.2857142984867096),
    .init(key: "vulvar_protection_fatty_cushion", x: 0.2805555462837219, y: 0.5392857193946838),
    .init(key: "vulvar_protection_vestibule_floor", x: 0.5, y: 0.6785714030265808),
  ]
  static let inner: [Feature] = [
    .init(key: "vulvar_protection_inner_folds", x: 0.375, y: 0.4571428596973419),
    .init(key: "vulvar_protection_inner_margin", x: 0.5805555582046509, y: 0.4714285731315613),
    .init(key: "vulvar_protection_vestibule", x: 0.5027777552604675, y: 0.5464285612106323),
  ]
}
