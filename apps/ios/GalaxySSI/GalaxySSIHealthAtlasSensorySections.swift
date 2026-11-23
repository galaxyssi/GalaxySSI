import Foundation

enum GalaxySSIHealthAtlasSensorySections {
  typealias Lesson = GalaxySSIHealthAtlasSectionLesson
  typealias Plate = GalaxySSIHealthAtlas.Plate
  typealias Feature = GalaxySSIHealthAtlas.Feature
  static func forEntry(_ id: String) -> Lesson? {
    switch id {
    case "ear": return ear
    case "retina": return retina
    default: return nil
    }
  }
  private static func copy(_ original: Plate, features: [Feature], keepMarkers: Bool = true) -> Plate {
    Plate(id: original.id, asset: original.asset, owner: original.owner, viewLabel: original.viewLabel,
      entryIDs: original.entryIDs, aspectRatio: original.aspectRatio, markers: keepMarkers ? original.markers : [],
      source: original.source, viewKey: original.viewKey, selectorLabel: original.selectorLabel, features: features)
  }
  static let ear: Lesson = {
    func feature(_ id: String, _ x: Double, _ y: Double, _ title: String, _ stage: Int) -> Feature {
      Feature(marker: .init(id: id, x: x / 460, y: y / 280), title: "health_atlas_" + title,
        explanation: "health_atlas_hearing_ear_" + String(stage))
    }
    let features = [feature("ear-canal", 148, 140, "external_ear_name", 0),
      feature("eardrum", 214, 138, "hearing_eardrum", 1),
      feature("ossicles", 254, 111, "hearing_ossicles", 2),
      feature("cochlea-output", 361, 177, "cochlea_name", 3)]
    let routes: [Lesson.Route] = [
      .init(start: .init(x: 40, y: 137), commands: [
        .init(kind: .cubic, points: [.init(x: 66, y: 130), .init(x: 77, y: 137), .init(x: 95, y: 140)]),
        .init(kind: .quad, points: [.init(x: 132, y: 136), .init(x: 179, y: 137)])]),
      .init(start: .init(x: 179, y: 137), commands: [.init(kind: .quad, points: [.init(x: 193, y: 140), .init(x: 214, y: 138)])]),
      .init(start: .init(x: 220, y: 137), commands: [
        .init(kind: .line, points: [.init(x: 231, y: 106)]),
        .init(kind: .quad, points: [.init(x: 248, y: 91), .init(x: 255, y: 109)]),
        .init(kind: .line, points: [.init(x: 262, y: 141)]),
        .init(kind: .line, points: [.init(x: 289, y: 141)])]),
      .init(start: .init(x: 357, y: 179), commands: [
        .init(kind: .cubic, points: [.init(x: 377, y: 176), .init(x: 397, y: 181), .init(x: 442, y: 198)])])
    ]
    return Lesson(plate: copy(GalaxySSIHealthAtlasMiddleEar.plate, features: features), stageFeatures: [0, 1, 2, 3],
      routes: routes, notes: ["health_atlas_hearing_route_scope"], artWidth: 460)
  }()
  static let retina: Lesson? = {
    guard let pack = try? GalaxySSIHealthAtlas.SensoryPack.bundled.get(),
      let original = pack.plates.first(where: { $0.owner == "retina" }),
      let rod = original.markers.first(where: { $0.id == "cell-rod-photoreceptor" }),
      let relay = original.annotations.first(where: { $0.id == "retina-relay-layer" }),
      let cone = original.markers.first(where: { $0.id == "cell-cone-photoreceptor" }),
      let ganglion = original.markers.first(where: { $0.id == "cell-retinal-ganglion-cell" }) else { return nil }
    let features = [
      Feature(marker: rod, title: "health_atlas_sensory_retinal_rod_label", explanation: "health_atlas_sensory_rod_discs_detail"),
      relay,
      Feature(marker: cone, title: "health_atlas_sensory_retinal_cone_label", explanation: "health_atlas_sensory_cone_outer_segment_detail"),
      Feature(marker: ganglion, title: "health_atlas_sensory_retinal_ganglion", explanation: "health_atlas_sensory_rgc_axon_detail")
    ]
    // Render-only layer highlights do not replace the structure view's navigation markers.
    return Lesson(plate: copy(original, features: features, keepMarkers: false), stageFeatures: [0, 1, 2, 3], routes: [])
  }()
}
