import BackgroundTasks
import UIKit

enum AgentConversationalTeamBackground {
  static let identifier = "com.galaxyssi.chat.ios.conversation-team"
  private static let pendingKey = "galaxyssi.conversation-team.background.pending"
  private static let lock = NSLock()
  private static var registered = false
  private static var generation: UInt64 = 0
  static func register() {
    lock.lock(); defer { lock.unlock() }
    guard !registered else { return }
    registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      guard let task = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
      lock.lock(); generation &+= 1; let epoch = generation; lock.unlock()
      let completion = AgentKnowledgeBackgroundCompletion { success, pending in
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
        if let pending { schedule(pending: pending, expected: epoch) }
      }
      let grant = UUID()
      let worker = Task { @MainActor in
        let success = await AgentConversationalTeamRuntime.shared.runBackground(grant: grant)
        completion.finish(success: success, pending: success ? nil : true)
      }
      completion.onCancellation { worker.cancel(); Task { @MainActor in AgentConversationalTeamRuntime.shared.expireBackground(grant) } }
      task.expirationHandler = { completion.finish(success: false, pending: true) }
    }
    if registered && UserDefaults.standard.bool(forKey: pendingKey) {
      DispatchQueue.main.async { schedule(pending: true) }
    }
  }
  static func schedule(pending: Bool, expected: UInt64? = nil) {
    lock.lock(); defer { lock.unlock() }
    if let expected, generation != expected { return }
    generation &+= 1
    UserDefaults.standard.set(pending, forKey: pendingKey)
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    guard registered, pending else { return }
    let request = BGProcessingTaskRequest(identifier: identifier)
    request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = false
    try? BGTaskScheduler.shared.submit(request)
  }
}
