import SwiftUI
import UIKit

private struct PublicNewsRowFrames: PreferenceKey {
  static var defaultValue: [String: CGRect] { [:] }

  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
  }
}

private struct PublicNewsReadableFrames: PreferenceKey {
  static var defaultValue: [String: CGRect] { [:] }

  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    PublicNewsRowFrames.reduce(value: &value, nextValue: nextValue)
  }
}

@MainActor
private struct PublicNewsScrollAccess: UIViewRepresentable {
  @MainActor
  final class Handle {
    weak var view: UIView?
    var frames: [String: CGRect] = [:]
    var readableFrames: [String: CGRect] = [:]

    var scrollView: UIScrollView? {
      var ancestor = view?.superview
      while let current = ancestor {
        if let scroll = current as? UIScrollView { return scroll }
        ancestor = current.superview
      }
      return nil
    }

    func restoreOffset(_ delta: CGFloat) {
      guard let scroll = scrollView else { return }
      let minY = -scroll.adjustedContentInset.top
      let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
      let y = min(maxY, max(minY, scroll.contentOffset.y + delta))
      scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
    }
  }

  let handle: Handle

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.isUserInteractionEnabled = false
    handle.view = view
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) { handle.view = uiView }
}

enum PublicNewsHeaderLayout {
  static let actionWidth: CGFloat = 40
  static let sidePadding: CGFloat = 16
  static let titleFontSize: CGFloat = 17
  static let countGap: CGFloat = 8
  static let actionGap: CGFloat = 4
  static let height: CGFloat = 56

  static func unreadWidth(container: CGFloat, title: CGFloat) -> CGFloat {
    let side = actionWidth + sidePadding
    let renderedTitle = min(max(0, title), max(0, container - 2 * side))
    return max(0, (container - renderedTitle) / 2 - side - countGap - actionGap)
  }

