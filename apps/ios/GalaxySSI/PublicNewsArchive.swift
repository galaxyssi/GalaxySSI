import Combine
import Foundation

@MainActor
final class PublicNewsArchive: ObservableObject {
  @Published private(set) var articles: [PublicNewsArticle] = []
  @Published private(set) var refreshing = false
  @Published private(set) var refreshIncomplete = false
  @Published private(set) var storageFailed = false
  @Published private(set) var notRelevantIDs: Set<String> = []

  private struct Snapshot: Codable {
    var articles: [PublicNewsArticle]
    var refreshedAt: Date?
    var pushCursor: PublicNewsPushCursor?
    var notRelevantIDs: Set<String>?
    var publisherState: PublicNewsPublisherState?
  }

  private let fileURL: URL?
  private var refreshedAt: Date?
  private var loaded = false
  private var pushCursor = PublicNewsPushCursor()
  private var publisherState = PublicNewsPublisherState()

  private enum PollOutcome {
    case articles([PublicNewsArticle])
    case discussion
    case failed
  }

  var eligibleArticles: [PublicNewsArticle] { articles.filter { !notRelevantIDs.contains($0.id) } }

  init(fileURL: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    .first?.appendingPathComponent("public-news.json")) {
    self.fileURL = fileURL
  }

  func load() {
    guard !loaded else { return }
    guard let fileURL else { storageFailed = true; return }
    do {
      let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
      articles = snapshot.articles
      refreshedAt = snapshot.refreshedAt
      pushCursor = snapshot.pushCursor ?? PublicNewsPushCursor()
      notRelevantIDs = snapshot.notRelevantIDs ?? []
      publisherState = snapshot.publisherState ?? PublicNewsPublisherState()
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      // The archive is created after the first successful collection.
    } catch {
      storageFailed = true
      return
    }
    loaded = true
    storageFailed = false
  }

  func refresh(force: Bool = false, learnPublishers: Bool = false) async {
    load()
    guard loaded, !refreshing else { return }
    let now = Date()
    if !force, let refreshedAt, now.timeIntervalSince(refreshedAt) < 900 { return }
    refreshing = true
    refreshIncomplete = false
    defer { refreshing = false }

    var state = publisherState
    let probe = learnPublishers ? state.probeCandidate(in: eligibleArticles, now: now) : nil
    let sources = state.plan(now: now, enabled: learnPublishers, probe: probe != nil)
    let results = await withTaskGroup(of: (Int, PollOutcome).self) { group in
      for (index, source) in sources.enumerated() {
        group.addTask {
          do { return (index, .articles(try await PublicNewsFeedClient.fetch(source, now: now))) }
          catch PublicNewsFeedError.discussionFeed { return (index, .discussion) }
          catch { return (index, .failed) }
        }
      }
      var batches: [(Int, PollOutcome)] = []
      for await batch in group { batches.append(batch) }
      return batches.sorted { $0.0 < $1.0 }
    }
    guard !Task.isCancelled else { return }
    var received: [PublicNewsArticle] = []
    var successful = false
    for (index, result) in results {
      switch result {
      case .articles(let articles):
        received += articles
        successful = true
        state.recordPoll(sources[index], success: true, discussion: false, now: now)
      case .discussion:
        state.recordPoll(sources[index], success: false, discussion: true, now: now)
      case .failed:
        refreshIncomplete = true
        state.recordPoll(sources[index], success: false, discussion: false, now: now)
      }
    }
    let next = received.isEmpty ? articles : Self.merge(existing: articles, incoming: received)
    guard save(next, refreshedAt: successful ? now : refreshedAt, publishers: state), let probe else { return }
    do {
      let feeds = try await PublicNewsFeedClient.probe(probe.article.url)
      guard !Task.isCancelled else { return }
      state.learn(feeds, from: probe.article, host: probe.host, now: now)
      state.probeAfter[probe.host] = now.addingTimeInterval(7 * 86_400)
    } catch {
      guard !Task.isCancelled else { return }
      state.probeAfter[probe.host] = now.addingTimeInterval(3_600)
    }
    save(articles, refreshedAt: refreshedAt, publishers: state)
  }

  func markRead(_ id: String) {
    update(id) { $0.read = true }
  }

  func toggleSaved(_ id: String) {
    update(id) { $0.saved.toggle() }
  }

  @discardableResult
  func markNotRelevant(_ id: String) -> Bool {
    guard articles.contains(where: { $0.id == id }) else { return false }
    if notRelevantIDs.contains(id) { return true }
    return save(articles, refreshedAt: refreshedAt, feedback: notRelevantIDs.union([id]))
  }

