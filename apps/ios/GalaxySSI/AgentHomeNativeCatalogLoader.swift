import Combine
import Foundation

@MainActor
final class AgentHomeNativeCatalogLoader: ObservableObject {
  @Published private(set) var tools: [AgentNativeToolDescriptor] = []
  @Published private(set) var hasSnapshot = false
  @Published private(set) var refreshFailed = false
  private var state = GlobalAgentDashboardRefreshState()
  private let queue: DispatchQueue
  private let load: () -> [AgentNativeToolDescriptor]?
  private static let contentQueue = DispatchQueue(label: "galaxyssi.home-native-catalog", qos: .utility)

  init(queue: DispatchQueue? = nil,
       load: @escaping () -> [AgentNativeToolDescriptor]? = { AgentPhoneNativeToolCatalog.descriptors() }) {
    self.queue = queue ?? Self.contentQueue
    self.load = load
  }

  var availableCount: Int {
    tools.filter { $0.risk != .blocked && $0.availability.status == .available }.count
  }

  func isCurrent(identity: String) -> Bool {
    !identity.isBlank && state.identity == identity && hasSnapshot
  }

  func refresh(identity: String) {
    guard !identity.isBlank else { invalidate(); return }
    if state.identity != identity { tools = []; hasSnapshot = false; refreshFailed = false }
    if let token = state.request(identity: identity) { launch(token) }
  }

  func refreshIfActive(identity: String) {
    guard state.identity != nil else { return }
    refresh(identity: identity)
  }

  func invalidate() {
    state.invalidate()
    tools = []
    hasSnapshot = false
    refreshFailed = false
  }

  private func launch(_ token: UUID) {
    let read = load
    queue.async { [weak self] in
      let result = read()
      Task { @MainActor [weak self] in self?.complete(result, token: token) }
    }
  }

  private func complete(_ result: [AgentNativeToolDescriptor]?, token: UUID) {
    let completion = state.complete(token)
    guard completion.accepted else { return }
    if let result { tools = result; hasSnapshot = true }
    refreshFailed = result == nil
    if let next = completion.next { launch(next) }
  }
}
