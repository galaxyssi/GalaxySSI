import BackgroundTasks
import Foundation

enum GalaxySSIHealthCareModelAttentionBackground {
  static let taskIdentifier = "com.galaxyssi.ios.health-model-attention.refresh"
  @MainActor private static var scheduled: Date?

  static func register() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
      guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
      let work = Task { @MainActor in
        scheduled = nil
        let next = await GalaxySSIHealthCareModelAttentionRuntime.shared.reconcile {
          GalaxySSIHealthCareModelAttentionRuntime.Context.persisted()
        }
        schedule(next)
        refresh.setTaskCompleted(success: !Task.isCancelled)
      }
      refresh.expirationHandler = { work.cancel() }
    }
  }

  @MainActor
  static func schedule(_ date: Date?) {
    guard scheduled != date else { return }
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    scheduled = nil
    guard let date else { return }
    let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
    request.earliestBeginDate = date
    do { try BGTaskScheduler.shared.submit(request); scheduled = date }
    catch { /* The durable receipt remains eligible on the next app/system opportunity. */ }
  }
}
