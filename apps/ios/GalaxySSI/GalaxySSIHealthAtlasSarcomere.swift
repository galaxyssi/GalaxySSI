import Foundation

/// Relative drawing units, not patient measurements or a normal range.
struct GalaxySSIHealthAtlasSarcomere: Equatable {
  static let owner = "cell-skeletal-myocyte"
  let stage: Int
  init?(stage: Int) {
    guard (0..<4).contains(stage) else { return nil }
    self.stage = stage
  }
  var zDistance: Int { stage == 2 ? 180 : 250 }
  var relativeLengthPercent: Int { zDistance * 100 / 250 }
  let thinLength = 86
  let thickLength = 136
  var leftZ: Int { (360 - zDistance) / 2 }
  var rightZ: Int { leftZ + zDistance }
  var leftThick: Int { (360 - thickLength) / 2 }
  var rightThick: Int { leftThick + thickLength }
  var overlap: Int { leftZ + thinLength - leftThick }
  func context(text t: (String) -> String) -> [String] {
    [String(format: t("sarcomere_ratio"), Int64(relativeLengthPercent)), t("sarcomere_scope")]
  }
}
