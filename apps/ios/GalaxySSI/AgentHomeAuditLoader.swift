import Foundation
import Combine

@MainActor
final class AgentHomeAuditLoader: ObservableObject {
  @Published private(set) var records: [AgentNativeToolAuditRecord] = []
  private var state = GlobalAgentDashboardRefreshState()
  private let queue: DispatchQueue
  private let load: () -> [AgentNativeToolAuditRecord]
  private static let contentQueue = DispatchQueue(label: "galaxyssi.home-audit", qos: .utility)

  init(queue: DispatchQueue? = nil, load: @escaping () -> [AgentNativeToolAuditRecord] = {
    AgentNativeToolDefaultStores.makePersistentStores().auditStore.list(limit: 12, toolId: "", status: nil)
  }) {
    self.queue = queue ?? Self.contentQueue
    self.load = load
  }

  func records(for identity: String?) -> [AgentNativeToolAuditRecord] {
    guard let identity, !identity.isBlank, state.identity == identity else { return [] }
    return records
  }

  func refresh(identity: String) {
    guard !identity.isBlank else { invalidate(); return }
    if state.identity != identity { records = [] }
    if let token = state.request(identity: identity) { launch(token) }
  }

  func invalidate() {
    state.invalidate()
    records = []
  }

  private func launch(_ token: UUID) {
    let read = load
    queue.async { [weak self] in
      let result = read()
      Task { @MainActor [weak self] in
        guard let self else { return }
        let completion = self.state.complete(token)
        guard completion.accepted else { return }
        self.records = result
        if let next = completion.next { self.launch(next) }
      }
    }
  }
}
