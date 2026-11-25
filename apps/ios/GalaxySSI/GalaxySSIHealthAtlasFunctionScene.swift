import SwiftUI

struct GalaxySSIHealthAtlasFunctionScene<Artwork: View>: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let language: String
  let phase: Double
  let showTitle: Bool
  let artwork: Artwork
  var onExplain: () -> Void = {}
  @State private var explanation: Explanation?
  private struct Explanation: Identifiable { let id: String; let title: String; let message: String }
  @ScaledMetric(relativeTo: .subheadline) private var captionSize: CGFloat = 13
  @ScaledMetric(relativeTo: .footnote) private var chapterSize: CGFloat = 14
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get(key, language) }
  private var labels: [String] {
    story.chapters.enumerated().map {
      String(format: t("health_atlas_scene_chapter"), Int64($0.offset + 1), Int64(story.chapters.count), t($0.element.title))
    }
  }
  var body: some View {
    GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-function-frame", legendIdentifier: "atlas-function-subtitles",
      overlayNote: true, header: { EmptyView() }, artwork: { artwork }, legend: {
      Button {
        let index = story.chapter(phase), chapter = labels[index], caption = t(story.chapters[index].caption)
        onExplain()
        explanation = .init(id: story.id, title: showTitle ? t(story.title) : chapter,
          message: showTitle ? chapter + "\n\n" + caption : caption)
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          GalaxySSIHealthAtlasReservedCaption(values: labels, selected: story.chapter(phase), identifier: "atlas-function-chapter")
            .font(.system(size: chapterSize, weight: .semibold)).foregroundColor(GalaxySSIHealthTheme.accent)
          GalaxySSIHealthAtlasReservedCaption(values: story.chapters.map { t($0.caption) }, selected: story.chapter(phase),
            identifier: "atlas-function-caption", maximumLines: 2)
            .font(.system(size: captionSize)).foregroundColor(.primary)
        }.contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("atlas-function-explanation")
    })
    .alert(item: $explanation) { note in
      Alert(title: Text(note.title), message: Text(note.message),
        dismissButton: .default(Text(GalaxySSILocalization.string("galaxyssi.close", fallback: "Close", language: language))))
    }
  }
}
