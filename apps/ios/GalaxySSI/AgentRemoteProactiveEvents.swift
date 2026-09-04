import CryptoKit
import Combine
import Foundation

struct AgentRemoteProactiveEvent: Codable, Equatable, Identifiable {
  let eventId: String
  let desktopId: String
  let desktopName: String
  let taskId: String
  let runId: String
  let kind: String
  let status: String
  let detail: String
  let timestampMillis: Int64

  var id: String { eventId }

  private enum CodingKeys: String, CodingKey {
    case eventId = "event_id"
    case desktopId = "desktop_id"
    case desktopName = "desktop_name"
    case taskId = "task_id"
    case runId = "run_id"
    case kind
    case status
    case detail
    case timestampMillis = "timestamp_millis"
  }
}

@MainActor
final class UserDefaultsAgentRemoteProactiveEventStore: ObservableObject {
  static let shared = UserDefaultsAgentRemoteProactiveEventStore()

  static let defaultKey = "galaxyssi_remote_proactive_events_v1"
  private static let maxEvents = 500

  @Published private(set) var events: [AgentRemoteProactiveEvent]
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    guard let data = defaults.data(forKey: Self.defaultKey),
          let decoded = try? JSONDecoder().decode([AgentRemoteProactiveEvent].self, from: data) else {
      events = []
      return
    }
    events = Self.sortedAndCapped(decoded)
  }

  @discardableResult
  func ingest(
    payload: [String: Any],
    trustedDesktopId: String,
    trustedDesktopName: String = ""
  ) -> Bool {
    let desktopId = clipped(trustedDesktopId, to: 128)
    guard !desktopId.isEmpty else { return false }

    let runId = clipped(payload.string("run_id"), to: 128)
    let sequence = payload.int("sequence")
    let timestamp = Int64(payload.int("timestamp_millis")).nonZero ?? currentTimeMillis()
    let kind = clipped(payload.string("kind"), to: 64)
    let identity = [desktopId, runId, String(sequence), kind, String(timestamp)].joined(separator: "\u{1f}")
    let eventId = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    let event = AgentRemoteProactiveEvent(
      eventId: eventId,
      desktopId: desktopId,
      desktopName: clipped(payload.string("desktop_name").ifBlank(trustedDesktopName), to: 120),
      taskId: clipped(payload.string("task_id"), to: 128),
      runId: runId,
      kind: kind,
      status: clipped(payload.string("status"), to: 32),
      detail: clipped(payload.string("detail"), to: 2_048),
      timestampMillis: timestamp
    )

    events.removeAll { $0.eventId == event.eventId }
    events = Self.sortedAndCapped(events + [event])
    persist()
    return true
  }

  func recent(limit: Int = 100) -> [AgentRemoteProactiveEvent] {
    Array(events.prefix(limit.clamped(to: 1...Self.maxEvents)))
  }

  func clear() {
    events = []
    defaults.removeObject(forKey: Self.defaultKey)
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(events) else { return }
    defaults.set(data, forKey: Self.defaultKey)
  }

  private static func sortedAndCapped(_ values: [AgentRemoteProactiveEvent]) -> [AgentRemoteProactiveEvent] {
    Array(values.sorted {
      if $0.timestampMillis == $1.timestampMillis {
        return $0.eventId > $1.eventId
      }
      return $0.timestampMillis > $1.timestampMillis
    }.prefix(maxEvents))
  }

  private func clipped(_ value: String, to limit: Int) -> String {
    String(value.prefix(limit))
  }

  private func currentTimeMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}

private extension Int64 {
  var nonZero: Int64? { self > 0 ? self : nil }
}
