import Foundation

struct PublicNewsBacklogLedger: Codable, Equatable {
  enum Lane: Int, CaseIterable { case recent, history, retry }
  enum Outcome { case ready, retry, released, failure(String) }

  struct Claim: Codable, Equatable {
    let articleID: String
    let token: UUID
    let expires: Date
  }

  struct Entry: Codable, Equatable {
    var failures = 0
    var retryAt: Date?
    var claim: Claim?
    var ready = false
    var everPublished: Bool?
    var stopped: Bool?
  }

  struct Counts: Equatable {
    var waiting = 0
    var processing = 0
    var retry = 0
    var ready = 0
  }

  private static let cycle: [Lane] = [.recent, .recent, .history, .retry]
  private(set) var nextLane = 0
  private(set) var entries: [String: Entry] = [:]
  private(set) var retryPolicyRevision: Int? = PublicNewsArticleRetryPolicy.revision
  private var pendingCleanup: Set<String>?
  var pendingCleanupKeys: Set<String> { pendingCleanup ?? [] }
  var publishedKeys: Set<String> {
    Set(entries.compactMap { $0.value.ready || $0.value.everPublished == true ? PublicNewsArticleRetryPolicy.key($0.key) : nil })
  }

  mutating func prepareRetryPolicy(cachedReady: Set<String>) {
    let upgrading = retryPolicyRevision == nil
    for (id, var entry) in entries {
      let published = entry.ready || entry.everPublished == true || cachedReady.contains(id)
      if published { entry.everPublished = true }
      if upgrading && entry.failures > 0 {
        if published { entry.stopped = true; entry.claim = nil; entry.retryAt = nil }
        else { discard(id); continue }
      }
      entries[id] = entry
    }
    retryPolicyRevision = PublicNewsArticleRetryPolicy.revision
  }
  mutating func acknowledgeCleanup(_ keys: Set<String>, preservedIDs: Set<String>) {
    pendingCleanup = pendingCleanupKeys.subtracting(keys)
    for id in preservedIDs {
      var entry = entries[id] ?? Entry(ready: true)
      entry.everPublished = true; entry.stopped = true; entry.claim = nil; entry.retryAt = nil
      entries[id] = entry
    }
  }
  private mutating func discard(_ id: String) {
    var pending = pendingCleanupKeys
    pending.insert(PublicNewsArticleRetryPolicy.key(id)); pendingCleanup = pending
    entries.removeValue(forKey: id)
  }

  func nextEligible(articleIDs: Set<String>, now: Date) -> Date? {
    articleIDs.compactMap { id -> Date? in
      guard !pendingCleanupKeys.contains(PublicNewsArticleRetryPolicy.key(id)) else { return nil }
      guard let entry = entries[id] else { return now }
      guard !entry.ready, entry.stopped != true else { return nil }
      return max(now, max(entry.claim?.expires ?? now, entry.retryAt ?? now))
    }.min()
  }

  mutating func reconcile(_ articleIDs: Set<String>, now: Date) {
    entries = entries.filter { articleIDs.contains($0.key) || $0.value.everPublished == true || $0.value.stopped == true }
    for id in Array(entries.keys) {
      if let claim = entries[id]?.claim, claim.expires <= now { entries[id]?.claim = nil }
    }
  }

  mutating func claim(_ articles: [PublicNewsArticle], now: Date) -> Claim? {
    let oldestFirst = articles.sorted {
      $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate < $1.sortDate
    }
    func eligible(_ article: PublicNewsArticle, retry: Bool) -> Bool {
      guard !pendingCleanupKeys.contains(PublicNewsArticleRetryPolicy.key(article.id)) else { return false }
      guard let entry = entries[article.id] else { return !retry }
      return !entry.ready && entry.stopped != true && (entry.claim?.expires ?? .distantPast) <= now &&
        (entry.retryAt ?? .distantPast) <= now && (entry.failures > 0) == retry
    }
    let start = max(0, nextLane) % Self.cycle.count
    for offset in 0..<Self.cycle.count {
      let slot = (start + offset) % Self.cycle.count
      let article: PublicNewsArticle?
      switch Self.cycle[slot] {
      case .recent: article = oldestFirst.reversed().first { eligible($0, retry: false) }
      case .history: article = oldestFirst.first { eligible($0, retry: false) }
      case .retry:
        article = oldestFirst.filter { eligible($0, retry: true) }.min {
          (entries[$0.id]?.retryAt ?? .distantPast) < (entries[$1.id]?.retryAt ?? .distantPast)
        }
      }
      guard let article else { continue }
      let claim = Claim(articleID: article.id, token: UUID(), expires: now.addingTimeInterval(180))
      entries[article.id, default: Entry()].claim = claim
      nextLane = (slot + 1) % Self.cycle.count
      return claim
    }
    return nil
  }

