import BackgroundTasks
import Foundation

enum GalaxySSIHealthAppointmentBackground {
  static let identifier = "com.galaxyssi.ios.health-appointment.refresh"
  @MainActor private static var scheduled: Date?

  static func register() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
      let work = Task { @MainActor in
        scheduled = nil
        let next = await GalaxySSIHealthAppointmentNotifications.cleanPersisted()
        schedule(next)
        refresh.setTaskCompleted(success: !Task.isCancelled)
      }
      refresh.expirationHandler = { work.cancel() }
    }
  }

  @MainActor static func schedule(_ date: Date?) {
    guard scheduled != date else { return }
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    scheduled = nil
    guard let date else { return }
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = date
    do { try BGTaskScheduler.shared.submit(request); scheduled = date }
    catch { /* Cleanup also runs on the next available app lifecycle opportunity. */ }
  }
}
