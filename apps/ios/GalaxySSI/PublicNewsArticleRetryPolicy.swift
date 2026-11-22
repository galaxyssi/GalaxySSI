import Foundation

enum PublicNewsArticleRetryPolicy {
  static let revision = 2
  static let maximumFailures = 4
  static func exhausted(attemptsBeforeClaim: Int) -> Bool { attemptsBeforeClaim >= 3 }
  static func delay(attemptsBeforeClaim: Int, error: String) -> TimeInterval {
    let base: TimeInterval = error.hasPrefix("article_") &&
      !["article_translation_timeout", "article_translation_model_pending"].contains(error) ? 1_800 : 60
    return min(14_400, base * pow(2, Double(min(3, max(0, attemptsBeforeClaim)))))
  }
  static func key(_ articleID: String) -> String { PublicNewsSpeechBookmark.key(for: articleID) }
}

enum PublicNewsArticleRetryCleanup {
  static func prepare(file: URL, backlog: PublicNewsBacklogStore, bodies: PublicNewsBodyStore) async throws -> PublicNewsRowArchive.Loaded? {
    var state = try await backlog.load()
    if state.retryPolicyRevision == nil {
      let ready = await bodies.completedIDs(Set(state.entries.keys))
      try await backlog.prepareRetryPolicy(cachedReady: ready)
      state = try await backlog.load()
    }
    let pending = state.pendingCleanupKeys
    if !pending.isEmpty {
      let preserved = try await bodies.discardUnpublished(pending, preserving: state.publishedKeys) { keys in
        try PublicNewsRowArchive.discardUnpublished(legacyURL: file, keys: keys)
      }
      let saved = try PublicNewsRowArchive.load(legacyURL: file)
      let preservedIDs = Set(saved.snapshot.articles.filter { preserved.contains(PublicNewsArticleRetryPolicy.key($0.id)) }.map(\.id))
      try await backlog.acknowledgeCleanup(pending, preservedIDs: preservedIDs)
      return saved
    }
    return nil
  }
}

struct PublicNewsArticleAttemptFailure: Error { let reason: String }
