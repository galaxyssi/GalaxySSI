import SwiftUI

struct GalaxySSIHealthAtlasBloodDefenseView: View {
  let atlas: GalaxySSIHealthAtlas
  let lesson: GalaxySSIHealthAtlasBloodDefense
  let phase: Double
  let stages: [String]
  let language: String
  let open: (String) -> Void
  var showsDetails = true
  var body: some View {
    if let frame = Frame(lesson, phase: phase) {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSIHealthAtlasCellScene(frame: frame.scene, stages: stages, language: language, identifier: "atlas-blood-defense-diagram") { drawing in
          GalaxySSIHealthAtlasBloodDefenseDrawing(lesson: lesson).drawScene(in: drawing, frame: frame)
        }
        if showsDetails {
          Text(GalaxySSIHealthAtlasText.get("health_atlas_" + lesson.scopeKey, language)).font(.footnote).foregroundColor(.secondary)
          if let id = lesson.relatedID {
            GalaxySSIHealthAtlasCellSceneRelatedRow(atlas: atlas, entryID: id, language: language, open: open)
          }
        }
      }
    }
  }
}
