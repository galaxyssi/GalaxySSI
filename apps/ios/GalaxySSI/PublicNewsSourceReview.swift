import Foundation

struct PublicNewsSourceReview: Codable, Equatable {
  let inputKey: String
  let sourceFingerprint: String
  let excerpts: [String]
  let reviewedAt: Date

  static func key(_ article: PublicNewsArticle) -> String {
    let fields = [article.id, article.title, article.summary]
    return PublicNewsSpeechBookmark.key(for: fields.map { "\($0.utf8.count):\($0)" }.joined())
  }

  static func current(for article: PublicNewsArticle) -> PublicNewsSourceReview? {
    guard let review = article.sourceReview, review.inputKey == key(article), !review.excerpts.isEmpty else { return nil }
    return review
  }

  static let prompt = AgentUntrustedEvidenceBoundary.enforceSystemPrompt("""
    Check whether the original publisher's page supports the feed headline. Use only the supplied page.
    Return JSON {"quotes":["a verbatim passage from the supplied page"]}. Select one or two distinct,
    directly supporting excerpts of 45 to 400 characters each. Do not paraphrase, introduce facts, or
    use tools. Return {"quotes":[]} if the page does not support the headline.
    """)

  static func passages(_ source: PublicNewsOriginalBody) -> [String] {
    var left = 6_000
    return source.paragraphs.prefix(20).compactMap { paragraph in
      let text = String(paragraph.prefix(max(0, left)))
      left -= text.count
      return text.count >= 45 ? text : nil
    }
  }

  static func accept(_ response: String, article: PublicNewsArticle, source: PublicNewsOriginalBody,
                     now: Date) -> PublicNewsSourceReview? {
    struct Result: Decodable { let quotes: [String] }
    guard response.utf8.count <= 8_192,
          let result = try? JSONDecoder().decode(Result.self, from: Data(response.utf8)),
          (1...2).contains(result.quotes.count) else { return nil }
    let quotes = result.quotes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let captured = passages(source)
    guard Set(quotes).count == quotes.count, quotes.allSatisfy({ quote in
      (45...400).contains(quote.count) && captured.contains { $0.range(of: quote, options: .literal) != nil }
    }) else { return nil }
    return .init(inputKey: key(article), sourceFingerprint: source.fingerprint, excerpts: quotes, reviewedAt: now)
  }
}

@MainActor
final class PublicNewsSourceReviewWorker {
  static let shared = PublicNewsSourceReviewWorker()
  static let preferenceKey = "publicNews.reviewOriginalSources"
  private var running = false
  private let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
    .appendingPathComponent("public-news-source-review-retry.json")

  static func allowed(_ settings: GlobalAgentSettings) -> Bool {
    settings.enabled && settings.proactiveInsightsEnabled && settings.autonomousResearchEnabled
  }

  func run(archive: PublicNewsArchive, store: GalaxySSIStore) async {
    while running && !Task.isCancelled { try? await Task.sleep(nanoseconds: 500_000_000) }
    guard !Task.isCancelled, let file else { return }
    running = true
    defer { running = false }
    do {
      var ledger = try load(file)
      while enabled(store) && !Task.isCancelled {
        let profile = LocalModelRuntimeSettings.selectedProfile()
        let runtime = LocalModelInferenceRuntime.shared
        guard AgentIOSBackgroundLoad.current().deferSeconds == 0, runtime.readyForBackground(profile: profile) else {
          try await Task.sleep(nanoseconds: 30_000_000_000)
          continue
        }
        let now = Date()
        let candidates = archive.eligibleArticles.filter {
          PublicNewsSourceReview.current(for: $0) == nil && PublicNewsArticleBody.supports($0.url) &&
            now.timeIntervalSince($0.publishedAt ?? $0.discoveredAt) <= 7 * 86_400
        }
        if let article = candidates.first(where: { ledger.ready(PublicNewsSourceReview.key($0), at: now) }) {
          let key = PublicNewsSourceReview.key(article)
          let lease = ledger.claim([key], at: now, retaining: Set(candidates.map(PublicNewsSourceReview.key)))
          try persist(ledger, file)
          var reason: String?
          do {
            let original = try await PublicNewsArticleBody.load(article.url)
            try Task.checkCancellation()
            guard enabled(store), AgentIOSBackgroundLoad.current().deferSeconds == 0,
                  runtime.readyForBackground(profile: profile) else {
              throw LocalModelBackgroundDeferredError()
            }
            let input = [article.title, original.title] + PublicNewsSourceReview.passages(original)
            let prompt = AgentUntrustedEvidenceBoundary.wrapText(sourceType: "public_news_original",
              sourceId: key, content: input.joined(separator: "\n\n"))
            let runId = lease.uuidString
            let budget = GalaxySSIGlobalAutonomousBudgetRuntime.acquire(store: store, runId: runId,
              actionId: key, kind: .researchEvidence, resourceId: "ios:public-news-local",
              systemPrompt: PublicNewsSourceReview.prompt, prompt: prompt, nowMillis: GlobalRealtimeClock.nowMillis())
            if budget.granted {
              var response = ""
              defer {
                GalaxySSIGlobalAutonomousBudgetRuntime.complete(runId: runId, actionId: key, kind: .researchEvidence,
                  inputTokens: 0, outputTokens: 0, reportedCostMicros: 0, responseText: response,
                  nowMillis: GlobalRealtimeClock.nowMillis())
              }
              response = try await runtime.generateAsync(profile: profile, systemPrompt: PublicNewsSourceReview.prompt,
                userPrompt: prompt, maximumTokens: 640, temperature: 0, thinkingMode: .noThink, workClass: .background).text
              try Task.checkCancellation()
              if enabled(store), let review = PublicNewsSourceReview.accept(response, article: article, source: original,
                now: Date()), archive.storeSourceReview(review, articleID: article.id) {
                reason = nil
              } else {
                reason = "source_review_not_supported"
              }
            } else {
              reason = "source_review_budget_deferred"
            }
          } catch is CancellationError {
            reason = nil
          } catch {
            reason = Task.isCancelled ? nil : "source_review_retry"
          }
          ledger.finish(key, lease: lease, at: Date(), reason: reason)
          try persist(ledger, file)
        }
        try await Task.sleep(nanoseconds: 30_000_000_000)
      }
    } catch {
      // A review failure must not affect collection or the reader.
    }
  }

  private func enabled(_ store: GalaxySSIStore) -> Bool {
    UserDefaults.standard.bool(forKey: Self.preferenceKey) && Self.allowed(store.globalAgentSettings)
  }

  private func load(_ file: URL) throws -> PublicNewsHeadlineRetryLedger {
    do { return try JSONDecoder().decode(PublicNewsHeadlineRetryLedger.self, from: Data(contentsOf: file)) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return PublicNewsHeadlineRetryLedger()
    }
  }

  private func persist(_ ledger: PublicNewsHeadlineRetryLedger, _ file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(ledger).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