  mutating func finish(_ claim: Claim, outcome: Outcome, now: Date) {
    guard var entry = entries[claim.articleID], entry.claim?.token == claim.token else { return }
    entry.claim = nil
    switch outcome {
    case .ready:
      entry.ready = true
      entry.everPublished = true; entry.stopped = nil
      entry.retryAt = nil; entry.failures = 0
    case .retry, .failure:
      let reason: String
      if case .failure(let message) = outcome { reason = message } else { reason = "article_extraction_failed" }
      let attempts = max(0, entry.failures)
      entry.failures = min(PublicNewsArticleRetryPolicy.maximumFailures, attempts + 1)
      if PublicNewsArticleRetryPolicy.exhausted(attemptsBeforeClaim: attempts) {
        if entry.everPublished == true || entry.ready { entry.stopped = true; entry.retryAt = nil }
        else { discard(claim.articleID); return }
      } else {
        entry.retryAt = now.addingTimeInterval(PublicNewsArticleRetryPolicy.delay(attemptsBeforeClaim: attempts, error: reason))
      }
    case .released:
      break
    }
    entries[claim.articleID] = entry
  }

  mutating func reconcileReady(_ articleIDs: Set<String>, cachedReady: Set<String>, now: Date) {
    reconcile(articleIDs, now: now)
    for id in articleIDs where entries[id]?.claim == nil {
      if cachedReady.contains(id) {
        var entry = entries[id] ?? Entry()
        entry.ready = true; entry.everPublished = true; entry.retryAt = nil
        entries[id] = entry
      } else if entries[id]?.ready == true {
        entries[id]?.ready = false
      }
    }
  }

  func counts(articleIDs: Set<String>, cachedReady: Set<String>, now: Date) -> Counts {
    var result = Counts()
    for id in articleIDs {
      if cachedReady.contains(id) { result.ready += 1; continue }
      if pendingCleanupKeys.contains(PublicNewsArticleRetryPolicy.key(id)) || entries[id]?.stopped == true { continue }
      guard let entry = entries[id] else { result.waiting += 1; continue }
      if let claim = entry.claim, claim.expires > now { result.processing += 1 }
      else if entry.ready { result.waiting += 1 }
      else if entry.failures > 0 { result.retry += 1 }
      else { result.waiting += 1 }
    }
    return result
  }
}

actor PublicNewsBacklogStore {
  static let shared = PublicNewsBacklogStore()
  private let file: URL?

  init(file: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    .first?.appendingPathComponent("public-news-backlog.json")) {
    self.file = file
  }

  func claim(_ articles: [PublicNewsArticle], count: Int, now: Date) throws -> [PublicNewsBacklogLedger.Claim] {
    try Task.checkCancellation()
    var ledger = try load()
    ledger.reconcile(Set(articles.map(\.id)), now: now)
    var claims: [PublicNewsBacklogLedger.Claim] = []
    for _ in 0..<max(0, min(2, count)) {
      guard let next = ledger.claim(articles, now: now) else { break }
      claims.append(next)
    }
    try save(ledger)
    return claims
  }

  func reconcileReady(_ ids: Set<String>, cached: Set<String>) throws {
    try Task.checkCancellation()
    var ledger = try load()
    ledger.reconcileReady(ids, cachedReady: cached, now: Date())
    try save(ledger)
  }

  func finish(_ claim: PublicNewsBacklogLedger.Claim, outcome: PublicNewsBacklogLedger.Outcome, now: Date) throws {
    var ledger = try load()
    ledger.finish(claim, outcome: outcome, now: now)
    try save(ledger)
  }

  func load() throws -> PublicNewsBacklogLedger {
    guard let file else { throw PublicNewsArticleBodyError.incompleteSource }
    do {
      let ledger = try JSONDecoder().decode(PublicNewsBacklogLedger.self, from: Data(contentsOf: file))
      guard ledger.retryPolicyRevision == nil || ledger.retryPolicyRevision == PublicNewsArticleRetryPolicy.revision else {
        throw PublicNewsArticleBodyError.incompleteSource
      }
      return ledger
    }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return PublicNewsBacklogLedger()
    }
  }

  func prepareRetryPolicy(cachedReady: Set<String>) throws {
    var ledger = try load()
    let previous = ledger
    ledger.prepareRetryPolicy(cachedReady: cachedReady)
    if ledger != previous { try save(ledger) }
  }
  func acknowledgeCleanup(_ keys: Set<String>, preservedIDs: Set<String>) throws {
    var ledger = try load()
    ledger.acknowledgeCleanup(keys, preservedIDs: preservedIDs)
    try save(ledger)
  }

  private func save(_ ledger: PublicNewsBacklogLedger) throws {
    guard let file else { throw PublicNewsArticleBodyError.incompleteSource }
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(ledger)
    try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
