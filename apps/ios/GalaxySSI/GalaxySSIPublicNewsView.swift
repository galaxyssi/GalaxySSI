import SwiftUI

@MainActor
struct GalaxySSIPublicNewsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("publicNews.liveEnabled") private var liveNewsEnabled = false
  @AppStorage("publicNews.publisherDiscovery") private var publisherDiscovery = false
  @StateObject private var archive = PublicNewsArchive()
  @State private var filter = Filter.all
  @State private var refreshRequest = 0
  @State private var showHighlights = false
  @State private var showScience = false
  @State private var showHeadlineTranslation = false
  @State private var selected: PublicNewsArticle?
  @SceneStorage("publicNews.showSearch") private var showSearch = false

  private enum Filter: Hashable { case all, unread, saved }

  private var visibleArticles: [PublicNewsArticle] {
    switch filter {
    case .all: return archive.eligibleArticles
    case .unread: return archive.eligibleArticles.filter { !$0.read }
    case .saved: return archive.eligibleArticles.filter(\.saved)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("public_news_title", "Discoveries"),
        leading: { GalaxySSIBackButton() },
        trailing: {
          Menu {
            Button { showSearch = true } label: {
              Label(t("public_news_search", "Search news"), systemImage: "magnifyingglass")
            }
            Button { showHighlights = true } label: {
              Label(t("public_news_highlights", "Highlights"), systemImage: "sparkles")
            }
            Button { refreshRequest += 1 } label: {
              Label(t("public_news_refresh", "Refresh news"), systemImage: "arrow.clockwise")
            }
            .disabled(archive.refreshing)
            Button { showScience = true } label: {
              Label(t("science_title", "Life sciences"), systemImage: "books.vertical")
            }
            Button { showHeadlineTranslation = true } label: {
              Label(t("public_news_headline_translate", "Translate headlines"), systemImage: "character.bubble")
            }
            Toggle(t("public_news_live", "Live Hacker News"), isOn: $liveNewsEnabled)
            Toggle(t("public_news_learn_publishers", "Discover publisher feeds"), isOn: $publisherDiscovery)
              .disabled(archive.refreshing)
          } label: {
            Image(systemName: "ellipsis").frame(width: 40, height: 44)
          }
          .accessibilityLabel(t("public_news_actions", "News actions"))
        }
      )
      Picker(t("public_news_filter", "News filter"), selection: $filter) {
        Text(t("public_news_all", "All")).tag(Filter.all)
        Text(t("public_news_unread", "Unread")).tag(Filter.unread)
        Text(t("public_news_saved", "Saved")).tag(Filter.saved)
      }
      .pickerStyle(.segmented)
      .padding(12)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if archive.storageFailed {
            status(t("public_news_storage_failed", "The local news archive could not be accessed."))
          }
          if archive.refreshIncomplete {
            status(t("public_news_refresh_incomplete", "Some publishers could not be refreshed."))
          }
          if visibleArticles.isEmpty && !archive.refreshing {
            status(t("public_news_empty", "No articles"))
          }
          ForEach(visibleArticles) { article in
            HStack(spacing: 8) {
              GalaxySSIPublicNewsCover(article: article)
              GalaxySSIPublicNewsHeadline(archive: archive, article: article, onOpen: {
                selected = article
                archive.markRead(article.id)
              }) {
                Text(article.displayTitle)
                  .font(.body.weight(article.read ? .regular : .semibold))
                  .foregroundColor(.galaxySSITextPrimary)
                  .lineLimit(3)
              } detail: {
                GalaxySSIPublicNewsByline(article: article)
              }
              .padding(.vertical, 12)
              GalaxySSIPublicNewsBookmark(archive: archive, article: article)
            }
            .padding(.leading, 12)
            .background(Color.galaxySSISurface)
            Divider().padding(.leading, 12)
          }
        }
        .padding(.horizontal, 12)
      }
      .overlay(alignment: .top) {
        if archive.refreshing && archive.articles.isEmpty { ProgressView().padding() }
      }
      .refreshable { await archive.refresh(force: true, learnPublishers: publisherDiscovery) }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .background {
      NavigationLink(destination: GalaxySSIPublicNewsSearchView(archive: archive), isActive: $showSearch) {
        EmptyView()
      }
      .hidden()
    }
    .background {
      NavigationLink(destination: GalaxySSIPublicNewsHighlightsView(archive: archive), isActive: $showHighlights) {
        EmptyView()
      }
      .hidden()
    }
    .navigationBarHidden(true)
    .task(id: refreshRequest) { await archive.refresh(force: refreshRequest != 0, learnPublishers: publisherDiscovery) }
    .task(id: liveNewsEnabled && scenePhase == .active) {
      if liveNewsEnabled && scenePhase == .active { await archive.collectLive() }
    }
    .sheet(item: $selected) { GalaxySSIPublicNewsReader(archive: archive, original: $0) }
    .sheet(isPresented: $showScience) {
      NavigationView { GalaxySSIScienceKnowledgeView() }
        .navigationViewStyle(.stack)
    }
    .sheet(isPresented: $showHeadlineTranslation) {
      NavigationView { GalaxySSINewsHeadlineTranslationView(archive: archive) }
        .navigationViewStyle(.stack)
    }
  }

  private func status(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .foregroundColor(.galaxySSITextSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIPublicNewsReader: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ObservedObject var archive: PublicNewsArchive
  let original: PublicNewsArticle

  var body: some View {
    let article = archive.articles.first { $0.id == original.id } ?? original
    return VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("public_news_article", "Article"),
        leading: {
          Button { dismiss() } label: {
            Image(systemName: "xmark").frame(width: 40, height: 44)
          }
          .accessibilityLabel(t("public_news_close", "Close article"))
        },
        trailing: { GalaxySSIPublicNewsBookmark(archive: archive, article: article) }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GalaxySSIPublicNewsHeadline(archive: archive, article: article, reader: true, onDismissArticle: {
            dismiss()
          }) {
            Text(article.displayTitle).font(.title2.weight(.semibold))
          } detail: {
            GalaxySSIPublicNewsByline(article: article)
          }
          if article.displayTitle != article.title, let translation = article.headlineTranslation {
            VStack(alignment: .leading, spacing: 4) {
              Text(article.title).textSelection(.enabled)
              Text(translation.provider == .apple
                ? t("public_news_headline_apple", "Translated with Apple Translation")
                : t("public_news_headline_local", "Translated by an on-device model"))
                .font(.caption)
            }
            .foregroundColor(.secondary)
          }
          if !article.summary.isEmpty {
            Text(article.summary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
          }
          GalaxySSIPublicNewsBodyView(article: article) { cover in
            archive.rememberCover(cover, articleID: article.id)
          }
          Link(destination: article.url) {
            Label(t("public_news_open_source", "Open publisher"), systemImage: "arrow.up.right")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

struct GalaxySSIPublicNewsByline: View {
  let article: PublicNewsArticle

  var body: some View {
    HStack(spacing: 6) {
      Text(article.publisher)
      if let published = article.publishedAt {
        Text("·").accessibilityHidden(true)
        Text(published, style: .date)
      }
    }
    .font(.caption)
    .foregroundColor(.galaxySSITextSecondary)
  }
}

@MainActor
struct GalaxySSIPublicNewsBookmark: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let archive: PublicNewsArchive
  let article: PublicNewsArticle

  var body: some View {
    Button { archive.toggleSaved(article.id) } label: {
      Image(systemName: article.saved ? "bookmark.fill" : "bookmark")
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(article.saved ? t("public_news_unsave", "Remove bookmark") : t("public_news_save", "Bookmark"))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
