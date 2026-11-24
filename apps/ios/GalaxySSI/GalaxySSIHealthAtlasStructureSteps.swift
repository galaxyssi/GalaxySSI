import SwiftUI

enum GalaxySSIHealthAtlasLandmarks {
  struct Landmark {
    let id: String
    let title: String
    let description: String
    let point: CGPoint
    let feature: Bool
  }
  static func list(_ plate: GalaxySSIHealthAtlas.Plate, atlas: GalaxySSIHealthAtlas) -> [Landmark] {
    let anatomy = plate.markers.compactMap { marker -> Landmark? in
      guard let entry = atlas.entry(marker.id) else { return nil }
      return .init(id: marker.id, title: entry.name, description: entry.description,
        point: .init(x: marker.x, y: marker.y), feature: false)
    }
    let features = plate.annotations.map {
      Landmark(id: $0.id, title: $0.title, description: $0.explanation,
        point: .init(x: $0.marker.x, y: $0.marker.y), feature: true)
    }
    return (anatomy + features).enumerated().sorted {
      $0.element.point.y == $1.element.point.y ? $0.offset < $1.offset : $0.element.point.y < $1.element.point.y
    }.map(\.element)
  }
}

struct GalaxySSIHealthAtlasStructureSteps: Codable, Equatable {
  struct Step: Codable, Equatable {
    let owner: String
    let view: String
    var position: Int
    var key: String { owner + "|" + view }
  }
  private(set) var steps: [Step] = []
  func position(owner: String, view: String, count: Int) -> Int {
    min(max(0, count), max(0, steps.first { $0.owner == owner && $0.view == view }?.position ?? 0))
  }
  mutating func select(_ position: Int, owner: String, view: String, count: Int) {
    let position = min(max(0, count), max(0, position))
    let index = steps.firstIndex { $0.owner == owner && $0.view == view }
    if position == 0 { if let index { steps.remove(at: index) }; return }
    if let index { steps[index].position = position }
    else { steps.append(.init(owner: owner, view: view, position: position)) }
    if steps.count > 400 { steps.removeFirst(steps.count - 400) }
  }
  var serialized: String {
    (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  }
  static func restore(_ text: String, atlas: GalaxySSIHealthAtlas) -> Self {
    guard text.utf8.count <= 128_000, let data = text.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(Self.self, from: data), decoded.steps.count <= 400 else { return .init() }
    var clean = Self()
    for step in decoded.steps {
      guard step.owner.isEmpty || atlas.entry(step.owner) != nil,
        let plate = atlas.views(for: step.owner.isEmpty ? nil : step.owner).first(where: { ($0.viewKey ?? "") == step.view }),
        plate.hasLabels else { continue }
      clean.select(step.position, owner: step.owner, view: step.view, count: GalaxySSIHealthAtlasLandmarks.list(plate, atlas: atlas).count)
    }
    return clean
  }
}
