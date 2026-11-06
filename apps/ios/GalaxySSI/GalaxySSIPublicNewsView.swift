import SwiftUI

@MainActor
struct GalaxySSIPublicNewsView: View {
  var initialArticleKey: String? = nil
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var store: GalaxySSIStore
  @AppStorage("publicNews.liveEnabled") private var liveNewsEnabled = false
  @AppStorage("publicNews.publisherDiscovery") private var publisherDiscovery = false
  @AppStorage("publicNews.automaticHeadlineTranslation") private var automaticHeadlineTranslation = false
  @AppStorage("publicNews.headlineTranslationRoute") private var headlineTranslationRoute = ""
  @StateObject private var archive = PublicNewsArchive()
  @ObservedObject private var automaticHeadlines = PublicNewsAutomaticHeadlineWorker.shared
  @ObservedObject private var speech = PublicNewsSpeechPlayback.shared
  @State private var speechCandidates: [String]?
  @State private var noDownloadedSpeechItems = false
  @State private var showBacklog = false
  @State private var filter = Filter.all
  @State private var refreshRequest = 0
  @State private var showHighlights = false
  @State private var showScience = false
  @State private var showHeadlineTranslation = false
  @State private var selected: PublicNewsArticle?
  @State private var didOpenInitialArticle = false
  @SceneStorage("publicNews.showSearch") private var showSearch = false

  private enum Filter: Hashable { case all, unread, saved }

  private var headlineWorkerEnabled: Bool {
    scenePhase == .active && !showHeadlineTranslation &&
      PublicNewsAutomaticHeadlinePolicy.enabled(automaticHeadlineTranslation, language: language)
  }

  private var headlineCloudRoutes: [GalaxySSIContact] {
    store.visibleContacts.filter {
      $0.deliveryMode == .cloudAPI && $0.selectedCloudModel != nil
    }
  }

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
            Button {
              noDownloadedSpeechItems = false
              speechCandidates = visibleArticles.map(\.id)
            } label: {
              Label(t("public_news_speech_read_downloaded", "Read downloaded articles"), systemImage: "waveform")
            }
            .disabled(visibleArticles.isEmpty || speechCandidates != nil || !store.voiceSettings.textToSpeechEnabled)
            Button { showSearch = true } label: {
              Label(t("public_news_search", "Search news"), systemImage: "magnifyingglass")
            }
            Button { showHighlights = true } label: {
              Label(t("public_news_highlights", "Highlights"), systemImage: "sparkles")
            }
            Button { showBacklog = true } label: {
              Label(t("public_news_backlog_title", "Article processing"), systemImage: "list.bullet.rectangle")
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
            Toggle(t("public_news_headline_automatic", "Automatically translate headlines"),
              isOn: $automaticHeadlineTranslation)
            if automaticHeadlineTranslation {
              Picker(t("public_news_headline_model", "Headline translation model"), selection: $headlineTranslationRoute) {
                Text(t("public_news_headline_on_device", "On-device model")).tag("")
                ForEach(headlineCloudRoutes) { contact in
                  Text(contact.displayName + " · " + (contact.selectedCloudModel?.displayName ?? "")).tag(contact.id)
                }
                if !headlineTranslationRoute.isEmpty && !headlineCloudRoutes.contains(where: { $0.id == headlineTranslationRoute }) {
                  Text(t("public_news_headline_waiting_model", "Waiting for model")).tag(headlineTranslationRoute)
                }
              }
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

      if speech.queue.current != nil {
        GalaxySSIPublicNewsSpeechControls(playback: speech, showTitle: true)
          .padding(.horizontal, 12)
        if speech.queue.phase == .failed {
          status(t("public_news_speech_failed", "Could not read the downloaded article."))
        }
      }
      if noDownloadedSpeechItems {
        status(t("public_news_speech_no_downloads", "No downloaded articles to read."))
      }
      if headlineWorkerEnabled, let message = headlineWorkerStatus { status(message) }

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
            .onAppear { automaticHeadlines.visible(article.id, true, archive: archive) }
            .onDisappear { automaticHeadlines.visible(article.id, false, archive: archive) }
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
    .task(id: "\(headlineWorkerEnabled):\(headlineTranslationRoute)") {
      automaticHeadlines.configure(enabled: headlineWorkerEnabled, route: headlineTranslationRoute,
        archive: archive, store: store)
    }
    .onChange(of: archive.articles) { _ in automaticHeadlines.wake() }
    .onChange(of: headlineCloudRoutes) { _ in automaticHeadlines.wake() }
    .onDisappear { automaticHeadlines.suspend(archive: archive, store: store) }
    .onAppear {
      guard let initialArticleKey, !didOpenInitialArticle else { return }
      didOpenInitialArticle = true
      archive.load()
      selected = archive.eligibleArticles.first { PublicNewsSpeechBookmark.key(for: $0.id) == initialArticleKey }
    }
    .task(id: refreshRequest) { await archive.refresh(force: refreshRequest != 0, learnPublishers: publisherDiscovery) }
    .task(id: speechCandidates) {
      guard let ids = speechCandidates else { return }
      let items = await PublicNewsBodyStore.shared.speechItems(articleIDs: ids)
      guard !Task.isCancelled, speechCandidates == ids else { return }
      speechCandidates = nil
      guard scenePhase == .active else { return }
      noDownloadedSpeechItems = items.isEmpty
      if !items.isEmpty {
        speech.play(items, settings: store.voiceSettings, languagePolicy: store.languagePolicy)
      }
    }
    .task(id: liveNewsEnabled && scenePhase == .active) {
      if liveNewsEnabled && scenePhase == .active { await archive.collectLive() }
    }
    .sheet(item: $selected) { GalaxySSIPublicNewsReader(archive: archive, original: $0) }
    .sheet(isPresented: $showBacklog) {
      NavigationView { GalaxySSIPublicNewsBacklogView(archive: archive) }
        .navigationViewStyle(.stack)
    }
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

  private var headlineWorkerStatus: String? {
    switch automaticHeadlines.status {
    case .off, .idle: return nil
    case .waitingModel: return t("public_news_headline_waiting_model", "Waiting for model")
    case .translating: return t("public_news_headline_working", "Translating headlines")
    case .deferred: return t("public_news_headline_auto_deferred", "Headline translation is waiting for device resources.")
    case .retrying: return t("public_news_headline_retrying", "Waiting to retry headline translation")
    case .storageFailed: return t("public_news_storage_failed", "The local news archive could not be accessed.")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIPublicNewsReader: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var coordinator: MessageCoordinator
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
              Text(headlineProvider(translation.provider))
                .font(.caption)
            }
            .foregroundColor(.secondary)
          }
          if !article.summary.isEmpty {
            Text(article.summary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
          }
          GalaxySSIPublicNewsBodyView(article: article, retainedArticleIDs: Set(archive.articles.map(\.id))) { cover in
            archive.rememberCover(cover, articleID: article.id)
          }
          Button {
            coordinator.voiceAppContexts.openVoice(.init(surface: .news,
              articleID: PublicNewsSpeechBookmark.key(for: article.id)))
          } label: {
            Label(t("voice_app_open_controls", "Voice controls"), systemImage: "waveform")
              .frame(minHeight: 44)
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

  private func headlineProvider(_ provider: PublicNewsHeadlineTranslation.Provider) -> String {
    switch provider {
    case .apple: return t("public_news_headline_apple", "Translated with Apple Translation")
    case .localModel: return t("public_news_headline_local", "Translated by an on-device model")
    case .cloud: return t("public_news_headline_cloud", "Translated by a configured cloud model")
    }
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
