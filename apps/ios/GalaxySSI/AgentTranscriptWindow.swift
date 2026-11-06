import Combine
import Foundation

@MainActor
final class AgentTranscriptWindow: ObservableObject {
  struct Owner: Equatable {
    let conversationID: String
    let generation = UUID()
  }

  struct Snapshot: Equatable {
    var owner: Owner?
    var messages: [ChatMessage] = []
    var hasMore = false
    var loadedLimit = 0
    var prependAnchor: UUID?
  }

  typealias Loader = (String, Int) async -> GalaxySSIChatHistoryPage?
  @Published private(set) var snapshot = Snapshot()
  private var loader: Loader?
  private var work: Task<Void, Never>?
  private var refreshPending = false
  private var requestedLimit = 0
  private var prependAnchor: UUID?

  func activate(_ conversationID: String, pageSize: Int, loader: @escaping Loader) {
    guard !conversationID.isBlank else { clear(); return }
    guard snapshot.owner?.conversationID != conversationID else { return }
    clear()
    self.loader = loader
    requestedLimit = max(1, pageSize)
    snapshot = Snapshot(owner: Owner(conversationID: conversationID))
    requestRefresh()
  }

  func clear() {
    work?.cancel()
    work = nil
    loader = nil
    refreshPending = false
    requestedLimit = 0
    prependAnchor = nil
    if snapshot.owner != nil { snapshot = Snapshot() }
  }

  func requestRefresh() {
    guard snapshot.owner != nil else { return }
    refreshPending = true
    start()
  }

  func loadOlder(pageSize: Int) -> Bool {
    guard snapshot.hasMore, requestedLimit == snapshot.loadedLimit,
          let first = snapshot.messages.first else { return false }
    prependAnchor = first.id
    requestedLimit += max(1, pageSize)
    requestRefresh()
    return true
  }

  func owns(_ owner: Owner?) -> Bool {
    owner != nil && owner == snapshot.owner
  }

  private func start() {
    guard work == nil, refreshPending, let owner = snapshot.owner, let loader else { return }
    refreshPending = false
    let limit = requestedLimit
    let anchor = prependAnchor
    prependAnchor = nil
    work = Task { [weak self] in
      let page = await loader(owner.conversationID, limit)
      guard let self, !Task.isCancelled, self.owns(owner) else { return }
      if let page, page.messages.allSatisfy({ $0.conversationId == owner.conversationID }) {
        let next = Snapshot(owner: owner, messages: page.messages, hasMore: page.hasMore,
                            loadedLimit: limit, prependAnchor: anchor)
        if self.snapshot != next { self.snapshot = next }
      } else if self.requestedLimit == limit {
        self.requestedLimit = max(1, self.snapshot.loadedLimit == 0 ? limit : self.snapshot.loadedLimit)
      }
      self.work = nil
      self.start()
    }
  }
}
