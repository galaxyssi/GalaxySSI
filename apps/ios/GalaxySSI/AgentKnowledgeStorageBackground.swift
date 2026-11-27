import BackgroundTasks
import Foundation
import UIKit

enum AgentKnowledgeStorageMaintenancePolicy {
  static func permits(foreground: Bool, protectedData: Bool, lowPower: Bool, thermal: ProcessInfo.ThermalState) -> Bool {
    !foreground && protectedData && !lowPower && (thermal == .nominal || thermal == .fair)
  }
}

struct AgentKnowledgeStorageMaintenanceBudget {
  private let started: TimeInterval
  private let deadline: TimeInterval
  private let clock: () -> TimeInterval

  init(seconds: TimeInterval = 10, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
    self.clock = clock
    started = clock()
    deadline = started + seconds
  }

  func check() throws {
    try Task.checkCancellation()
    let now = clock()
    guard started.isFinite, deadline.isFinite, now.isFinite, now >= started, now < deadline else { throw CancellationError() }
  }
}

// Physical maintenance is independent of installed embedding models and index preferences.
enum AgentKnowledgeStorageBackground {
  static let taskIdentifier = "com.galaxyssi.chat.ios.knowledge-storage"
  private static let pendingKey = "galaxyssi.knowledge.storage.background.pending.v1"
  private static let lock = NSLock()
  private static var attemptedRegistration = false
  private static var registered = false
  private static var generation: UInt64 = 0
  private static var active: (id: UUID, control: AgentKnowledgeBackgroundCompletion)?
  private static var observers: [NSObjectProtocol] = []
  @MainActor private static weak var database: AgentKnowledgeDatabase?

  static func register() {
    lock.lock()
    guard !attemptedRegistration else { lock.unlock(); return }
    attemptedRegistration = true
    registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
      guard let task = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
      launch(task)
    }
    observers = [UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification,
      UIApplication.protectedDataWillBecomeUnavailableNotification].map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in suspendActiveGrant() }
    }
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
      object: nil, queue: .main) { _ in
      if UserDefaults.standard.bool(forKey: pendingKey) { schedule(pending: true) }
    })
    let resume = UserDefaults.standard.bool(forKey: pendingKey)
    lock.unlock()
    if resume { schedule(pending: true) }
  }

  static func schedule(pending: Bool, expectedGeneration: UInt64? = nil) {
    lock.lock()
    defer { lock.unlock() }
    if let expectedGeneration, generation != expectedGeneration { return }
    UserDefaults.standard.set(pending, forKey: pendingKey)
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    guard pending, registered else { return }
    let request = BGProcessingTaskRequest(identifier: taskIdentifier)
    request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = false
    try? BGTaskScheduler.shared.submit(request)
  }

  @MainActor
  static func bind(database newDatabase: AgentKnowledgeDatabase) {
    guard database !== newDatabase else { return }
    database = newDatabase
    lock.lock()
    generation &+= 1
    let previous = active?.control
    active = nil
    lock.unlock()
    previous?.finish(success: false, pending: nil)
    schedule(pending: true)
  }

  private static func suspendActiveGrant() {
    lock.lock()
    generation &+= 1
    let previous = active?.control
    active = nil
    let pending = UserDefaults.standard.bool(forKey: pendingKey)
    lock.unlock()
    previous?.finish(success: false, pending: nil)
    if pending { schedule(pending: true) }
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
        guard AgentKnowledgeStorageMaintenancePolicy.permits(foreground: UIApplication.shared.applicationState != .background,
          protectedData: UIApplication.shared.isProtectedDataAvailable, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
          thermal: ProcessInfo.processInfo.thermalState) else { throw CancellationError() }
        guard let source = database ?? GalaxySSIStore.existingAgentKnowledgeDatabase() else {
          control.finish(success: true, pending: false)
          return
        }
        let worker = Task.detached(priority: .utility) {
          let budget = AgentKnowledgeStorageMaintenanceBudget()
          return try source.maintainPrimaryStorageSlice(maximumPages: 8) {
            try budget.check()
            guard AgentKnowledgeStorageMaintenancePolicy.permits(foreground: false, protectedData: true,
              lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, thermal: ProcessInfo.processInfo.thermalState) else {
              throw CancellationError()
            }
          }
        }
        control.onCancellation { worker.cancel() }
        _ = try await worker.value
        try Task.checkCancellation()
        // Keep periodic intent even when this pass is complete: new writes and age gates can create later work.
        control.finish(success: true, pending: true)
      } catch {
        control.finish(success: false, pending: true)
      }
    }
    control.onCancellation { work.cancel() }
  }
}
