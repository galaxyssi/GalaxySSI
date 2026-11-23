import Foundation

struct GalaxySSIHealthAtlasEndocrinePath: Decodable {
  struct Step: Decodable {
    let label: String
    let destination: String?
  }
  let scope: String
  let separateBranches: Bool
  let steps: [Step]
  func step(_ stage: Int) -> Step? { steps.indices.contains(stage) ? steps[stage] : nil }
  func row(_ branch: Int) -> [Int]? {
    guard (0...1).contains(branch), steps.count == 4 else { return nil }
    return branch == 0 ? [0, 1] : separateBranches ? [2, 3] : [3, 2]
  }
  static func forEntry(_ id: String) -> Self? {
    guard let pack = try? GalaxySSIHealthAtlas.EndocrinePack.bundled.get() else { return nil }
    return pack.paths[id]
  }
  static func context(_ id: String, language: String) -> String? {
    forEntry(id).map { GalaxySSIHealthAtlasText.get($0.scope, language) }
  }
}
