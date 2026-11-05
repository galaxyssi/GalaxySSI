import Combine
import Foundation

@MainActor
final class PublicNewsBacklogWorker: ObservableObject {
  static let shared = PublicNewsBacklogWorker()

  @Published private(set) var counts = PublicNewsBacklogLedger.Counts()
  @Published private(set) var running = false
  @Published private(set) var stoppedForResources = false
  @Published private(set) var storageFailed = false
  private var work: Task<Void, Never>?

  private enum Preparation {
    case cached(PublicNewsBodyCheckpoint)
    case html(String)
    case failed
  }

  func updateCounts(_ archive: PublicNewsArchive) async {
    guard !running else { return }
    let ids = Set(Self.eligible(archive).map(\.id))
    let cached = await PublicNewsBodyStore.shared.completedIDs(ids)
    guard !Task.isCancelled, !running else { return }
    do {
      let state = try await PublicNewsBacklogStore.shared.load()
      counts = state.counts(articleIDs: ids, cachedReady: cached, now: Date())
    } catch {
      storageFailed = true
    }
  }

  func start(_ archive: PublicNewsArchive) {
    guard work == nil else { return }
    storageFailed = false
    stoppedForResources = false
    running = true
    work = Task { @MainActor in
      await run(archive)
      work = nil
      running = false
      Task { @MainActor in await updateCounts(archive) }
    }
  }

  func cancel() { work?.cancel() }

  private func run(_ archive: PublicNewsArchive) async {
    let candidates = Self.eligible(archive)
    let ids = Set(candidates.map(\.id))
    let deadline = ProcessInfo.processInfo.systemUptime + 120
    var cachedReady = await PublicNewsBodyStore.shared.completedIDs(ids)
    var attempted = 0
    let ledger = PublicNewsBacklogStore.shared
    do {
      try await ledger.reconcileReady(ids, cached: cachedReady)
      while !Task.isCancelled && attempted < 12 && ProcessInfo.processInfo.systemUptime < deadline {
        guard Self.canWork else { stoppedForResources = true; return }
        let retained = Set(archive.articles.map(\.id))
        let available = candidates.filter { retained.contains($0.id) && !archive.notRelevantIDs.contains($0.id) }
        let claims = try await ledger.claim(available, count: min(2, 12 - attempted), now: Date())
        if claims.isEmpty { return }
        counts = try await ledger.load().counts(articleIDs: ids, cachedReady: cachedReady, now: Date())
        attempted += claims.count
        let byID = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let prepared = await withTaskGroup(of: (String, Preparation).self) { group in
          for claim in claims {
            guard let article = byID[claim.articleID] else { continue }
            group.addTask {
              if let cached = await PublicNewsBodyStore.shared.load(article.id) { return (article.id, .cached(cached)) }
              do { return (article.id, .html(try await PublicNewsArticleBody.fetchHTML(article.url))) }
              catch { return (article.id, .failed) }
            }
          }
          var results = [String: Preparation]()
          for await (id, result) in group { results[id] = result }
          return results
        }
        if !Self.canWork { stoppedForResources = true }
        var stop = false
        for claim in claims {
          let canContinue = !stop && !Task.isCancelled && Self.canWork &&
            ProcessInfo.processInfo.systemUptime < deadline && !archive.notRelevantIDs.contains(claim.articleID) &&
            archive.articles.contains { $0.id == claim.articleID }
          var outcome = PublicNewsBacklogLedger.Outcome.released
          if canContinue {
            do {
              let checkpoint: PublicNewsBodyCheckpoint
              switch prepared[claim.articleID] ?? .failed {
              case .cached(let saved): checkpoint = saved
              case .html(let html):
                let body = try await PublicNewsArticleBody.extract(html, articleURL: byID[claim.articleID]?.url)
                checkpoint = try await PublicNewsBodyStore.shared.install(
                  body, articleID: claim.articleID, retaining: Set(archive.articles.map(\.id))
                )
              case .failed: throw PublicNewsArticleBodyError.incompleteSource
              }
              let final = try await PublicNewsTranslation.run(
                checkpoint, workClass: .background, deadlineUptime: deadline, progress: { _ in }
              )
              outcome = final.completed == nil ? .retry : .ready
              if final.completed != nil { cachedReady.insert(claim.articleID) }
            } catch is CancellationError {
              stop = true
            } catch PublicNewsArticleBodyError.modelUnavailable {
              stoppedForResources = true
              stop = true
            } catch is LocalModelBackgroundDeferredError {
              stoppedForResources = true
              stop = true
            } catch is LocalModelASRPriorityError {
              stoppedForResources = true
              stop = true
            } catch {
              outcome = Task.isCancelled ? .released : .retry
            }
          }
          try await ledger.finish(claim, outcome: outcome, now: Date())
          counts = try await ledger.load().counts(articleIDs: ids, cachedReady: cachedReady, now: Date())
        }
        if stop { return }
      }
    } catch {
      if !Task.isCancelled { storageFailed = true }
    }
  }

  private static func eligible(_ archive: PublicNewsArchive) -> [PublicNewsArticle] {
    archive.eligibleArticles.filter { PublicNewsArticleBody.supports($0.url) }
  }

  private static var canWork: Bool {
    let process = ProcessInfo.processInfo
    return !process.isLowPowerModeEnabled && process.thermalState != .serious && process.thermalState != .critical
  }
}
