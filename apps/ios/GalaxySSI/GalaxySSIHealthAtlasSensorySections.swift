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
      source: original.source, viewKey: original.viewKey, selectorLabel: original.selectorLabel, features: features,
      splitCallouts: original.splitCallouts)
  }
  static let ear: Lesson = {
    func feature(_ id: String, _ x: Double, _ y: Double, _ title: String, _ stage: Int) -> Feature {
      Feature(marker: .init(id: id, x: x / 420, y: y / 280), title: "health_atlas_" + title,
        explanation: "health_atlas_hearing_ear_" + String(stage))
    }
    let features = [feature("ear-canal", 135, 145, "external_ear_name", 0),
      feature("eardrum", 187, 139, "hearing_eardrum", 1),
      feature("ossicles", 223, 118, "hearing_ossicles", 2),
      feature("cochlea-output", 319, 156, "cochlea_name", 3)]
    let routes: [Lesson.Route] = [
      .init(start: .init(x: 79, y: 149), commands: [
        .init(kind: .cubic, points: [.init(x: 100, y: 146), .init(x: 124, y: 144), .init(x: 153, y: 145)])]),
      .init(start: .init(x: 153, y: 145), commands: [.init(kind: .quad, points: [.init(x: 172, y: 145), .init(x: 187, y: 139)])]),
      .init(start: .init(x: 195, y: 145), commands: [
        .init(kind: .quad, points: [.init(x: 202, y: 111), .init(x: 211, y: 109)]),
        .init(kind: .cubic, points: [.init(x: 221, y: 109), .init(x: 228, y: 113), .init(x: 229, y: 120)]),
        .init(kind: .quad, points: [.init(x: 233, y: 133), .init(x: 236, y: 143)]),
        .init(kind: .line, points: [.init(x: 266, y: 144)])]),
      .init(start: .init(x: 319, y: 156), commands: [
        .init(kind: .cubic, points: [.init(x: 344, y: 153), .init(x: 351, y: 151), .init(x: 361, y: 147)]),
        .init(kind: .cubic, points: [.init(x: 382, y: 143), .init(x: 395, y: 138), .init(x: 411, y: 135)])])
    ]
    return Lesson(plate: copy(GalaxySSIHealthAtlasMiddleEar.plate, features: features), stageFeatures: [0, 1, 2, 3],
      routes: routes, notes: ["health_atlas_hearing_route_scope"], artWidth: 420)
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
