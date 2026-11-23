import Foundation
import UIKit

/// Visibility graph for layout-time label leaders, never animation-frame work.
enum GalaxySSIHealthAtlasLeaderRoutes {
  static func segmentDistance(_ point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
    let dx = end.x - start.x, dy = end.y - start.y, length = dx * dx + dy * dy
    guard length > 0 else { return hypot(point.x - start.x, point.y - start.y) }
    let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / length))
    return hypot(point.x - start.x - t * dx, point.y - start.y - t * dy)
  }
  static func route(start: CGPoint, end: CGPoint, obstacles: [CGPoint], clearance: CGFloat,
                    minX: CGFloat = -.infinity, maxX: CGFloat = .infinity) -> [CGPoint] {
    guard clearance.isFinite, clearance > 0, obstacles.count <= 32,
      !minX.isNaN, !maxX.isNaN, minX <= maxX, start.x >= minX, start.x <= maxX, end.x >= minX, end.x <= maxX,
      ([start, end] + obstacles).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    func visible(_ a: CGPoint, _ b: CGPoint) -> Bool {
      obstacles.allSatisfy { segmentDistance($0, start: a, end: b) >= clearance }
    }
    if visible(start, end) { return [start, end] }
    if obstacles.contains(where: { distance($0, start) < clearance || distance($0, end) < clearance }) { return [] }
    let offset = clearance * 1.5
    var points = [start, end]
    for point in obstacles {
      for candidate in [CGPoint(x: point.x - offset, y: point.y - offset), CGPoint(x: point.x + offset, y: point.y - offset),
        CGPoint(x: point.x + offset, y: point.y + offset), CGPoint(x: point.x - offset, y: point.y + offset)] {
        if candidate.x >= minX, candidate.x <= maxX, !points.contains(candidate),
          obstacles.allSatisfy({ distance(candidate, $0) >= clearance }) { points.append(candidate) }
      }
    }
    var best = Array(repeating: CGFloat.infinity, count: points.count)
    var previous = Array(repeating: -1, count: points.count)
    var visited = Set<Int>()
    best[0] = 0
    for _ in points.indices {
      guard let current = points.indices.filter({ !visited.contains($0) }).min(by: { best[$0] < best[$1] }),
        best[current].isFinite else { return [] }
      if current == 1 {
        var index = 1, path = [CGPoint]()
        while index >= 0 { path.append(points[index]); index = previous[index] }
        return Array(path.reversed())
      }
      visited.insert(current)
      for next in points.indices where !visited.contains(next) && visible(points[current], points[next]) {
        let cost = best[current] + distance(points[current], points[next])
        if cost < best[next] { best[next] = cost; previous[next] = current }
      }
    }
    return []
  }
}

extension GalaxySSIHealthAtlas {
  struct OverviewPack: Decodable {
    let schema: Int
    let plates: [Plate]
    var relatedAdditions: [String: [String]]? = nil
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static func read(bundle: Bundle) throws -> Self? {
      guard let data = NSDataAsset(name: "HealthAtlasSystemOverviews", bundle: bundle)?.data else { return nil }
      guard data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: data)
    }
    func validating(in atlas: GalaxySSIHealthAtlas, bundle: Bundle) throws {
      guard schema == 1, plates.count == 10, Set(plates.map(\.id)).count == plates.count,
        Set(plates.flatMap(\.entryIDs)).count == plates.flatMap(\.entryIDs).count,
        plates.allSatisfy({ plate in
          guard let owner = plate.owner, atlas.entry(owner)?.kind == .system,
            plate.entryIDs.contains(owner), !plate.entryIDs.isEmpty,
            plate.viewLabel == "health_atlas_view_system_" + (["male": "testicular", "female": "ovarian"][owner] ?? owner),
            plate.entryIDs.allSatisfy({ atlas.entry($0)?.kind == .system || atlas.entry($0)?.kind == .organ }),
            plate.source?.scheme == "https", plate.source?.host == "openstax.org",
            plate.source?.user == nil, plate.source?.password == nil,
            plate.asset.hasPrefix("HealthAtlasOverview"),
            UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil,
            plate.aspectRatio.isFinite, (0.1...3).contains(plate.aspectRatio),
            Set(plate.markers.map(\.id)).count == plate.markers.count else { return false }
          return plate.markers.allSatisfy { marker in
            atlas.entry(marker.id)?.kind == .organ && marker.x.isFinite && marker.y.isFinite &&
              (0...1).contains(marker.x) && (0...1).contains(marker.y)
          }
        }) else { throw Invalid.catalogue }
    }
    func applying(to atlas: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let additions = relatedAdditions ?? [:]
      guard additions.isEmpty || additions == ["cardio": ["aorta", "pulmonary-trunk", "lungs"]] else { throw Invalid.catalogue }
      let revised = atlas.entries.map { entry in
        entry.replacing(related: entry.related + (additions[entry.id] ?? []).filter { !entry.related.contains($0) })
      }
      let result = try GalaxySSIHealthAtlas.validated(.init(schema: atlas.schema, entries: revised, mechanisms: atlas.mechanisms))
      try validating(in: result, bundle: bundle)
      return result
    }
  }
}
