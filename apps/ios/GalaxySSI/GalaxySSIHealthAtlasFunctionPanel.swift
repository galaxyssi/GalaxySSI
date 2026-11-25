import SwiftUI

struct GalaxySSIHealthAtlasFunctionPanel: View {
  let catalogue: GalaxySSIHealthAtlasFunctionCatalogue
  let entryID: String
  let language: String
  let previewPresented: Bool
  @Binding var selection: GalaxySSIHealthAtlasFunctionSelection
  let onPhase: (String, Double) -> Void
  private var choices: [GalaxySSIHealthAtlasFunctionCatalogue.Story] {
    catalogue.choices(for: entryID).filter { GalaxySSIHealthAtlasFunctionRendering.implemented.contains($0.id) }
  }
  private var current: GalaxySSIHealthAtlasFunctionCatalogue.Story? {
    choices.first { $0.id == selection.selected } ?? choices.first
  }
  var body: some View {
    if let story = current {
      VStack(alignment: .leading, spacing: 12) {
        if choices.count > 3 { picker.pickerStyle(.menu) }
        else if choices.count > 1 {
          GalaxySSIHealthAtlasCompactTabs(options: choices.map(\.id), selection: Binding(
            get: { current?.id ?? "" }, set: { selection.choose($0, entryID: entryID, catalogue: catalogue) }),
            title: { id in choices.first(where: { $0.id == id }).map { GalaxySSIHealthAtlasFunctionText.get($0.choiceTitle, language) } ?? "" },
            key: { $0 }, identifier: "atlas-function-lesson")
        }
        GalaxySSIHealthAtlasFunctionPlayer(story: story, language: language, phase: phase(story.id),
          previewPresented: previewPresented,
          showTitle: !(2...3).contains(choices.count) ||
            GalaxySSIHealthAtlasFunctionText.get(story.choiceTitle, language) != GalaxySSIHealthAtlasFunctionText.get(story.title, language),
          playbackID: "function|" + entryID + "|" + story.id,
          onPhase: { onPhase(story.id, $0) }) { position in
            GalaxySSIHealthAtlasFunctionArtwork(story: story, phase: position, language: language)
          }.id(entryID + "|" + story.id)
          .onAppear { selection.choose(story.id, entryID: entryID, catalogue: catalogue) }
      }
    }
  }
  private var picker: some View {
    Picker(GalaxySSIHealthAtlasFunctionText.get("health_atlas_sense_choose", language), selection: Binding(
      get: { current?.id ?? "" }, set: { selection.choose($0, entryID: entryID, catalogue: catalogue) })) {
      ForEach(choices) { story in Text(GalaxySSIHealthAtlasFunctionText.get(story.choiceTitle, language)).tag(story.id) }
    }.accessibilityIdentifier(choices.count > 3 ? "atlas-function-lesson-menu" : "atlas-function-lesson")
  }
  private func phase(_ storyID: String) -> Binding<Double> {
    Binding(get: { selection.phase(entryID: entryID, storyID: storyID, catalogue: catalogue) },
      set: { selection.save($0, storyID: storyID, entryID: entryID, catalogue: catalogue) })
  }
}
