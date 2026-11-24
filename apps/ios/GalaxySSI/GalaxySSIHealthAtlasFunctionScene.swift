import SwiftUI

struct GalaxySSIHealthAtlasFunctionScene<Artwork: View>: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let language: String
  let phase: Double
  let showTitle: Bool
  let artwork: Artwork
  @Environment(\.colorScheme) private var colorScheme
  @ScaledMetric(relativeTo: .subheadline) private var captionSize: CGFloat = 15
  @ScaledMetric(relativeTo: .footnote) private var chapterSize: CGFloat = 14
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get(key, language) }
  private var labels: [String] {
    story.chapters.enumerated().map {
      String(format: t("health_atlas_scene_chapter"), Int64($0.offset + 1), Int64(story.chapters.count), t($0.element.title))
    }
  }
  var body: some View {
    let colors = GalaxySSIHealthAtlasFilmPalette.values(dark: colorScheme == .dark)
    GalaxySSIHealthAtlasSceneFrame(identifier: "atlas-function-frame", ground: GalaxySSIHealthAtlasFilmPalette.color(colors.ground)) {
      VStack(alignment: .leading, spacing: 0) {
        if showTitle {
          Text(t(story.title)).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
        }
        artwork.frame(maxWidth: .infinity)
        VStack(alignment: .leading, spacing: 2) {
          GalaxySSIHealthAtlasReservedCaption(values: labels, selected: story.chapter(phase), identifier: "atlas-function-chapter")
            .font(.system(size: chapterSize, weight: .semibold)).foregroundColor(GalaxySSIHealthAtlasFilmPalette.color(colors.chapter))
          GalaxySSIHealthAtlasReservedCaption(values: story.chapters.map { t($0.caption) }, selected: story.chapter(phase), identifier: "atlas-function-caption")
            .font(.system(size: captionSize)).foregroundColor(GalaxySSIHealthAtlasFilmPalette.color(colors.text))
        }.padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 12)
          .background(GalaxySSIHealthAtlasFilmPalette.color(colors.caption))
          .accessibilityIdentifier("atlas-function-subtitles")
      }
    }
  }
}
