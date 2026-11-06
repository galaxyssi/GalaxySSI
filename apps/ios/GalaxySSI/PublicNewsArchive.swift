import Combine
import Foundation

enum PublicNewsArchiveStorage {
  struct Snapshot: Codable {
    var articles: [PublicNewsArticle]
    var refreshedAt: Date?
    var pushCursor: PublicNewsPushCursor?
    var notRelevantIDs: Set<String>?
    var publisherState: PublicNewsPublisherState?
  }

  private struct Metadata: Codable {
    let unreadCountV1: Int
    let pageIndexOffset: Int?
  }

  private struct PageEntry: Decodable {
    let key: String
    let offset: Int
    let length: Int
    let read: Bool
    let saved: Bool
  }

  private struct LegacyMetadata: Decodable {
    struct Row: Decodable {
      let url: URL
      let read: Bool
    }

    let articles: [Row]
    let notRelevantIDs: Set<String>?
  }

  static func unreadCount(_ articles: [PublicNewsArticle], excluding hidden: Set<String>) -> Int {
    articles.reduce(into: 0) { count, article in
      if !article.read, !hidden.contains(article.id) { count += 1 }
    }
  }

  private static func readHeader(_ file: FileHandle) throws -> (Metadata, Int)? {
    let prefix = try file.read(upToCount: 128) ?? Data()
    guard let lineEnd = prefix.firstIndex(of: 0x0a), lineEnd > prefix.startIndex,
          prefix[prefix.index(before: lineEnd)] == 0x2c else { return nil }
    var header = Data(prefix[..<prefix.index(before: lineEnd)])
    header.append(0x7d)
    guard let metadata = try? JSONDecoder().decode(Metadata.self, from: header), metadata.unreadCountV1 >= 0 else { return nil }
    return (metadata, lineEnd + 1)
  }

  static func firstPage(from url: URL, filter: PublicNewsTimeline.Filter, anchor: String,
                        retaining: Set<String>) throws -> [PublicNewsArticle]? {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    guard let (metadata, start) = try readHeader(file), let indexOffset = metadata.pageIndexOffset, indexOffset > 0 else {
      return nil
    }
    let end = try file.seekToEnd()
    guard UInt64(start) < end, UInt64(indexOffset) < end - UInt64(start) else { return nil }
    let indexStart = UInt64(start) + UInt64(indexOffset)
    let indexSize = end - indexStart - 1
    guard indexSize <= 16 * 1024 * 1024 else { return nil }
    try file.seek(toOffset: indexStart)
    guard let indexData = try file.read(upToCount: Int(indexSize)), UInt64(indexData.count) == indexSize,
          try file.read(upToCount: 1)?.first == 0x7d else { return nil }
    let decoder = JSONDecoder()
    let index = try decoder.decode([PageEntry].self, from: indexData).filter {
      switch filter {
      case .all: return true
      case .unread: return !$0.read || retaining.contains($0.key)
      case .saved: return $0.saved
      }
    }
    let range = PublicNewsPageWindow.initialRange(count: index.count, anchor: index.firstIndex { $0.key == anchor })
    return try index[range].map { entry in
      guard entry.offset >= 0, entry.length > 0, entry.offset < indexOffset,
            entry.length <= indexOffset - entry.offset else { throw CocoaError(.fileReadCorruptFile) }
      try file.seek(toOffset: UInt64(start) + UInt64(entry.offset))
      guard let data = try file.read(upToCount: entry.length), data.count == entry.length else {
        throw CocoaError(.fileReadCorruptFile)
      }
      let article = try decoder.decode(PublicNewsArticle.self, from: data)
      guard PublicNewsSpeechBookmark.key(for: article.id) == entry.key, article.read == entry.read,
            article.saved == entry.saved else { throw CocoaError(.fileReadCorruptFile) }
      return article
    }
  }

  static func readUnreadCount(from url: URL, allowLegacy: Bool) throws -> Int? {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    if let (metadata, start) = try readHeader(file) {
      let end = try file.seekToEnd()
      if end > UInt64(start + 1) {
        try file.seek(toOffset: end - 1)
        if try file.read(upToCount: 1)?.first == 0x7d { return metadata.unreadCountV1 }
      }
    }
    // An unindexed legacy archive is only scanned on the caller's background queue.
    guard allowLegacy else { return nil }
    try file.seek(toOffset: 0)
    let metadata = try JSONDecoder().decode(LegacyMetadata.self, from: try file.readToEnd() ?? Data())
    let hidden = metadata.notRelevantIDs ?? []
    return metadata.articles.reduce(into: 0) { count, article in
      if !article.read, !hidden.contains(article.url.absoluteString) { count += 1 }
    }
  }

  static func readSnapshot(from url: URL) throws -> Snapshot? {
    do { return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url)) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return nil
    }
  }
}