  func collectLive() async {
    load()
    guard loaded, !Task.isCancelled else { return }
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.receiveLiveEvents() }
      group.addTask { await self.drainLiveStories() }
      await group.waitForAll()
    }
  }

  private func receiveLiveEvents() async {
    var retry: TimeInterval = 2.5
    while !Task.isCancelled {
      let started = ProcessInfo.processInfo.systemUptime
      do {
        try await PublicNewsPushClient.stream { event in
          try await self.acceptLiveEvent(event)
        }
      } catch {
        if Task.isCancelled { return }
      }
      if ProcessInfo.processInfo.systemUptime - started >= 30 { retry = 2.5 }
      do { try await Task.sleep(nanoseconds: UInt64((retry + Double.random(in: 0...1)) * 1_000_000_000)) }
      catch { return }
      retry = min(retry * 2, 300)
    }
  }

  private func acceptLiveEvent(_ event: PublicNewsSSEDecoder.Event) throws {
    try Task.checkCancellation()
    var next = pushCursor
    try next.accept(type: event.type, data: event.data, now: Date())
    if next != pushCursor, !save(articles, refreshedAt: refreshedAt, cursor: next) {
      throw PublicNewsPushError.unavailable
    }
  }

  private func drainLiveStories() async {
    while !Task.isCancelled {
      let now = Date()
      if let id = pushCursor.next(at: now) {
        do {
          let article = try await PublicNewsPushClient.fetchStory(id, now: now)
          try Task.checkCancellation()
          guard pushCursor.pending[id] != nil else { continue }
          var nextArticles = articles
          if let article, !articles.contains(where: { $0.id == article.id }) {
            nextArticles = Self.merge(existing: articles, incoming: [article])
          }
          var next = pushCursor
          next.complete(id)
          if save(nextArticles, refreshedAt: refreshedAt, cursor: next) {
            try await Task.sleep(nanoseconds: 250_000_000)
            continue
          }
        } catch {
          if Task.isCancelled { return }
          var next = pushCursor
          next.deferItem(id, now: Date())
          _ = save(articles, refreshedAt: refreshedAt, cursor: next)
        }
      }
      do { try await Task.sleep(nanoseconds: 3_000_000_000) }
      catch { return }
    }
  }

  private func update(_ id: String, change: (inout PublicNewsArticle) -> Void) {
    guard let index = articles.firstIndex(where: { $0.id == id }) else { return }
    var next = articles
    change(&next[index])
    guard next[index] != articles[index] else { return }
    save(next, refreshedAt: refreshedAt)
  }

  @discardableResult
  private func save(_ next: [PublicNewsArticle], refreshedAt: Date?,
                    cursor: PublicNewsPushCursor? = nil, feedback: Set<String>? = nil,
                    publishers: PublicNewsPublisherState? = nil) -> Bool {
    guard loaded, let fileURL else { return false }
    do {
      let data = try JSONEncoder().encode(Snapshot(
        articles: next, refreshedAt: refreshedAt, pushCursor: cursor ?? pushCursor,
        notRelevantIDs: feedback ?? notRelevantIDs, publisherState: publishers ?? publisherState
      ))
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      if articles != next { articles = next }
      self.refreshedAt = refreshedAt
      if let cursor { pushCursor = cursor }
      if let feedback { notRelevantIDs = feedback }
      if let publishers { publisherState = publishers }
      storageFailed = false
      return true
    } catch {
      storageFailed = true
      return false
    }
  }

  nonisolated static func merge(existing: [PublicNewsArticle], incoming: [PublicNewsArticle]) -> [PublicNewsArticle] {
    var byID = [String: PublicNewsArticle]()
    var aliasIDs = [PublisherIdentity: Set<String>]()
    for article in existing {
      byID[article.id] = article
      if let identity = PublisherIdentity(article) { aliasIDs[identity, default: []].insert(article.id) }
    }
    var seen = Set<String>()
    for var article in incoming {
      if byID[article.id] == nil, let identity = PublisherIdentity(article),
         let ids = aliasIDs[identity], ids.count == 1, let priorID = ids.first, let prior = byID[priorID],
         PublisherIdentity(prior) == identity, prior.url.host?.lowercased() != article.url.host?.lowercased(),
         prior.url.port == article.url.port {
        article.url = prior.url
        article.publisher = prior.publisher
        if !prior.summary.isEmpty { article.summary = prior.summary }
      }
      if !seen.insert(article.id).inserted {
        if let extra = article.interests, var current = byID[article.id] {
          current.interests = (current.interests ?? []).union(extra)
          byID[article.id] = current
        }
        continue
      }
      if let previous = byID[article.id] {
        article.read = previous.read
        article.saved = previous.saved
        article.discoveredAt = previous.discoveredAt
        article.publishedAt = article.publishedAt ?? previous.publishedAt
        if let previousInterests = previous.interests {
          article.interests = (article.interests ?? []).union(previousInterests)
        }
        if article.summary.isEmpty { article.summary = previous.summary }
      }
      byID[article.id] = article
      if let identity = PublisherIdentity(article) { aliasIDs[identity, default: []].insert(article.id) }
    }
    let ordered = byID.values.sorted {
      $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate > $1.sortDate
    }
    var remaining = 600
    return ordered.filter { article in
      if article.saved { return true }
      guard remaining > 0 else { return false }
      remaining -= 1
      return true
    }
  }

  private struct PublisherIdentity: Hashable {
    let host: String
    let path: String
    let query: String?
    let title: String

    init?(_ article: PublicNewsArticle) {
      guard let parts = URLComponents(url: article.url, resolvingAgainstBaseURL: false),
            parts.scheme == "https", parts.user == nil, parts.password == nil, parts.fragment == nil,
            parts.port == nil || parts.port == 443,
            let domain = PublicNewsPublisherDiscovery.canonicalHost(article.url), !article.title.isEmpty else { return nil }
      host = domain
      path = parts.percentEncodedPath
      query = parts.percentEncodedQuery
      title = article.title
    }
  }
}
