import SwiftUI

struct GalaxySSIHealthAtlasFunctionScene<Artwork: View>: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let language: String
  let phase: Double
  let showTitle: Bool
  let artwork: Artwork
  @ScaledMetric(relativeTo: .subheadline) private var captionSize: CGFloat = 15
  @ScaledMetric(relativeTo: .footnote) private var chapterSize: CGFloat = 14
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get(key, language) }
  private var labels: [String] {
    story.chapters.enumerated().map {
      String(format: t("health_atlas_scene_chapter"), Int64($0.offset + 1), Int64(story.chapters.count), t($0.element.title))
    }
  }
  var body: some View {
    GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-function-frame", legendIdentifier: "atlas-function-subtitles") {
      if showTitle {
        Text(t(story.title)).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 12)
      }
    } artwork: {
      artwork
    } legend: {
      VStack(alignment: .leading, spacing: 2) {
        GalaxySSIHealthAtlasReservedCaption(values: labels, selected: story.chapter(phase), identifier: "atlas-function-chapter")
          .font(.system(size: chapterSize, weight: .semibold)).foregroundColor(GalaxySSIHealthTheme.accent)
        GalaxySSIHealthAtlasReservedCaption(values: story.chapters.map { t($0.caption) }, selected: story.chapter(phase), identifier: "atlas-function-caption")
          .font(.system(size: captionSize)).foregroundColor(.primary)
      }
    }
  }
}
