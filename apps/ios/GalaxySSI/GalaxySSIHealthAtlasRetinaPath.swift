import Foundation

enum GalaxySSIHealthAtlasRetinaPath {
  static let owner = "retina"
  static let source = URL(string: "https://pubmed.ncbi.nlm.nih.gov/28856684/")!
  static let nodes = ["sensory_retinal_rod_label", "sensory_retinal_relay_rod", "sensory_retinal_cone_label", "sensory_retinal_ganglion"]
  private static let links = [
    ["cell-rod-photoreceptor"],
    ["cell-retinal-bipolar-cell", "cell-retinal-aii-amacrine-cell"],
    ["cell-cone-photoreceptor"],
    ["cell-retinal-ganglion-cell"]
  ]
  static func destinations(stage: Int) -> [String]? { links.indices.contains(stage) ? links[stage] : nil }
  static func context(_ id: String, text t: (String) -> String) -> [String] {
    id == owner ? [t("sensory_retinal_scope"), t("sensory_retinal_relay_rod"), source.absoluteString] : []
  }
  static var eyeContext: GalaxySSIHealthAtlas.Plate {
    let eye = GalaxySSIHealthAtlasEyeOptics.plate
    return .init(id: "retina-eye-context", asset: eye.asset, owner: eye.owner, viewLabel: eye.viewLabel,
      entryIDs: eye.entryIDs, aspectRatio: eye.aspectRatio, markers: eye.markers, source: eye.source,
      viewKey: "retina-eye-context", selectorLabel: "health_atlas_sensory_retinal_eye_location", splitCallouts: eye.splitCallouts)
  }
}
