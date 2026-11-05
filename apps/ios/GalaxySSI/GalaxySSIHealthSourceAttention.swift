import Foundation

struct GalaxySSIHealthSourceAttention: Codable, Equatable {
  typealias Scope = GalaxySSIHealthKitImport.Scope

  struct Incident: Codable, Identifiable, Equatable {
    let id: UUID
    let scope: Scope
    let failedAt: Date
  }

  enum ReadResult: String, Codable, Equatable {
    case samples, empty, failed
  }

  struct ReadHistory: Codable, Equatable {
    let result: ReadResult
    let at: Date
    let lastSamplesAt: Date?
  }

  var selected: Set<Scope> = []
  private var unresolved: [Scope: Incident] = [:]
  private(set) var readHistory: [Scope: ReadHistory]?

  var active: [Incident] {
    unresolved.values.filter { selected.contains($0.scope) }.sorted {
      if $0.failedAt != $1.failedAt { return $0.failedAt > $1.failedAt }
      return $0.scope.rawValue < $1.scope.rawValue
    }
  }

  mutating func readFinished(_ scope: Scope, result: ReadResult, now: Date) {
    var history = readHistory ?? [:]
    history[scope] = .init(result: result, at: now,
                           lastSamplesAt: result == .samples ? now : history[scope]?.lastSamplesAt)
    readHistory = history
    guard selected.contains(scope) else { return }
    if result != .failed {
      unresolved.removeValue(forKey: scope)
    } else {
      unresolved[scope] = Incident(id: UUID(), scope: scope, failedAt: now)
    }
  }

  mutating func acknowledge(_ incident: Incident) {
    guard unresolved[incident.scope]?.id == incident.id else { return }
    unresolved.removeValue(forKey: incident.scope)
  }
}