  static let glyphOffsets: [CGPoint] = [
    .init(x: 0, y: -7), .init(x: -7, y: 0), .zero, .init(x: 7, y: 0), .init(x: 0, y: 7)
  ]
}

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
  @State private var timeline = PublicNewsTimeline()
  @State private var pageWindow = PublicNewsPageWindow()
  @State private var scrollAccess = PublicNewsScrollAccess.Handle()
  @State private var scrollRequest: ScrollRequest?
  @State private var didRestoreTimeline = false
  @State private var expandedHeadline: PublicNewsArticle?
  @State private var bookmarkChange: BookmarkChange?
  @State private var refreshRequest = 0
  @State private var showHighlights = false
  @State private var showScience = false
  @State private var showHeadlineTranslation = false
  @State private var showFeedMenu = false
  @State private var showNewsSettings = false
  @State private var settingsAction: SettingsAction?
  @ScaledMetric(relativeTo: .body) private var menuRowHeight = 48.0
  @State private var selected: PublicNewsArticle?
  @State private var didOpenInitialArticle = false
  @SceneStorage("publicNews.showSearch") private var showSearch = false
  @SceneStorage("publicNews.timelineFilter") private var savedFilter = "all"
  @SceneStorage("publicNews.timelineTop") private var topKey = ""
  @SceneStorage("publicNews.timelineOffset") private var topOffset = 0.0
  @SceneStorage("publicNews.timelineExpanded") private var expandedKey = ""

  private typealias Filter = PublicNewsTimeline.Filter
  private enum SettingsAction: Equatable { case read, search, highlights, backlog, refresh, science, translate }
  private struct ScrollRequest: Equatable {
    let id: String
    var offset: CGFloat = 0
    var forceProxy = false
    var token = UUID()
  }
  private struct BookmarkChange: Equatable {
    let id: String
    let saved: Bool
    var token = UUID()
  }
  private static let viewport = "public-news-viewport"

  private var headlineWorkerEnabled: Bool {
    archive.loaded && scenePhase == .active && !showHeadlineTranslation &&
      PublicNewsAutomaticHeadlinePolicy.enabled(automaticHeadlineTranslation, language: language)
  }

  private var headlineCloudRoutes: [GalaxySSIContact] {
    store.visibleContacts.filter {
      $0.deliveryMode == .cloudAPI && $0.selectedCloudModel != nil
    }
  }

  private var activeFilter: Filter {
    didRestoreTimeline ? timeline.filter : (Filter(rawValue: savedFilter) ?? .all)
  }

  private var visibleArticles: [PublicNewsArticle] {
    guard archive.loaded else { return archive.initialPageFilter == activeFilter ? archive.initialPage ?? [] : [] }
    let byID = Dictionary(archive.eligibleArticles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return timeline.visibleIDs[pageWindow.clamped(to: timeline.visibleIDs.count)].compactMap { byID[$0] }
  }

  private var canTrackReading: Bool {
    scenePhase == .active && didRestoreTimeline && scrollRequest == nil && (archive.reminderUnreadCount ?? 0) > 0 &&
      !showFeedMenu && !showNewsSettings && !showSearch && !showHighlights &&
      !showBacklog && !showScience && !showHeadlineTranslation && selected == nil
  }

  var body: some View {
    let pageBackground = Color.galaxySSIPageBackground
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("public_news_title", "Following updates"),
        backgroundColor: pageBackground,
        leading: { GalaxySSIBackButton() },
        trailing: {
          Button { showFeedMenu.toggle() } label: {
            ZStack {
              ForEach(PublicNewsHeaderLayout.glyphOffsets.indices, id: \.self) { index in
                let offset = PublicNewsHeaderLayout.glyphOffsets[index]
                Circle().frame(width: 3, height: 3).offset(x: offset.x, y: offset.y)
              }
            }
            .foregroundColor(.galaxySSITextPrimary)
            .frame(width: PublicNewsHeaderLayout.actionWidth, height: 48)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(t("public_news_actions", "Filter and settings"))
          .accessibilityIdentifier("public-news-menu")
        }
      )
      .overlay {
        unreadHeaderCount
      }

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
      newsTimeline
    }
    .background(pageBackground.ignoresSafeArea())
    .accessibilityHidden(showFeedMenu)
    .overlay(alignment: .topTrailing) {
      if showFeedMenu { feedMenu }
    }
    .onChange(of: scenePhase) { if $0 != .active { showFeedMenu = false } }
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
    .onChange(of: archive.articles) { _ in
      guard archive.loaded else { return }
      updateTimeline()
      automaticHeadlines.wake()
    }
    .onChange(of: archive.notRelevantIDs) { _ in updateTimeline() }
    .onChange(of: archive.initialPage) { page in
      guard !archive.loaded, !didRestoreTimeline, !topKey.isEmpty,
            let article = page?.first(where: { PublicNewsSpeechBookmark.key(for: $0.id) == topKey }) else { return }
      scrollRequest = .init(id: article.id, offset: CGFloat(topOffset))
    }
    .onChange(of: headlineCloudRoutes) { _ in automaticHeadlines.wake() }
    .onDisappear { automaticHeadlines.suspend(archive: archive, store: store) }
    .task(id: savedFilter) {
      let filter = Filter(rawValue: savedFilter) ?? .all
      if !archive.loaded {
        await archive.loadForReader(filter: filter, anchor: topKey, retaining: Set([topKey, expandedKey]))
      }
      guard !Task.isCancelled, archive.loaded else { return }
      updateTimeline()
      automaticHeadlines.wake()
      guard let initialArticleKey, !didOpenInitialArticle else { return }
      didOpenInitialArticle = true
      selected = archive.eligibleArticles.first { PublicNewsSpeechBookmark.key(for: $0.id) == initialArticleKey }
    }
    .task(id: archive.loaded ? refreshRequest : nil) {
      guard archive.loaded else { return }
      await archive.refresh(force: refreshRequest != 0, learnPublishers: publisherDiscovery)
    }
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
    .task(id: archive.loaded && liveNewsEnabled && scenePhase == .active) {
      if archive.loaded && liveNewsEnabled && scenePhase == .active { await archive.collectLive() }
    }
    .sheet(isPresented: $showNewsSettings, onDismiss: performNewsSettingsAction) { newsSettings }
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

  private var newsTimeline: some View {
    GeometryReader { viewport in
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0).id("public-news-list-start")
            if archive.storageFailed {
              status(t("public_news_storage_failed", "The local news archive could not be accessed."))
            }
            if archive.refreshIncomplete {
              status(t("public_news_refresh_incomplete", "Some publishers could not be refreshed."))
            }
            if archive.loaded && visibleArticles.isEmpty && !archive.refreshing {
              status(t("public_news_empty", "No articles"))
            }
            ForEach(visibleArticles) { article in
              timelineRow(article)
                .background {
                  GeometryReader { row in
                    Color.clear.preference(key: PublicNewsRowFrames.self,
                      value: [article.id: row.frame(in: .named(Self.viewport))])
                  }
                }
                .id(article.id)
            }
          }
          .padding(.horizontal, 12)
          .background(PublicNewsScrollAccess(handle: scrollAccess))
        }
        .coordinateSpace(name: Self.viewport)
        .onPreferenceChange(PublicNewsReadableFrames.self) { frames in
          scrollAccess.readableFrames = frames
          let visible = frames.compactMap { id, frame in
            frame.maxY > 0 && frame.minY < viewport.size.height ? id : nil
          }
          automaticHeadlines.prioritizeVisible(Set(visible), archive: archive)
        }
        .onPreferenceChange(PublicNewsRowFrames.self) { frames in
          scrollAccess.frames = frames
          if let request = scrollRequest {
            applyOffset(request, frames: frames, height: viewport.size.height)
            return
          }
          guard didRestoreTimeline, let anchor = topRow(frames, height: viewport.size.height) else { return }
          let key = PublicNewsSpeechBookmark.key(for: anchor.id)
          let offset = Double(-anchor.frame.minY.rounded())
          if topKey != key { topKey = key }
          if topOffset != offset { topOffset = offset }
          extendPageIfNeeded(frames, height: viewport.size.height, anchor: anchor)
        }
        .task(id: scrollRequest) {
          guard let request = scrollRequest else { return }
          if !request.forceProxy, applyOffset(request, frames: scrollAccess.frames, height: viewport.size.height) { return }
          proxy.scrollTo(request.id, anchor: .top)
          // A removed row or a scroll clamped at the end may not report a new frame.
          try? await Task.sleep(nanoseconds: 350_000_000)
          if !Task.isCancelled, scrollRequest == request { scrollRequest = nil }
        }
        .task(id: canTrackReading ? timeline.filter : nil) {
          guard canTrackReading else { return }
          await trackReading()
        }
        .overlay(alignment: .top) {
          if visibleArticles.isEmpty && (!archive.loaded && !archive.storageFailed || archive.refreshing) {
            ProgressView().padding()
          }
        }
        .overlay(alignment: .bottom) {
          VStack(spacing: 4) {
            if headlineWorkerEnabled, let message = headlineWorkerStatus {
              Text(message)
                .font(.caption)
                .foregroundColor(.galaxySSITextSecondary)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
            }
            if !timeline.pendingIDs.isEmpty {
              Button {
                let anchor = topRow(scrollAccess.frames, height: viewport.size.height)
                revealArrivals()
                if let anchor {
                  scrollRequest = .init(id: anchor.id, offset: -anchor.frame.minY, forceProxy: true)
                }
                refreshRequest += 1
              } label: {
                Label(String(format: t("public_news_new_arrivals", "%d new updates"), timeline.pendingIDs.count),
                  systemImage: "arrow.up").frame(minHeight: 44)
              }
              .buttonStyle(.borderedProminent)
            }
            if let change = bookmarkChange {
              HStack {
                Text(change.saved ? t("public_news_bookmark_added", "Bookmark added") :
                  t("public_news_bookmark_removed", "Bookmark removed"))
                Button(t("public_news_bookmark_undo", "Undo")) {
                  if archive.setSaved(change.id, to: !change.saved) { bookmarkChange = nil }
                }
                .frame(minHeight: 44)
              }
              .padding(.horizontal, 12)
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
          }
          .padding(8)
        }
        .task(id: bookmarkChange) {
          guard let change = bookmarkChange else { return }
          try? await Task.sleep(nanoseconds: 4_000_000_000)
          if !Task.isCancelled, bookmarkChange == change { bookmarkChange = nil }
        }
        .refreshable {
          guard archive.loaded else { return }
          if !timeline.pendingIDs.isEmpty { revealArrivals() }
          await archive.refresh(force: true, learnPublishers: publisherDiscovery)
        }
      }
    }
  }

  private func topRow(_ frames: [String: CGRect], height: CGFloat) -> (id: String, frame: CGRect)? {
    frames.filter { $0.value.maxY > 0 && $0.value.minY < height }
      .min { $0.value.minY < $1.value.minY }.map { ($0.key, $0.value) }
  }

  private func extendPageIfNeeded(_ frames: [String: CGRect], height: CGFloat, anchor: (id: String, frame: CGRect)) {
    guard archive.loaded else { return }
    let ids = timeline.visibleIDs
    let range = pageWindow.clamped(to: ids.count)
    guard !range.isEmpty else { return }
    if range.lowerBound > 0, let first = frames[ids[range.lowerBound]], first.maxY > 0 {
      pageWindow.extend(older: false, count: ids.count)
      scrollRequest = .init(id: anchor.id, offset: -anchor.frame.minY, forceProxy: true)
    } else if range.upperBound < ids.count, let last = frames[ids[range.upperBound - 1]], last.minY < height {
      pageWindow.extend(older: true, count: ids.count)
    }
  }

  private func revealArrivals() {
    let previous = timeline.visibleIDs
    timeline.revealArrivals()
    pageWindow.reconcile(from: previous, to: timeline.visibleIDs)
    pageWindow.extend(older: false, count: timeline.visibleIDs.count)
  }

  private func trackReading() async {
    var dwell = PublicNewsReadDwell()
    var previousOffset: CGFloat?
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 250_000_000)
      guard !Task.isCancelled, canTrackReading else { return }
      guard let scroll = scrollAccess.scrollView else { continue }
      let offset = scroll.contentOffset.y
      let idle = previousOffset == offset && !scroll.isTracking && !scroll.isDragging && !scroll.isDecelerating
      previousOffset = offset
      let unread = Set(archive.eligibleArticles.lazy.filter { !$0.read }.map(\.id))
      let height = scroll.bounds.height
      let visible = Set(scrollAccess.readableFrames.compactMap { id, frame -> String? in
        let visibleHeight = max(0, min(frame.maxY, height) - max(frame.minY, 0))
        return unread.contains(id) && frame.height > 0 && visibleHeight >= frame.height * 0.85 ? id : nil
      })
      let ready = dwell.sample(idle ? visible : [], now: ProcessInfo.processInfo.systemUptime)
      if !ready.isEmpty { archive.markRead(ready) }
      if unread.isEmpty { return }
    }
  }

  @discardableResult
  private func applyOffset(_ request: ScrollRequest, frames: [String: CGRect], height: CGFloat) -> Bool {
    guard let frame = frames[request.id], frame.maxY > 0, frame.minY < height else { return false }
    scrollAccess.restoreOffset(frame.minY + min(request.offset, max(0, frame.height - 1)))
    scrollRequest = nil
    return true
  }

  private func updateTimeline() {
    guard archive.loaded else { return }
    let articles = archive.eligibleArticles
    if didRestoreTimeline {
      let previous = timeline.visibleIDs
      timeline.reconcile(articles)
      if previous != timeline.visibleIDs { pageWindow.reconcile(from: previous, to: timeline.visibleIDs) }
    } else {
      let keys = Set([topKey, expandedKey].filter { !$0.isEmpty })
      let retained = Set(articles.filter { keys.contains(PublicNewsSpeechBookmark.key(for: $0.id)) }.map(\.id))
      timeline.select(Filter(rawValue: savedFilter) ?? .all, articles: articles, retainingUnread: retained)
      guard !articles.isEmpty else { return }
      expandedHeadline = articles.first { PublicNewsSpeechBookmark.key(for: $0.id) == expandedKey }
      didRestoreTimeline = true
      let anchor = topKey.isEmpty ? nil : timeline.visibleIDs.first { PublicNewsSpeechBookmark.key(for: $0) == topKey }
      pageWindow.reset(timeline.visibleIDs, anchor: anchor)
      if let id = anchor {
        scrollRequest = .init(id: id, offset: CGFloat(topOffset))
      }
    }
  }

  private func selectFilter(_ filter: Filter) {
    guard activeFilter != filter else { return }
    didRestoreTimeline = true
    savedFilter = filter.rawValue
    topKey = ""
    topOffset = 0
    expandedKey = ""
    expandedHeadline = nil
    timeline.select(filter, articles: archive.eligibleArticles)
    pageWindow.reset(timeline.visibleIDs)
    scrollRequest = .init(id: "public-news-list-start")
  }

  private func timelineRow(_ article: PublicNewsArticle) -> some View {
    let key = PublicNewsSpeechBookmark.key(for: article.id)
    let expanded = expandedKey == key
    let presented = presentedHeadline(article, expanded: expanded)
    let reservesBilingualSpace = !expanded && (article.displayTitle != article.title ||
      (PublicNewsAutomaticHeadlinePolicy.enabled(automaticHeadlineTranslation, language: language) &&
        PublicNewsHeadlineTranslator.isEnglish(article.title)))
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        GalaxySSIPublicNewsCover(article: article)
        GalaxySSIPublicNewsHeadline(archive: archive, article: presented, expanded: expanded,
          reservesBilingualSpace: reservesBilingualSpace, onOpen: {
            expandedHeadline = expanded ? nil : article
            expandedKey = expanded ? "" : key
          }) {
          Text(presented.displayTitle)
            .font(.body.weight(.semibold))
            .foregroundColor(article.read ? .galaxySSITextSecondary : .galaxySSITextPrimary)
            .lineLimit(expanded ? nil : reservesBilingualSpace ? 2 : 3)
        } detail: {
          GalaxySSIPublicNewsByline(article: article)
        }
        .padding(.vertical, 12)
        GalaxySSIPublicNewsBookmark(archive: archive, article: article) { saved in
          bookmarkChange = .init(id: article.id, saved: saved)
        }
        .disabled(!archive.loaded)
      }
      .padding(.leading, 12)
      .background {
        GeometryReader { header in
          Color.clear.preference(key: PublicNewsReadableFrames.self,
            value: [article.id: header.frame(in: .named(Self.viewport))])
        }
      }
      if expanded {
        VStack(alignment: .leading, spacing: 8) {
          if !article.summary.isEmpty { Text(article.summary).textSelection(.enabled) }
          GalaxySSIPublicNewsBodyView(article: article, retainedArticleIDs: Set(archive.articles.map(\.id))) { cover in
            archive.rememberCover(cover, articleID: article.id)
          }
          .disabled(!archive.loaded)
          Button { selected = article } label: {
            Label(t("public_news_open_article", "Open article"), systemImage: "doc.text")
              .frame(minHeight: 44)
          }
          .disabled(!archive.loaded)
        }
        .padding(.horizontal, 12)
      }
      Divider().padding(.leading, 12)
    }
    .background(Color.galaxySSISurface)
  }

  private func presentedHeadline(_ article: PublicNewsArticle, expanded: Bool) -> PublicNewsArticle {
    guard expanded, let expandedHeadline, expandedHeadline.id == article.id,
          expandedHeadline.title == article.title else { return article }
    var presented = article
    presented.headlineTranslation = expandedHeadline.headlineTranslation
    return presented
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

  @ViewBuilder private var unreadHeaderCount: some View {
    if let count = archive.reminderUnreadCount, count > 0 {
      let label = String(format: t("public_news_header_unread", "%lld unread"), Int64(count))
      let title = t("public_news_title", "Following updates")
      let width = ceil((title as NSString).size(withAttributes: [
        .font: UIFont.boldSystemFont(ofSize: PublicNewsHeaderLayout.titleFontSize)
      ]).width) + 1
      GeometryReader { geometry in
        let available = PublicNewsHeaderLayout.unreadWidth(container: geometry.size.width, title: width)
        HStack {
          Spacer(minLength: 0)
          Text(label)
            .font(.caption2)
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(1)
            .frame(width: available, alignment: .leading)
            .clipped()
            .accessibilityLabel(Text(label))
        }
        .padding(.trailing, PublicNewsHeaderLayout.sidePadding + PublicNewsHeaderLayout.actionWidth + PublicNewsHeaderLayout.actionGap)
        .frame(height: geometry.size.height)
      }
      .allowsHitTesting(false)
    }
  }

  private var feedMenu: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topTrailing) {
        Color.clear.contentShape(Rectangle()).onTapGesture { showFeedMenu = false }
          .accessibilityHidden(true)
        ScrollView {
          VStack(spacing: 0) {
            ForEach(Filter.allCases, id: \.self) { option in
              let label = filterLabel(option)
              feedMenuRow(label.title, icon: label.icon, selected: activeFilter == option) {
                selectFilter(option)
                showFeedMenu = false
              }
            }
            Rectangle().fill(Color.galaxySSISeparator).frame(height: 1)
              .padding(.horizontal, 16).padding(.vertical, 4)
            feedMenuRow(t("public_news_settings", "Following settings"), icon: "gearshape", selected: false) {
              showFeedMenu = false
              showNewsSettings = true
            }
          }
          .padding(.vertical, 4)
        }
        .frame(width: min(242, max(0, geometry.size.width - 16)),
          height: min(menuRowHeight * 4 + 17, max(0, geometry.size.height - PublicNewsHeaderLayout.height - 10)))
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        .padding(.top, PublicNewsHeaderLayout.height + 2)
        .padding(.trailing, 8)
        .accessibilityAction(.escape) { showFeedMenu = false }
      }
    }
  }

  private func feedMenuRow(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon).frame(width: 22).accessibilityHidden(true)
        Text(title).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "checkmark").font(.body.weight(.semibold))
          .foregroundColor(.galaxySSIAccent).opacity(selected ? 1 : 0)
          .frame(width: 20).accessibilityHidden(true)
      }
      .foregroundColor(.galaxySSITextPrimary)
      .padding(.horizontal, 16)
      .padding(.vertical, 4)
      .frame(minHeight: menuRowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func filterLabel(_ option: Filter) -> (title: String, icon: String) {
    switch option {
    case .all: return (t("public_news_menu_all", "All updates"), "list.bullet.rectangle")
    case .unread: return (t("public_news_menu_unread", "Unread only"), "envelope")
    case .saved: return (t("public_news_menu_saved", "My saved items"), "bookmark")
    }
  }

  private var newsSettings: some View {
    NavigationView {
      Form {
        Section {
          Button { openAfterSettings(.read) } label: {
            Label(t("public_news_speech_read_downloaded", "Read downloaded articles"), systemImage: "waveform")
          }
          .disabled(timeline.visibleIDs.isEmpty || speechCandidates != nil || !store.voiceSettings.textToSpeechEnabled)
          Button { openAfterSettings(.search) } label: {
            Label(t("public_news_search", "Search news"), systemImage: "magnifyingglass")
          }
          Button { openAfterSettings(.highlights) } label: {
            Label(t("public_news_highlights", "Highlights"), systemImage: "sparkles")
          }
          Button { openAfterSettings(.backlog) } label: {
            Label(t("public_news_backlog_title", "Article processing"), systemImage: "list.bullet.rectangle")
          }
          Button { openAfterSettings(.refresh) } label: {
            Label(t("public_news_refresh", "Refresh news"), systemImage: "arrow.clockwise")
          }
          .disabled(archive.refreshing)
          Button { openAfterSettings(.science) } label: {
            Label(t("science_title", "Life sciences"), systemImage: "books.vertical")
          }
          Button { openAfterSettings(.translate) } label: {
            Label(t("public_news_headline_translate", "Translate headlines"), systemImage: "character.bubble")
          }
        }
        Section {
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
        }
      }
      .navigationTitle(t("public_news_settings", "Following settings"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("common_close", "Close")) { showNewsSettings = false }
        }
      }
    }
    .navigationViewStyle(.stack)
  }

  private func openAfterSettings(_ action: SettingsAction) {
    guard archive.loaded || action == .science else { return }
    settingsAction = action
    showNewsSettings = false
  }

  private func performNewsSettingsAction() {
    let action = settingsAction
    settingsAction = nil
    switch action {
    case .read:
      noDownloadedSpeechItems = false
      speechCandidates = timeline.visibleIDs
    case .search: showSearch = true
    case .highlights: showHighlights = true
    case .backlog: showBacklog = true
    case .refresh: refreshRequest += 1
    case .science: showScience = true
    case .translate: showHeadlineTranslation = true
    case nil: break
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
        title: t("public_news_title", "Following updates"),
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
  var onChanged: ((Bool) -> Void)? = nil

  var body: some View {
    Button {
      let saved = !article.saved
      if archive.setSaved(article.id, to: saved) { onChanged?(saved) }
    } label: {
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
