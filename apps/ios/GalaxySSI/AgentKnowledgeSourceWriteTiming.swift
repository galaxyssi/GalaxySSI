import Foundation

// Standalone storage correlation, never derived from an item, source or task.
struct AgentKnowledgeSourceWriteTiming {
  enum Phase: String, CaseIterable {
    case total, stage, prepare, commit, ownership, apply, observe
    var runtime: AgentRuntimeTimingPhase {
      switch self {
      case .total: return .knowledgeSourceTotal
      case .stage: return .knowledgeSourceStage
      case .prepare: return .knowledgeSourcePrepare
      case .commit: return .knowledgeSourceCommit
      case .ownership: return .knowledgeSourceOwnership
      case .apply: return .knowledgeSourceApply
      case .observe: return .knowledgeSourceObserve
      }
    }
  }
  private let correlation = UUID().uuidString
  private let timing: AgentRuntimeTiming
  private let deferJournal: Bool
  init(timing: AgentRuntimeTiming = AgentLatencyTelemetry.runtime, deferJournal: Bool = true) {
    self.timing = timing; self.deferJournal = deferJournal
  }
  static let disabled = Self(timing: AgentRuntimeTiming(tracer: nil))
  func measure<T>(_ phase: Phase, operation: () throws -> T) rethrows -> T {
    try timing.measure(taskId: correlation, phase: phase.runtime, deferJournal: deferJournal, operation: operation)
  }
}
