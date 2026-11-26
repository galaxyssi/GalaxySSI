import BackgroundTasks
import Foundation
import UIKit

// Completion and cancellation can race on different system queues. A late worker
// may release resources, but cannot complete or reschedule an expired grant twice.
final class AgentKnowledgeBackgroundCompletion {
  private let lock = NSLock()
  private var finished = false
  private var cancelled = false
  private var cancellation: [() -> Void] = []
  private var completion: ((Bool, Bool?) -> Void)?

  init(_ completion: @escaping (Bool, Bool?) -> Void) { self.completion = completion }

  func onCancellation(_ action: @escaping () -> Void) {
    lock.lock()
    if finished {
      let shouldCancel = cancelled
      lock.unlock()
      if shouldCancel { action() }
      return
    }
    cancellation.append(action)
    lock.unlock()
  }

  func finish(success: Bool, pending: Bool?) {
    lock.lock()
    guard !finished else { lock.unlock(); return }
    finished = true
    cancelled = !success
    let actions = success ? [] : cancellation
    cancellation.removeAll()
    let callback = completion
    completion = nil
    lock.unlock()
    for action in actions { action() }
    callback?(success, pending)
  }
}

enum AgentKnowledgeBackgroundScheduler {
  static let taskIdentifier = "com.galaxyssi.chat.ios.knowledge-index"
  private static let pendingKey = "galaxyssi.knowledge.native.background.pending.v1"
  private static let lock = NSLock()
  private static var registered = false
  private static var generation: UInt64 = 0
  private static var active: (id: UUID, control: AgentKnowledgeBackgroundCompletion)?
  @MainActor private static weak var database: AgentKnowledgeDatabase?

  static func register() {
    lock.lock()
    guard !registered else { lock.unlock(); return }
    registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
      guard let task = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
      launch(task)
    }
    let resume = registered && UserDefaults.standard.bool(forKey: pendingKey)
    lock.unlock()
    if resume { schedule(pending: true) }
  }

  // Persist intent even when the OS declines a request. Foreground/source changes
  // and the next launch can retry; a cold launch never creates a new history ID.
  static func schedule(pending: Bool, expectedGeneration: UInt64? = nil) {
    lock.lock()
    defer { lock.unlock() }
    if let expectedGeneration, generation != expectedGeneration { return }
    if !pending { generation &+= 1 }
    UserDefaults.standard.set(pending, forKey: pendingKey)
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    guard pending, registered else { return }
    let request = BGProcessingTaskRequest(identifier: taskIdentifier)
    request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = false
    try? BGTaskScheduler.shared.submit(request)
  }

  static func cancel() {
    lock.lock()
    generation &+= 1
    UserDefaults.standard.set(false, forKey: pendingKey)
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    let previous = active?.control
    active = nil
    lock.unlock()
    previous?.finish(success: false, pending: nil)
  }

  @MainActor
  static func bind(database newDatabase: AgentKnowledgeDatabase) {
    guard database !== newDatabase else { return }
    database = newDatabase
    lock.lock()
    generation &+= 1
    let previous = active?.control
    active = nil
    let resume = UserDefaults.standard.bool(forKey: pendingKey)
    lock.unlock()
    previous?.finish(success: false, pending: nil)
    if resume { schedule(pending: true) }
  }

  private static func launch(_ task: BGProcessingTask) {
    lock.lock()
    guard UserDefaults.standard.bool(forKey: pendingKey) else {
      lock.unlock()
      task.setTaskCompleted(success: true)
      return
    }
    generation &+= 1
    let ticket = generation, id = UUID(), previous = active?.control
    let control = AgentKnowledgeBackgroundCompletion { success, pending in
      lock.lock()
      if active?.id == id { active = nil }
      lock.unlock()
      if let pending { schedule(pending: pending, expectedGeneration: ticket) }
      task.expirationHandler = nil
      task.setTaskCompleted(success: success)
    }
    active = (id, control)
    lock.unlock()
    previous?.finish(success: false, pending: nil)
    task.expirationHandler = { control.finish(success: false, pending: true) }
    let work = Task { @MainActor in
      do {
        try Task.checkCancellation()
        guard UIApplication.shared.isProtectedDataAvailable,
          UIApplication.shared.applicationState != .active else { throw CancellationError() }
        guard let source = database ?? GalaxySSIStore.existingAgentKnowledgeDatabase() else {
          control.finish(success: true, pending: false)
          return
        }
        let controller = AgentKnowledgeSemanticController(database: source, automaticallyStart: false)
        guard controller.state.enabled, controller.state.installed else {
          control.finish(success: true, pending: false)
          return
        }
        let lease = try source.nativeFiles.beginBackgroundLease()
        defer { lease.end() }
        control.onCancellation { lease.end() }
        try Task.checkCancellation()
        let pending = try await controller.runBackgroundSlice(lease: lease)
        try Task.checkCancellation()
        lease.end()
        control.finish(success: true, pending: pending)
      } catch {
        control.finish(success: false, pending: true)
      }
    }
    control.onCancellation { work.cancel() }
  }
}
