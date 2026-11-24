import Foundation

enum GalaxySSIHealthAtlasToothAnatomyData {
  enum Kind: Int { case incisor, canine, premolar, molar }
  struct ArchTooth {
    let kind: Kind; let x: Double; let y: Double; let w: Double; let h: Double; let angle: Double
  }
  struct ProfileTooth {
    let kind: Kind; let x: Double; let y: Double; let w: Double; let h: Double
  }
  static let halfArch: [ArchTooth] = [
    .init(kind: .incisor, x: 165, y: 84, w: 28, h: 25, angle: -6),
    .init(kind: .incisor, x: 137, y: 93, w: 25, h: 25, angle: -30),
    .init(kind: .canine, x: 117, y: 116, w: 28, h: 26, angle: -52),
    .init(kind: .premolar, x: 106, y: 146, w: 27, h: 27, angle: -73),
    .init(kind: .premolar, x: 102, y: 176, w: 28, h: 29, angle: -88),
    .init(kind: .molar, x: 102, y: 210, w: 33, h: 36, angle: -90),
    .init(kind: .molar, x: 105, y: 247, w: 34, h: 36, angle: -97),
  ]
  static let profile: [ProfileTooth] = [
    .init(kind: .incisor, x: 75, y: 147, w: 19, h: 32),
    .init(kind: .incisor, x: 96, y: 150, w: 19, h: 29),
    .init(kind: .canine, x: 124, y: 151, w: 28, h: 34),
    .init(kind: .premolar, x: 156, y: 152, w: 29, h: 29),
    .init(kind: .premolar, x: 188, y: 152, w: 30, h: 29),
    .init(kind: .molar, x: 227, y: 151, w: 42, h: 29),
    .init(kind: .molar, x: 273, y: 149, w: 44, h: 29),
  ]
  static let frontMolarCenters = [84.0, 276]
  static let crumbs: [(x: Double, y: Double)] = [
    (x: -19, y: 1),
    (x: -10, y: -5),
    (x: -3, y: 4),
    (x: 6, y: -6),
    (x: 13, y: 3),
    (x: 21, y: -1),
  ]
}
