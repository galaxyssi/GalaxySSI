import SwiftUI
import UIKit

@MainActor
struct GalaxySSIPublicNewsDocumentView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ObservedObject private var playback = PublicNewsSpeechPlayback.shared
  let checkpoint: PublicNewsBodyCheckpoint
  let articleURL: URL
  let showChinese: Bool
  var playFromParagraph: ((Int) -> Void)? = nil
  @State private var visible = 24
  @State private var viewer: GalaxySSIImageViewerItem?

  var body: some View {
    let translation = showChinese ? checkpoint.translatedDocument : nil
    let paragraphs = translation?.paragraphs ?? checkpoint.source.paragraphs
    let presentation = checkpoint.source.presentation
    let figures = Dictionary(grouping: presentation?.figures ?? [], by: \.beforeParagraph)
    let limit = min(paragraphs.count, visible)
    let activeParagraph = highlightedParagraph(translated: translation != nil)
    return LazyVStack(alignment: .leading, spacing: 12) {
      if let translation { Text(translation.title).font(.headline).textSelection(.enabled) }
      ForEach(0..<limit, id: \.self) { index in
        images(figures[index] ?? [])
        let style = presentation?.styles.indices.contains(index) == true ? presentation?.styles[index] : nil
        paragraph(paragraphs[index], style: style, translated: translation != nil)
          .background(activeParagraph == index ? Color.galaxySSIAccent.opacity(0.14) : Color.clear)
          .contextMenu {
            if let playFromParagraph {
              Button { playFromParagraph(index) } label: {
                Label(t("public_news_speech_here", "Read from here"), systemImage: "speaker.wave.2")
              }
            }
          }
      }
      if limit == paragraphs.count {
        images(figures[limit] ?? [])
      } else {
        Button(t("public_news_load_more_body", "Load more of the article")) { visible += 24 }
          .frame(minHeight: 44)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .fullScreenCover(item: $viewer) { GalaxySSIImageLightboxView(item: $0) }
    .onChange(of: checkpoint.fingerprint) { _ in visible = 24; viewer = nil }
  }

  private func highlightedParagraph(translated: Bool) -> Int? {
    guard playback.queue.phase == .playing, let item = playback.queue.current,
          item.articleKey == PublicNewsSpeechBookmark.key(for: articleURL.absoluteString),
          item.edition == (translated ? .chinese : .original),
          let document = PublicNewsSpeechDocument(checkpoint: checkpoint, edition: item.edition),
          document.key == playback.queue.bookmark.documentKey else { return nil }
    return playback.queue.bookmark.paragraph
  }

  private func images(_ figures: [PublicNewsArticlePresentation.Figure]) -> some View {
    ForEach(figures) { figure in
      GalaxySSIPublicNewsFigureView(figure: figure, articleURL: articleURL) { data in
        viewer = GalaxySSIImageViewerItem(id: figure.url.absoluteString, data: data, url: nil, title: figure.caption)
      }
    }
  }

  @ViewBuilder
  private func paragraph(_ value: String, style: PublicNewsArticlePresentation.Paragraph?, translated: Bool) -> some View {
    let role = style?.role ?? .text
    if role == .quote {
      HStack(alignment: .top, spacing: 8) {
        Rectangle().fill(Color.galaxySSIAccent).frame(width: 2)
        Text(value).italic().textSelection(.enabled)
      }
      .fixedSize(horizontal: false, vertical: true)
    } else {
      let phrases = translated ? [] : (style?.emphasis ?? [])
      emphasized(value, phrases: phrases).font(role == .heading ? .headline : .body).textSelection(.enabled)
    }
  }

  private func emphasized(_ value: String, phrases: [String]) -> Text {
    var text = Text(verbatim: "")
    var start = value.startIndex
    for span in PublicNewsSearch.ranges(in: value, terms: phrases) {
      text = text + Text(verbatim: String(value[start..<span.lowerBound])) + Text(verbatim: String(value[span])).bold()
      start = span.upperBound
    }
    return text + Text(verbatim: String(value[start...]))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIPublicNewsFigureView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let figure: PublicNewsArticlePresentation.Figure
  let articleURL: URL
  let open: (Data) -> Void
  @State private var photo: UIImage?
  @State private var data: Data?
  @State private var unavailable = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let photo, let data {
        Button { open(data) } label: {
          Image(uiImage: photo).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 330)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("public_news_enlarge_image", "Enlarge article image"))
      } else if unavailable {
        Text(t("public_news_image_unavailable", "Source image unavailable")).foregroundColor(.secondary)
      } else {
        ProgressView().frame(maxWidth: .infinity, minHeight: 72)
      }
      if !figure.caption.isEmpty {
        Text(figure.caption).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
      }
    }
    .task(id: figure.url) {
      unavailable = false
      photo = nil
      data = nil
      do {
        let bytes = try await PublicNewsImageCache.shared.image(figure.url, article: articleURL)
        let decoded = await Task.detached { GalaxySSIImageResourceDecoder.staticImage(from: bytes) }.value
        guard !Task.isCancelled else { return }
        if let decoded { photo = decoded; data = bytes }
        else { unavailable = true }
      } catch {
        if !Task.isCancelled { unavailable = true }
      }
    }
    .onDisappear { photo = nil; data = nil }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIPublicNewsCover: View {
  let article: PublicNewsArticle
  @State private var photo: UIImage?

  var body: some View {
    if let url = article.coverURL, PublicNewsImagePolicy.accepts(url, for: article.url) {
      ZStack {
        Color.galaxySSIButtonSoft
        if let photo {
          Image(uiImage: photo).resizable().scaledToFill()
        } else {
          Image(systemName: "photo").foregroundColor(.galaxySSITextSecondary)
        }
      }
      .frame(width: 68, height: 54)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .accessibilityHidden(true)
      .task(id: url) {
        photo = nil
        guard let data = try? await PublicNewsImageCache.shared.image(url, article: article.url), !Task.isCancelled else { return }
        let image = await Task.detached { GalaxySSIImageResourceDecoder.staticImage(from: data) }.value
        if !Task.isCancelled { photo = image }
      }
      .onDisappear { photo = nil }
    }
  }
}
