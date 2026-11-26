import Foundation
import Combine

struct GlobalAgentDashboardRuntimeSnapshot {
  var cognitionTasks: [GlobalCognitionTask] = []
  var autonomousRuns: [GlobalAutonomousRun] = []
  var longHorizonGoals: [GlobalLongHorizonGoal] = []
  var researchState = GlobalResearchExecutorState()

  static func load() -> GlobalAgentDashboardRuntimeSnapshot? {
    let deliberation = GlobalAgentDeliberationStore()
    let cognition = deliberation.cognitionTasks()
    guard deliberation.lastErrorDescription.isEmpty else { return nil }
    let runs = deliberation.autonomousRuns()
    guard deliberation.lastErrorDescription.isEmpty else { return nil }
    let goals = GlobalLongHorizonGoalStore()
    let horizon = goals.goals()
    guard goals.lastErrorDescription.isEmpty else { return nil }
    let research = GalaxySSIGlobalResearchRuntimeStore()
    let state = research.state()
    guard research.lastErrorDescription.isEmpty else { return nil }
    return .init(cognitionTasks: cognition, autonomousRuns: runs,
      longHorizonGoals: horizon, researchState: state)
  }
}

// Main-actor request ownership, separate from the filesystem worker.
struct GlobalAgentDashboardRefreshState {
  private(set) var identity: String?
  private(set) var token: UUID?
  private(set) var pending = false

  mutating func request(identity: String) -> UUID? {
    if self.identity != identity { invalidate(); self.identity = identity }
    guard token == nil else { pending = true; return nil }
    let next = UUID()
    token = next
    return next
  }

  mutating func complete(_ completed: UUID) -> (accepted: Bool, next: UUID?) {
    guard token == completed else { return (false, nil) }
    token = nil
    let again = pending
    pending = false
    return (true, again ? request(identity: identity ?? "") : nil)
  }

  mutating func invalidate() {
    identity = nil
    token = nil
    pending = false
  }
}

@MainActor
final class GlobalAgentDashboardLoader: ObservableObject {
  @Published private(set) var snapshot = GlobalAgentDashboardRuntimeSnapshot()
  @Published private(set) var refreshFailed = false
  private var state = GlobalAgentDashboardRefreshState()
  private let queue: DispatchQueue
  private let load: () -> GlobalAgentDashboardRuntimeSnapshot?
  private static let contentQueue = DispatchQueue(label: "galaxyssi.global-dashboard-content", qos: .utility)

  init(queue: DispatchQueue? = nil,
       load: @escaping () -> GlobalAgentDashboardRuntimeSnapshot? = GlobalAgentDashboardRuntimeSnapshot.load) {
    self.queue = queue ?? Self.contentQueue
    self.load = load
  }

  func refresh(identity: String) {
    if state.identity != identity {
      snapshot = .init()
      refreshFailed = false
    }
    if let token = state.request(identity: identity) { launch(token) }
  }

  func invalidate() {
    state.invalidate()
    snapshot = .init()
    refreshFailed = false
  }

  func refreshIfActive(identity: String) {
    guard state.identity != nil else { return }
    refresh(identity: identity)
  }

  private func launch(_ token: UUID) {
    let read = load
    queue.async { [weak self] in
      let result = read()
      Task { @MainActor [weak self] in
        self?.complete(result, token: token)
      }
    }
  }

  private func complete(_ result: GlobalAgentDashboardRuntimeSnapshot?, token: UUID) {
    let completion = state.complete(token)
    guard completion.accepted else { return }
    if let result { snapshot = result }
    refreshFailed = result == nil
    if let next = completion.next { launch(next) }
  }
}