@MainActor
final class PublicNewsArchive: ObservableObject {
  @Published private(set) var articles: [PublicNewsArticle] = []
  @Published private(set) var refreshing = false
  @Published private(set) var refreshIncomplete = false
  @Published private(set) var storageFailed = false
  @Published private(set) var notRelevantIDs: Set<String> = []
  @Published private(set) var loaded = false
  @Published private(set) var initialPage: [PublicNewsArticle]?
  private(set) var initialPageFilter: PublicNewsTimeline.Filter?

  private let fileURL: URL?
  private var refreshedAt: Date?
  private var revision: Int64 = 0
  private var unreadCount = 0
  private var pushCursor = PublicNewsPushCursor()
  private var publisherState = PublicNewsPublisherState()
  private var liveWake: AsyncStream<Void>.Continuation?

  private enum PollOutcome {
    case articles([PublicNewsArticle])
    case discussion
    case failed
  }

  var eligibleArticles: [PublicNewsArticle] { articles.filter { !notRelevantIDs.contains($0.id) } }

  var reminderUnreadCount: Int? {
    loaded && !storageFailed ? unreadCount : nil
  }

  nonisolated static var defaultFileURL: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first?.appendingPathComponent("public-news.json")
  }

  nonisolated static func readReminderUnreadCount(
    fileURL: URL? = PublicNewsArchive.defaultFileURL, allowLegacy: Bool = true
  ) -> Int? {
    guard let fileURL else { return nil }
    do {
      if let count = try PublicNewsRowArchive.unreadCount(legacyURL: fileURL) { return count }
      return try PublicNewsArchiveStorage.readUnreadCount(from: fileURL, allowLegacy: allowLegacy)
    }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return 0 }
    catch { return nil }
  }

  init(fileURL: URL? = PublicNewsArchive.defaultFileURL) {
    self.fileURL = fileURL
  }

  nonisolated static func readFirstPage(fileURL: URL, filter: PublicNewsTimeline.Filter, anchor: String,
                                        retaining: Set<String>) -> [PublicNewsArticle]? {
    do {
      if let page = try PublicNewsRowArchive.firstPage(legacyURL: fileURL, filter: filter, anchor: anchor, retaining: retaining) {
        return page
      }
      return try PublicNewsArchiveStorage.firstPage(from: fileURL, filter: filter, anchor: anchor, retaining: retaining)
    } catch { return nil }
  }

  func loadForReader(filter: PublicNewsTimeline.Filter, anchor: String, retaining: Set<String>) async {
    guard !loaded else { return }
    guard let fileURL else { storageFailed = true; return }
    initialPage = nil
    let preview = await Task.detached(priority: .userInitiated) {
      Self.readFirstPage(fileURL: fileURL, filter: filter, anchor: anchor, retaining: retaining)
    }.value
    guard !Task.isCancelled, !loaded else { return }
    initialPageFilter = filter
    initialPage = preview
    let result = await Task.detached(priority: .utility) {
      Result { try PublicNewsRowArchive.load(legacyURL: fileURL) }
    }.value
    guard !Task.isCancelled, !loaded else { return }
    switch result {
    case .success(let saved): install(saved)
    case .failure: storageFailed = true
    }
    initialPage = nil
  }

  func load() {
    guard !loaded else { return }
    guard let fileURL else { storageFailed = true; return }
    do { install(try PublicNewsRowArchive.load(legacyURL: fileURL)) }
    catch { storageFailed = true }
  }

  private func install(_ saved: PublicNewsRowArchive.Loaded) {
    let snapshot = saved.snapshot
    revision = saved.revision
    refreshedAt = snapshot.refreshedAt
    pushCursor = snapshot.pushCursor ?? PublicNewsPushCursor()
    publisherState = snapshot.publisherState ?? PublicNewsPublisherState()
    unreadCount = PublicNewsArchiveStorage.unreadCount(snapshot.articles, excluding: snapshot.notRelevantIDs ?? [])
    notRelevantIDs = snapshot.notRelevantIDs ?? []
    articles = snapshot.articles
    storageFailed = false
    loaded = true
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

  func markRead(_ ids: Set<String>) {
    var next = articles
    var changed = false
    for index in next.indices where !next[index].read && ids.contains(next[index].id) {
      next[index].read = true
      changed = true
    }
    if changed { save(next, refreshedAt: refreshedAt) }
  }

  @discardableResult
  func setSaved(_ id: String, to saved: Bool) -> Bool {
    guard let index = articles.firstIndex(where: { $0.id == id }),
          articles[index].saved != saved else { return false }
    var next = articles
    next[index].saved = saved
    return save(next, refreshedAt: refreshedAt)
  }

  func rememberCover(_ cover: URL, articleID: String) {
    update(articleID) { article in
      if article.coverURL == nil && PublicNewsImagePolicy.accepts(cover, for: article.url) { article.coverURL = cover }
    }
  }

  @discardableResult
  func storeHeadline(_ text: String, for id: String, source: String,
                     provider: PublicNewsHeadlineTranslation.Provider) -> Bool {
    guard let index = articles.firstIndex(where: { $0.id == id }),
          !notRelevantIDs.contains(id), articles[index].title == source,
          articles[index].headlineTranslation?.source != source,
          let validated = PublicNewsHeadlineTranslator.validate(text, source: source) else { return false }
    var next = articles
    next[index].headlineTranslation = .init(source: source, chinese: validated, provider: provider)
    return save(next, refreshedAt: refreshedAt)
  }

  @discardableResult
  func markNotRelevant(_ id: String) -> Bool {
    guard articles.contains(where: { $0.id == id }) else { return false }
    if notRelevantIDs.contains(id) { return true }
    return save(articles, refreshedAt: refreshedAt, feedback: notRelevantIDs.union([id]))
  }

  func collectLive() async {
    load()
    guard loaded, liveWake == nil, !Task.isCancelled else { return }
    let wakes = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { self.liveWake = $0 }
    defer { liveWake?.finish(); liveWake = nil }
    liveWake?.yield(())
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.receiveLiveEvents() }
      group.addTask { await self.drainLiveStories(wakes) }
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
      let wait = max(retry, AgentIOSBackgroundLoad.current().spacing) + Double.random(in: 0...1)
      do { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
      catch { return }
      retry = min(retry * 2, 300)
    }
  }

  private func acceptLiveEvent(_ event: PublicNewsSSEDecoder.Event) throws {
    try Task.checkCancellation()
    var next = pushCursor
    try next.accept(type: event.type, data: event.data, now: Date())
    let hasNewWork = !Set(next.pending.keys).subtracting(pushCursor.pending.keys).isEmpty
    if next != pushCursor, !save(articles, refreshedAt: refreshedAt, cursor: next) {
      throw PublicNewsPushError.unavailable
    }
    if hasNewWork { liveWake?.yield(()) }
  }

  private func drainLiveStories(_ wakes: AsyncStream<Void>) async {
    var timer: Task<Void, Never>?
    var nextFetchAt = Date.distantPast
    defer { timer?.cancel() }
    for await _ in wakes {
      guard !Task.isCancelled else { return }
      timer?.cancel()
      timer = nil
      let now = Date()
      if nextFetchAt <= now, let id = pushCursor.next(at: now) {
        do {
          let article = try await PublicNewsPushClient.fetchStory(id, now: now)
          try Task.checkCancellation()
          if pushCursor.pending[id] != nil {
            var nextArticles = articles
            if let article, !articles.contains(where: { $0.id == article.id }) {
              nextArticles = Self.merge(existing: articles, incoming: [article])
            }
            var next = pushCursor
            next.complete(id)
            _ = save(nextArticles, refreshedAt: refreshedAt, cursor: next)
          }
        } catch {
          if Task.isCancelled { return }
          var next = pushCursor
          next.deferItem(id, now: Date())
          _ = save(articles, refreshedAt: refreshedAt, cursor: next)
        }
        nextFetchAt = Date(timeIntervalSinceNow: max(storageFailed ? 3 : 1, AgentIOSBackgroundLoad.current().spacing))
      }
      guard let next = pushCursor.nextWake(at: Date()), let wake = liveWake else { continue }
      let delay = max(0.05, max(next, nextFetchAt).timeIntervalSinceNow)
      timer = Task {
        do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        catch { return }
        wake.yield(())
      }
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
    if !storageFailed, next == articles, refreshedAt == self.refreshedAt,
       (cursor ?? pushCursor) == pushCursor, (feedback ?? notRelevantIDs) == notRelevantIDs,
       (publishers ?? publisherState) == publisherState { return true }
    do {
      let count = PublicNewsArchiveStorage.unreadCount(next, excluding: feedback ?? notRelevantIDs)
      revision = try PublicNewsRowArchive.save(legacyURL: fileURL, revision: revision, previous: articles,
        previousHidden: notRelevantIDs, next: .init(
          articles: next, refreshedAt: refreshedAt, pushCursor: cursor ?? pushCursor,
          notRelevantIDs: feedback ?? notRelevantIDs, publisherState: publishers ?? publisherState
        ))
      unreadCount = count
      if articles != next { articles = next }
      self.refreshedAt = refreshedAt
      if let cursor { pushCursor = cursor }
      if let feedback { notRelevantIDs = feedback }
      if let publishers { publisherState = publishers }
      storageFailed = false
      return true
    } catch PublicNewsRowArchive.Failure.stale {
      if let latest = try? PublicNewsRowArchive.load(legacyURL: fileURL) { install(latest) }
      else { storageFailed = true }
      return false
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
        article.coverURL = article.coverURL ?? previous.coverURL
        if previous.title == article.title {
          article.headlineTranslation = previous.headlineTranslation
        }
        if let previousInterests = previous.interests {
          article.interests = (article.interests ?? []).union(previousInterests)
        }
        if article.summary.isEmpty { article.summary = previous.summary }
      }
      byID[article.id] = article
      if let identity = PublisherIdentity(article) { aliasIDs[identity, default: []].insert(article.id) }
    }
    return byID.values.sorted {
      $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate > $1.sortDate
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
