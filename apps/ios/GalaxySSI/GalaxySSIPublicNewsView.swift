import SwiftUI

@MainActor
struct GalaxySSIPublicNewsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("publicNews.liveEnabled") private var liveNewsEnabled = false
  @StateObject private var archive = PublicNewsArchive()
  @State private var filter = Filter.all
  @State private var refreshRequest = 0
  @State private var selected: PublicNewsArticle?

  private enum Filter: Hashable { case all, unread, saved }

  private var visibleArticles: [PublicNewsArticle] {
    switch filter {
    case .all: return archive.articles
    case .unread: return archive.articles.filter { !$0.read }
    case .saved: return archive.articles.filter(\.saved)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("public_news_title", "Discoveries"),
        leading: { GalaxySSIBackButton() },
        trailing: {
          Menu {
            Button { refreshRequest += 1 } label: {
              Label(t("public_news_refresh", "Refresh news"), systemImage: "arrow.clockwise")
            }
            .disabled(archive.refreshing)
            Toggle(t("public_news_live", "Live Hacker News"), isOn: $liveNewsEnabled)
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
              Button {
                selected = article
                archive.markRead(article.id)
              } label: {
                VStack(alignment: .leading, spacing: 6) {
                  Text(article.title)
                    .font(.body.weight(article.read ? .regular : .semibold))
                    .foregroundColor(.galaxySSITextPrimary)
                    .lineLimit(3)
                  byline(article)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              bookmark(article)
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
      .refreshable { await archive.refresh(force: true) }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .task(id: refreshRequest) { await archive.refresh(force: refreshRequest != 0) }
    .task(id: liveNewsEnabled && scenePhase == .active) {
      if liveNewsEnabled && scenePhase == .active { await archive.collectLive() }
    }
    .sheet(item: $selected) { article in reader(article) }
  }

  private func reader(_ original: PublicNewsArticle) -> some View {
    let article = archive.articles.first { $0.id == original.id } ?? original
    return VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("public_news_article", "Article"),
        leading: {
          Button { selected = nil } label: {
            Image(systemName: "xmark").frame(width: 40, height: 44)
          }
          .accessibilityLabel(t("public_news_close", "Close article"))
        },
        trailing: { bookmark(article) }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text(article.title).font(.title2.weight(.semibold)).textSelection(.enabled)
          byline(article)
          if !article.summary.isEmpty {
            Text(article.summary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
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

  private func byline(_ article: PublicNewsArticle) -> some View {
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

  private func bookmark(_ article: PublicNewsArticle) -> some View {
    Button { archive.toggleSaved(article.id) } label: {
      Image(systemName: article.saved ? "bookmark.fill" : "bookmark")
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(article.saved ? t("public_news_unsave", "Remove bookmark") : t("public_news_save", "Bookmark"))
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
