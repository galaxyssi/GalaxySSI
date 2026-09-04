import Foundation

@MainActor
final class UserDefaultsAgentRemoteProactiveWebhookStore {
  static let shared = UserDefaultsAgentRemoteProactiveWebhookStore()

  static let defaultKey = "galaxyssi_remote_proactive_webhook_events_v1"
  private static let maxEvents = 500

  private let defaults: UserDefaults
  private var consumedKeys: [String]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    consumedKeys = defaults.data(forKey: Self.defaultKey)
      .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    consumedKeys = Array(consumedKeys.suffix(Self.maxEvents))
  }

  func consume(taskId: String, eventId: String) -> Bool {
    let task = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    let event = eventId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !task.isEmpty, !event.isEmpty else { return false }
    let key = "\(task)\u{1f}\(event)"
    guard !consumedKeys.contains(key) else { return false }
    consumedKeys.append(key)
    consumedKeys = Array(consumedKeys.suffix(Self.maxEvents))
    persist()
    return true
  }

  func clear() {
    consumedKeys = []
    defaults.removeObject(forKey: Self.defaultKey)
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(consumedKeys) else { return }
    defaults.set(data, forKey: Self.defaultKey)
  }
}
