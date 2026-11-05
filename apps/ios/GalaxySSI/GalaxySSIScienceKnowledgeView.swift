import SwiftUI
import UIKit

@MainActor
struct GalaxySSIScienceKnowledgeView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var source = PublicScienceSource.biology
  @State private var entries: [PublicScienceEntry] = []
  @State private var refreshing = false
  @State private var unavailable = false
  @State private var search = ""

  var body: some View {
    List {
      Picker(t("science_source", "Source"), selection: $source) {
        ForEach(PublicScienceSource.allCases) { Text(title($0)).tag($0) }
      }
      if refreshing { ProgressView() }
      if unavailable {
        Text(t("science_catalog_unavailable", "Could not refresh the publisher catalog."))
          .foregroundColor(.secondary)
      }
      ForEach(entries.filter {
        search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
      }) { entry in
        NavigationLink {
          GalaxySSIScienceArticleView(source: source, entry: entry)
        } label: {
          Text(entry.title)
        }
      }
    }
    .navigationTitle(t("science_title", "Life sciences"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(t("common_close", "Close")) { dismiss() }
      }
    }
    .searchable(text: $search, prompt: t("science_search", "Search sections"))
    .task(id: source) { await load(source, force: false) }
    .refreshable { await load(source, force: true) }
  }

  private func load(_ requested: PublicScienceSource, force: Bool) async {
    guard !Task.isCancelled, requested == source else { return }
    let cached = PublicScienceCatalog.cached(requested)
    entries = cached?.entries ?? []
    unavailable = false
    refreshing = false
    guard force || cached?.fresh != true else { return }
    refreshing = true
    do {
      let body = try await PublicScienceTransport.fetch(requested.endpoint, limit: 5_000_000)
      guard let html = String(data: body, encoding: .utf8) else { throw PublicScienceError.unreadable }
      let result = try await PublicScienceDOM().catalog(html: html, source: requested)
      guard !Task.isCancelled, requested == source else { return }
      entries = result
      PublicScienceCatalog.store(result, source: requested)
    } catch {
      guard !Task.isCancelled, requested == source else { return }
      unavailable = true
    }
    refreshing = false
  }

  private func title(_ source: PublicScienceSource) -> String {
    switch source {
    case .biology: return t("science_biology", "Biology 2e")
    case .microbiology: return t("science_microbiology", "Microbiology")
    case .anatomy: return t("science_anatomy", "Anatomy and Physiology 2e")
    case .molecule: return "RCSB PDB-101"
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIScienceArticleView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let source: PublicScienceSource
  let entry: PublicScienceEntry
  @State private var document: PublicScienceDocument?
  @State private var tab = Tab.figures
  @State private var figureCount = 4
  @State private var unavailable = false
  @State private var retry = 0
  @State private var image: GalaxySSIImageViewerItem?

  private enum Tab: Hashable { case figures, text }

  var body: some View {
    VStack(spacing: 0) {
      if let document {
        Picker(t("science_reader_mode", "Reader mode"), selection: $tab) {
          Text(t("science_figures", "Figures")).tag(Tab.figures)
          Text(t("science_original_text", "Original text")).tag(Tab.text)
        }
        .pickerStyle(.segmented)
        .padding(12)
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 14) {
            Text(document.title).font(.title2.weight(.semibold)).textSelection(.enabled)
            if tab == .figures {
              if document.figures.isEmpty {
                Text(t("science_no_figures", "No figures in this section.")).foregroundColor(.secondary)
              }
              ForEach(document.figures.prefix(figureCount)) { figure in
                GalaxySSIScienceFigureView(source: source, figure: figure) { data in
                  image = GalaxySSIImageViewerItem(id: figure.url.absoluteString, data: data,
                    url: nil, title: figure.caption)
                }
              }
              if document.figures.count > figureCount {
                Button(t("science_more_figures", "Load more figures")) { figureCount += 4 }
                  .frame(minHeight: 44)
              }
            } else {
              ForEach(document.sections) { section in
                Text(section.text)
                  .font(section.heading ? .headline : .body)
                  .textSelection(.enabled)
              }
            }
            Divider()
            Text(document.attribution.joined(separator: " · ")).font(.footnote).foregroundColor(.secondary)
            if let license = document.license {
              Link(t("science_license", "License"), destination: license)
            }
            Link(t("public_news_open_source", "Open publisher"), destination: entry.url)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
        }
        .id(tab)
      } else if unavailable {
        VStack(alignment: .leading, spacing: 12) {
          Text(t("science_article_unavailable", "Could not load this article."))
          Button(t("science_retry", "Retry")) { retry += 1 }
          Link(t("public_news_open_source", "Open publisher"), destination: entry.url)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .navigationTitle(source.publisher)
    .navigationBarTitleDisplayMode(.inline)
    .task(id: retry) { await load() }
    .fullScreenCover(item: $image) { GalaxySSIImageLightboxView(item: $0) }
  }

  private func load() async {
    unavailable = false
    do {
      guard source.acceptsArticle(entry.url) else { throw PublicScienceError.invalidSource }
      let data = try await PublicScienceTransport.fetch(entry.url, limit: 5_000_000)
      guard let html = String(data: data, encoding: .utf8) else { throw PublicScienceError.unreadable }
      let parsed = try await PublicScienceDOM().article(html: html, source: source, url: entry.url)
      guard !Task.isCancelled else { return }
      tab = parsed.figures.isEmpty ? .text : .figures
      document = parsed
    } catch {
      if !Task.isCancelled { unavailable = true }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIScienceFigureView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let source: PublicScienceSource
  let figure: PublicScienceDocument.Figure
  let open: (Data) -> Void
  @State private var thumbnail: UIImage?
  @State private var data: Data?
  @State private var failed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let data, let thumbnail {
        Button { open(data) } label: {
          Image(uiImage: thumbnail).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 280)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("science_enlarge_figure", "Enlarge figure"))
      } else if failed {
        Text(t("science_figure_unavailable", "Could not load this figure.")).foregroundColor(.secondary)
      } else {
        ProgressView().frame(maxWidth: .infinity, minHeight: 64)
      }
      if !figure.caption.isEmpty { Text(figure.caption).font(.callout).textSelection(.enabled) }
    }
    .task {
      failed = false
      do {
        guard source.acceptsImage(figure.url) else { throw PublicScienceError.invalidSource }
        let bytes = try await PublicScienceTransport.fetch(figure.url, limit: 8_000_000)
        let image = await Task.detached { GalaxySSIImageResourceDecoder.staticImage(from: bytes) }.value
        guard !Task.isCancelled else { return }
        guard let image else { throw PublicScienceError.unreadable }
        thumbnail = image
        data = bytes
      } catch {
        if !Task.isCancelled { failed = true }
      }
    }
    .onDisappear { thumbnail = nil; data = nil }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
