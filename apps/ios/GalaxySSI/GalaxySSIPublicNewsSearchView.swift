import SwiftUI

@MainActor
struct GalaxySSIPublicNewsSearchView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ObservedObject var archive: PublicNewsArchive
  @SceneStorage("publicNews.searchText") private var text = ""
  @SceneStorage("publicNews.searchScope") private var scope = "all"
  @SceneStorage("publicNews.searchOrder") private var order = "relevance"
  @SceneStorage("publicNews.searchPeriod") private var period = 0
  @SceneStorage("publicNews.searchPublisher") private var publisher = ""
  @FocusState private var searchFocused: Bool
  @State private var result: PublicNewsSearchResult?
  @State private var resolvedQuery: PublicNewsSearchRequest?
  @State private var hits: [PublicNewsSearchHit] = []
  @State private var searching = false
  @State private var article: PublicNewsArticle?

  private struct SearchVersion: Equatable {
    var query: PublicNewsSearchRequest
    var refreshing: Bool
  }

  private var request: PublicNewsSearchRequest {
    PublicNewsSearchRequest(
      text: text, scope: .init(rawValue: scope) ?? .all, order: .init(rawValue: order) ?? .relevance,
      period: .init(rawValue: period) ?? .anytime, publisher: publisher
    )
  }

  private var publishers: [String] {
    let available = Set(archive.eligibleArticles.map(\.publisher))
    return (publisher.isEmpty ? available : available.union([publisher])).sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("public_news_search", "Search news"),
        leading: { GalaxySSIBackButton() },
        trailing: {
          Menu {
            Picker(t("public_news_publisher", "Publisher"), selection: $publisher) {
              Text(t("public_news_all_publishers", "All publishers")).tag("")
              ForEach(publishers, id: \.self) { Text($0).tag($0) }
            }
            Picker(t("public_news_period", "Time"), selection: $period) {
              Text(t("public_news_anytime", "Any time")).tag(0)
              Text(t("public_news_week", "Past 7 days")).tag(7)
              Text(t("public_news_month", "Past 30 days")).tag(30)
              Text(t("public_news_quarter", "Past 90 days")).tag(90)
            }
            Picker(t("public_news_sort", "Sort"), selection: $order) {
              Text(t("public_news_relevance", "Relevance")).tag("relevance")
              Text(t("public_news_newest", "Newest")).tag("newest")
            }
          } label: {
            Image(systemName: "line.3.horizontal.decrease.circle").frame(width: 40, height: 44)
          }
          .accessibilityLabel(t("public_news_filter", "News filter"))
        }
      )
      VStack(spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass").accessibilityHidden(true)
          TextField(t("public_news_search", "Search news"), text: $text)
            .focused($searchFocused)
            .submitLabel(.search)
            .onSubmit { searchFocused = false }
            .onChange(of: text) { value in
              if value.count > PublicNewsSearch.maximumQueryLength {
                text = String(value.prefix(PublicNewsSearch.maximumQueryLength))
              }
            }
          if !text.isEmpty {
            Button { text = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 36, height: 40) }
              .accessibilityLabel(t("public_news_clear_search", "Clear search"))
          }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(Color.galaxySSISearchBackground, in: RoundedRectangle(cornerRadius: 8))
        Picker(t("public_news_filter", "News filter"), selection: $scope) {
          Text(t("public_news_all", "All")).tag("all")
          Text(t("public_news_unread", "Unread")).tag("unread")
          Text(t("public_news_saved", "Saved")).tag("saved")
        }
        .pickerStyle(.segmented)
      }
      .padding(12)
      results
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .task(id: SearchVersion(query: request, refreshing: archive.refreshing)) {
      await runSearch(request)
    }
    .onChange(of: archive.notRelevantIDs) { hidden in
      guard let result else { return }
      self.result = PublicNewsSearchResult(
        articles: result.articles.filter { !hidden.contains($0.id) }, terms: result.terms
      )
      hits.removeAll { hidden.contains($0.id) }
    }
    .sheet(item: $article) { GalaxySSIPublicNewsReader(archive: archive, original: $0) }
  }

  private var results: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          Color.clear.frame(height: 0).id("search-top")
          if searching {
            ProgressView().frame(maxWidth: .infinity).padding()
          } else if let result {
            Text(String(format: t("public_news_matches", "%d results"), result.articles.count))
              .font(.caption)
              .foregroundColor(.galaxySSITextSecondary)
              .padding(.vertical, 8)
            ForEach(hits) { hit in
              row(hit, terms: result.terms)
              Divider()
            }
            if hits.count < result.articles.count {
              Button(t("public_news_more", "Load more")) { hits += result.page(start: hits.count) }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
          }
        }
        .padding(.horizontal, 12)
      }
      .onChange(of: request) { _ in proxy.scrollTo("search-top") }
    }
  }

  private func row(_ hit: PublicNewsSearchHit, terms: [String]) -> some View {
    let current = archive.articles.first { $0.id == hit.id } ?? hit.article
    return HStack(spacing: 8) {
      GalaxySSIPublicNewsHeadline(archive: archive, article: current, onOpen: {
        searchFocused = false
        article = current
        archive.markRead(current.id)
      }) {
        highlighted(current.title, terms: terms)
          .font(.body.weight(current.read ? .regular : .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(3)
      } detail: {
        if !hit.snippet.isEmpty {
          highlighted(hit.snippet, terms: terms).font(.callout).lineLimit(3)
        }
        GalaxySSIPublicNewsByline(article: current)
      }
      .padding(.vertical, 12)
      GalaxySSIPublicNewsBookmark(archive: archive, article: current)
    }
    .padding(.leading, 12)
    .background(Color.galaxySSISurface)
  }

  private func highlighted(_ value: String, terms: [String]) -> Text {
    var styled = AttributedString()
    var start = value.startIndex
    for range in PublicNewsSearch.ranges(in: value, terms: terms) {
      styled += AttributedString(String(value[start..<range.lowerBound]))
      var match = AttributedString(String(value[range]))
      match.backgroundColor = .yellow.opacity(0.35)
      styled += match
      start = range.upperBound
    }
    styled += AttributedString(String(value[start...]))
    return Text(styled)
  }

  private func runSearch(_ query: PublicNewsSearchRequest) async {
    guard resolvedQuery != query || result?.articles.isEmpty != false else { return }
    hits = []
    result = nil
    searching = !PublicNewsSearch.terms(query.text).isEmpty
    guard searching else { return }
    do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
    let articles = archive.eligibleArticles
    let worker = Task.detached(priority: .userInitiated) {
      try PublicNewsSearch.index(query, articles: articles, now: Date())
    }
    do {
      let next = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
      guard !Task.isCancelled, query == request else { return }
      let eligible = PublicNewsSearchResult(
        articles: next.articles.filter { !archive.notRelevantIDs.contains($0.id) }, terms: next.terms
      )
      resolvedQuery = query
      result = eligible
      hits = eligible.page(start: 0)
      searching = false
    } catch {
      if !Task.isCancelled, query == request { searching = false }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
