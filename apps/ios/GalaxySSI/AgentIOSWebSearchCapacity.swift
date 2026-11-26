import Foundation

enum AgentIOSWebSearchCapacity {
  static let maximumResults = 100
  static let defaultResults = 10

  // Selected by native code, never by an input JSON field or a permission grant.
  enum Scope: Equatable {
    case webMedia, intelligence
    var maximumResults: Int64 { self == .intelligence ? Int64(AgentIOSWebSearchCapacity.maximumResults) : 24 }
    var queryCharacters: Int { self == .intelligence ? 4_096 : 1_024 }
    func imageCandidates(_ requested: Int) -> Int {
      self == .intelligence ? min(max(requested, 1), AgentIOSWebSearchCapacity.maximumResults) : 20
    }
  }
}
