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
  }

  private let fileURL: URL?
  private var refreshedAt: Date?
  private var loaded = false
  private var pushCursor = PublicNewsPushCursor()

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
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      // The archive is created after the first successful collection.
    } catch {
      storageFailed = true
      return
    }
    loaded = true
    storageFailed = false
  }

  func refresh(force: Bool = false) async {
    load()
    guard loaded, !refreshing else { return }
    let now = Date()
    if !force, let refreshedAt, now.timeIntervalSince(refreshedAt) < 900 { return }
    refreshing = true
    refreshIncomplete = false
    defer { refreshing = false }

    let sources = PublicNewsSource.builtIn
    let results = await withTaskGroup(of: (Int, [PublicNewsArticle]?).self) { group in
      for (index, source) in sources.enumerated() {
        group.addTask { (index, try? await PublicNewsFeedClient.fetch(source, now: now)) }
      }
      var batches: [(Int, [PublicNewsArticle]?)] = []
      for await batch in group { batches.append(batch) }
      return batches.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
    }
    guard !Task.isCancelled else { return }
    refreshIncomplete = results.count != sources.count
    guard !results.isEmpty else { return }
    save(Self.merge(existing: articles, incoming: results.flatMap { $0 }), refreshedAt: now)
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
                    cursor: PublicNewsPushCursor? = nil, feedback: Set<String>? = nil) -> Bool {
    guard loaded, let fileURL else { return false }
    do {
      let data = try JSONEncoder().encode(Snapshot(
        articles: next, refreshedAt: refreshedAt, pushCursor: cursor ?? pushCursor,
        notRelevantIDs: feedback ?? notRelevantIDs
      ))
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      if articles != next { articles = next }
      self.refreshedAt = refreshedAt
      if let cursor { pushCursor = cursor }
      if let feedback { notRelevantIDs = feedback }
      storageFailed = false
      return true
    } catch {
      storageFailed = true
      return false
    }
  }

  nonisolated static func merge(existing: [PublicNewsArticle], incoming: [PublicNewsArticle]) -> [PublicNewsArticle] {
    var byID = [String: PublicNewsArticle]()
    for article in existing { byID[article.id] = article }
    var seen = Set<String>()
    for var article in incoming where seen.insert(article.id).inserted {
      if let previous = byID[article.id] {
        article.read = previous.read
        article.saved = previous.saved
        article.discoveredAt = previous.discoveredAt
        article.publishedAt = article.publishedAt ?? previous.publishedAt
        if article.summary.isEmpty { article.summary = previous.summary }
      }
      byID[article.id] = article
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
}
