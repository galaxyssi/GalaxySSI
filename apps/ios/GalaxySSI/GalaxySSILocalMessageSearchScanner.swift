import Foundation

actor GalaxySSILocalMessageSearchScanner {
  typealias Search = GalaxySSILocalMessageSearch
  struct Batch { let hits: [Search.Hit]; let more: Bool }
  private let owner: String
  private let query: String
  private let archived: Bool
  private let conversations: AgentConversationDatabase
  private let messages: GalaxySSIChatHistoryDatabase
  private var peers: [Search.Source]
  private var conversationCursor: AgentConversationPageCursor?
  private var conversationSources: [Search.Source] = []
  private var conversationsDone = false
  private var source: Search.Source?
  private var cursor: GalaxySSIChatHistoryCursor?
  private var page: [ChatMessage] = []
  private var sourceDone = false

  init(owner: String, query: String, archived: Bool, peers: [Search.Source],
       conversations: AgentConversationDatabase, messages: GalaxySSIChatHistoryDatabase) {
    self.owner = owner; self.query = Search.query(query) ?? ""; self.archived = archived; self.peers = peers
    self.conversations = conversations; self.messages = messages
  }
  func next(limit: Int) throws -> Batch {
    guard !owner.isBlank, !query.isEmpty else { return Batch(hits: [], more: false) }
    var hits: [Search.Hit] = []
    while hits.count < min(max(1, limit), 24) {
      try Task.checkCancellation()
      if source == nil { source = try nextSource(); cursor = nil; page = []; sourceDone = false }
      guard let current = source else { return Batch(hits: hits, more: false) }
      if current.kind == .agent {
        guard let live = conversations.read(current.id), Search.ordinary(live),
          (live.status == .archived) == archived else { source = nil; continue }
      }
      if page.isEmpty {
        if sourceDone { source = nil; continue }
        let saved = try messages.localSearchPage(contactId: current.contactID, conversationId: current.conversationID, before: cursor)
        guard saved.nextCursor == nil || saved.nextCursor != cursor else { throw Search.Failure.unavailable }
        cursor = saved.nextCursor; sourceDone = !saved.hasMore
        page = Array(saved.messages.reversed())
        try Task.checkCancellation()
        if page.isEmpty { continue }
      }
      let row = page.removeFirst()
      if let hit = Search.hit(row, source: current, owner: owner, query: query) { hits.append(hit) }
    }
    return Batch(hits: hits, more: true)
  }
  private func nextSource() throws -> Search.Source? {
    while conversationSources.isEmpty && !conversationsDone {
      try Task.checkCancellation()
      let saved = try conversations.localSearchPage(status: archived ? .archived : .active, cursor: conversationCursor)
      guard saved.nextCursor == nil || saved.nextCursor != conversationCursor else { throw Search.Failure.unavailable }
      conversationCursor = saved.nextCursor; conversationsDone = !saved.hasMore
      conversationSources = saved.items.filter(Search.ordinary).map {
        Search.Source(kind: .agent, id: $0.id, title: $0.title, archived: archived)
      }
    }
    if !conversationSources.isEmpty { return conversationSources.removeFirst() }
    return peers.isEmpty ? nil : peers.removeFirst()
  }

  nonisolated static func context(_ hit: Search.Hit, query: String, conversations: AgentConversationDatabase,
      messages: GalaxySSIChatHistoryDatabase, older: GalaxySSIChatHistoryCursor? = nil,
      newer: GalaxySSIChatHistoryCursor? = nil) throws -> Search.Context {
    try Task.checkCancellation()
    if hit.source.kind == .agent {
      guard let session = conversations.read(hit.source.id), Search.ordinary(session),
        (session.status == .archived) == hit.source.archived else { throw Search.Failure.unavailable }
    }
    guard let exact = messages.message(id: hit.message), GalaxySSIChatHistoryCursor(exact) == hit.cursor,
      Search.hit(exact, source: hit.source, owner: hit.owner, query: query) != nil else { throw Search.Failure.unavailable }
    let before = try messages.localSearchPage(contactId: hit.source.contactID, conversationId: hit.source.conversationID,
      before: older ?? (newer == nil ? hit.cursor : nil), after: newer, pageSize: older == nil && newer == nil ? 12 : 24)
    if older != nil || newer != nil {
      let lines = before.messages.compactMap { Search.line($0, source: hit.source) }
      return .init(lines: lines, older: older != nil ? before.nextCursor : lines.first.flatMap { line in
        before.messages.first(where: { $0.id == line.id }).map(GalaxySSIChatHistoryCursor.init)
      }, newer: newer != nil ? before.nextCursor : lines.last.flatMap { line in
        before.messages.first(where: { $0.id == line.id }).map(GalaxySSIChatHistoryCursor.init)
      })
    }
    let after = try messages.localSearchPage(contactId: hit.source.contactID, conversationId: hit.source.conversationID,
      after: hit.cursor, pageSize: 12)
    let rows = before.messages + [exact] + after.messages
    let lines = rows.compactMap { Search.line($0, source: hit.source) }
    guard lines.contains(where: { $0.id == hit.message }) else { throw Search.Failure.unavailable }
    return .init(lines: lines,
      older: before.hasMore ? before.messages.first.map(GalaxySSIChatHistoryCursor.init) : nil,
      newer: after.hasMore ? after.messages.last.map(GalaxySSIChatHistoryCursor.init) : nil)
  }
}

extension GalaxySSILocalMessageSearch {
  @MainActor
  static func allowed(_ source: Source, store: GalaxySSIStore) -> Bool {
    guard store.canReadAgentTranscript, store.canRestoreMessageViewport else { return false }
    if source.kind == .peer {
      return store.contact(id: source.id).flatMap { peer($0, archived: source.archived) } == source
    }
    guard let session = store.agentConversationDatabase.read(source.id) else { return false }
    return ordinary(session) && (session.status == .archived) == source.archived
  }
}
