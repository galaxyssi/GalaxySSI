import Combine
import Foundation

@MainActor
final class PublicNewsArchive: ObservableObject {
  @Published private(set) var articles: [PublicNewsArticle] = []
  @Published private(set) var refreshing = false
  @Published private(set) var refreshIncomplete = false
  @Published private(set) var storageFailed = false

  private struct Snapshot: Codable {
    var articles: [PublicNewsArticle]
    var refreshedAt: Date?
  }

  private let fileURL: URL?
  private var refreshedAt: Date?
  private var loaded = false

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

  private func update(_ id: String, change: (inout PublicNewsArticle) -> Void) {
    guard let index = articles.firstIndex(where: { $0.id == id }) else { return }
    var next = articles
    change(&next[index])
    guard next[index] != articles[index] else { return }
    save(next, refreshedAt: refreshedAt)
  }

  private func save(_ next: [PublicNewsArticle], refreshedAt: Date?) {
    guard loaded, let fileURL else { return }
    do {
      let data = try JSONEncoder().encode(Snapshot(articles: next, refreshedAt: refreshedAt))
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      articles = next
      self.refreshedAt = refreshedAt
      storageFailed = false
    } catch {
      storageFailed = true
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
