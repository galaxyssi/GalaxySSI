import SwiftUI

struct GalaxySSIHealthAtlasFunctionPlaybackMenu: View {
  enum Panel: String, Identifiable { case chapters, evidence; var id: String { rawValue } }
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let language: String
  let phase: Double
  let seek: (Double) -> Void
  let pause: () -> Void
  @Environment(\.openURL) private var openURL
  @State private var menu = false
  @State private var panel: Panel?
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get(key, language) }
  var body: some View {
    Button { pause(); menu = true } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
      .accessibilityLabel(t("health_atlas_scene_menu")).help(t("health_atlas_scene_menu"))
      .accessibilityIdentifier("atlas-function-menu")
      .confirmationDialog(t("health_atlas_scene_menu"), isPresented: $menu, titleVisibility: .visible) {
        Button(t("health_atlas_function_outline")) { panel = .chapters }
        Button(t("health_atlas_reset")) { seek(0) }.accessibilityIdentifier("atlas-function-reset")
        Button(t("health_atlas_evidence")) { panel = .evidence }
      }
      .sheet(item: $panel) { selected in
        NavigationView {
          Group {
            switch selected {
            case .chapters: chapters
            case .evidence: evidence
            }
          }.navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button { panel = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                  .accessibilityLabel(GalaxySSILocalization.string("galaxyssi.cancel", fallback: "Cancel", language: language))
              }
            }
        }.navigationViewStyle(.stack)
      }
  }
  private var chapters: some View {
    List {
      ForEach(Array(story.chapters.enumerated()), id: \.offset) { index, chapter in
        Button { seek(story.startOf(index)); panel = nil } label: {
          HStack {
            Text(String(format: t("health_atlas_scene_chapter"), Int64(index + 1), Int64(story.chapters.count), t(chapter.title)))
              .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if index == story.chapter(phase) { Image(systemName: "checkmark").accessibilityHidden(true) }
          }.frame(minHeight: 44)
        }.accessibilityAddTraits(index == story.chapter(phase) ? .isSelected : [])
          .accessibilityIdentifier("atlas-function-outline-stage-" + String(index))
      }
    }.navigationTitle(t("health_atlas_function_outline")).accessibilityIdentifier("atlas-function-chapter-picker")
  }
  private var evidence: some View {
    List {
      Text(t(story.scope)).fixedSize(horizontal: false, vertical: true)
      NavigationLink(t("health_atlas_scene_sources")) {
        List {
          ForEach(Array(story.references.enumerated()), id: \.offset) { index, reference in
            Button { openURL(reference.url); panel = nil } label: {
              Label(t(reference.title), systemImage: "arrow.up.right").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
            }.accessibilityIdentifier("atlas-function-source-" + String(index))
          }
        }.navigationTitle(t("health_atlas_scene_sources"))
      }
    }.navigationTitle(t("health_atlas_evidence"))
  }
}
