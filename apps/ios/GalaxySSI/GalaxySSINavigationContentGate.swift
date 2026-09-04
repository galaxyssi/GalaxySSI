import Foundation

struct GalaxySSINavigationContentGate: Equatable {
  private(set) var generation = UUID()

  mutating func begin() -> UUID {
    generation = UUID()
    return generation
  }

  mutating func invalidate() {
    generation = UUID()
  }

  func isCurrent(_ token: UUID) -> Bool {
    generation == token
  }
}
