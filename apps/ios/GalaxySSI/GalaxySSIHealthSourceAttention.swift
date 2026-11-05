import Foundation

struct GalaxySSIHealthSourceAttention: Codable, Equatable {
  typealias Scope = GalaxySSIHealthKitImport.Scope

  struct Incident: Codable, Identifiable, Equatable {
    let id: UUID
    let scope: Scope
    let failedAt: Date
  }

  var selected: Set<Scope> = []
  private var unresolved: [Scope: Incident] = [:]

  var active: [Incident] {
    unresolved.values.filter { selected.contains($0.scope) }.sorted {
      if $0.failedAt != $1.failedAt { return $0.failedAt > $1.failedAt }
      return $0.scope.rawValue < $1.scope.rawValue
    }
  }

  mutating func readFinished(_ scope: Scope, succeeded: Bool, now: Date) {
    guard selected.contains(scope) else { return }
    if succeeded {
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
