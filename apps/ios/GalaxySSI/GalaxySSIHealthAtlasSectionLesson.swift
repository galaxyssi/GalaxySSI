import Foundation

struct GalaxySSIHealthAtlasSectionLesson {
  struct Point: Decodable, Equatable {
    let x: Double
    let y: Double
    var valid: Bool { x.isFinite && y.isFinite && (0...360).contains(x) && (0...280).contains(y) }
  }
  struct Command: Decodable {
    enum Kind: String, Decodable { case line, quad, cubic }
    let kind: Kind
    let points: [Point]
    var valid: Bool { points.count == (kind == .line ? 1 : kind == .quad ? 2 : 3) && points.allSatisfy(\.valid) }
  }
  struct Route: Decodable {
    let start: Point
    let commands: [Command]
    var valid: Bool { start.valid && (1...4).contains(commands.count) && commands.allSatisfy(\.valid) }
  }
  struct Phase: Equatable {
    let value: Double
    init?(_ value: Double) {
      guard value.isFinite else { return nil }
      self.value = min(1, max(0, value))
    }
    var stage: Int { min(3, Int(value * 4)) }
    var fraction: Double { min(1, max(0, value * 4 - Double(stage))) }
    func radius(hasRoute: Bool) -> Double { hasRoute ? 12 : 14 + 4 * fraction }
  }
  static let source = URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-1-anatomy-of-the-lymphatic-and-immune-systems")!
  let plate: GalaxySSIHealthAtlas.Plate
  let stageFeatures: [Int]
  let routes: [Route]
  var notes: [String] = []
  func feature(stage: Int) -> GalaxySSIHealthAtlas.Feature? {
    guard stageFeatures.indices.contains(stage), plate.annotations.indices.contains(stageFeatures[stage]) else { return nil }
    return plate.annotations[stageFeatures[stage]]
  }
  func route(stage: Int) -> Route? { routes.indices.contains(stage) ? routes[stage] : nil }
  static func forEntry(_ id: String) -> Self? {
    if let pack = try? GalaxySSIHealthAtlas.GutPack.bundled.get(),
      let plate = pack.plates.first(where: { $0.owner == id }), let stages = pack.stageFeatures[id] {
      return Self(plate: plate, stageFeatures: stages, routes: pack.routes[id] ?? [], notes: pack.notes[id] ?? [])
    }
    guard let pack = try? GalaxySSIHealthAtlas.LymphPack.bundled.get(),
      let plate = pack.plates.first(where: { $0.owner == id }), let stages = pack.stageFeatures[id] else { return nil }
    return Self(plate: plate, stageFeatures: stages, routes: pack.routes[id] ?? [],
      notes: ["health_atlas_lymph_illustration_scope"] + (id == "thoracic-duct" ? ["health_atlas_lymph_duct_orientation"] : []))
  }
  static func context(_ id: String, stage: Int, language: String) -> [String] {
    guard let lesson = forEntry(id), let feature = lesson.feature(stage: stage) else { return [] }
    return lesson.notes.map { GalaxySSIHealthAtlasText.get($0, language) } + [GalaxySSIHealthAtlasText.get(feature.title, language)]
  }
}

// Compatibility for the existing lymphatic lesson callers and fixtures.
typealias GalaxySSIHealthAtlasLymphLesson = GalaxySSIHealthAtlasSectionLesson
