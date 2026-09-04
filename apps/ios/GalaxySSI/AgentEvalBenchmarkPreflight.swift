import Foundation

struct AgentBenchmarkHarnessCapabilities: Equatable {
  var planningAndTools: Bool
  var iosWorld: Bool
  var recoveryController: Bool
  var multiAgent: Bool
  var availableToolIds: Set<String> = []
  var availableIOSWorldTaskIds: Set<String> = []
}

enum AgentBenchmarkHarnessCapabilityProbe {
  static func current(
    multiAgent: Bool = false,
    faultStore: AgentEvalFaultControllerStore = AgentEvalFaultControllerStore(),
    worldStore: AgentIOSWorldStore = AgentIOSWorldStore()
  ) -> AgentBenchmarkHarnessCapabilities {
    let tools = AgentPhoneNativeToolCatalog.descriptors().filter { $0.availability.status == .available }
    let worldIds = Set(worldStore.tasks(limit: 100).map(\.id))
    return AgentBenchmarkHarnessCapabilities(
      planningAndTools: !tools.isEmpty,
      iosWorld: !worldIds.isEmpty,
      recoveryController: faultStore.activeLease() != nil,
      multiAgent: multiAgent,
      availableToolIds: Set(tools.map(\.id)),
      availableIOSWorldTaskIds: worldIds
    )
  }
}

enum AgentBenchmarkPreflight {
  static func assess(
    suite: AgentBenchmarkSuite,
    capabilities: AgentBenchmarkHarnessCapabilities,
    memories: [AgentMemoryItem],
    nowMillis: Int64 = AgentEvalClock.nowMillis()
  ) -> [String: AgentBenchmarkCaseReadiness] {
    Dictionary(uniqueKeysWithValues: suite.cases.map { item in
      let readiness: AgentBenchmarkCaseReadiness
      switch item.dimension {
      case .taskQuality:
        readiness = ready(item)
      case .planningAndTools:
        readiness = planningReadiness(item, capabilities)
      case .iosWorld:
        readiness = iosWorldReadiness(item, capabilities)
      case .immediateMemory, .longTermMemory:
        readiness = memoryReadiness(item, memories: memories, nowMillis: nowMillis)
      case .recovery:
        readiness = capabilities.recoveryController
          ? ready(item) : waiting(item, "external_fault_controller_required")
      case .multiAgent:
        readiness = capabilities.multiAgent
          ? ready(item) : blocked(item, "multi_agent_harness_unavailable")
      }
      return (item.id, readiness)
    })
  }

  private static func planningReadiness(
    _ item: AgentBenchmarkCase,
    _ capabilities: AgentBenchmarkHarnessCapabilities
  ) -> AgentBenchmarkCaseReadiness {
    guard capabilities.planningAndTools else { return blocked(item, "planning_tool_harness_unavailable") }
    let required = Set(AgentBenchmarkHarnessProtocol.tools(for: item, trialId: "preflight").map(\.id))
    let missing = required.subtracting(capabilities.availableToolIds)
    return missing.isEmpty ? ready(item) : blocked(item, "required_tool_unavailable:\(missing.sorted().joined(separator: ","))")
  }

  private static func iosWorldReadiness(
    _ item: AgentBenchmarkCase,
    _ capabilities: AgentBenchmarkHarnessCapabilities
  ) -> AgentBenchmarkCaseReadiness {
    guard capabilities.iosWorld else { return blocked(item, "ios_world_harness_unavailable") }
    guard capabilities.availableIOSWorldTaskIds.contains(item.expectation.iosWorldTaskId) else {
      return blocked(item, "ios_world_task_unavailable:\(item.expectation.iosWorldTaskId)")
    }
    return ready(item)
  }

  private static func memoryReadiness(
    _ item: AgentBenchmarkCase,
    memories: [AgentMemoryItem],
    nowMillis: Int64
  ) -> AgentBenchmarkCaseReadiness {
    let fixture = fixtureId(item.id)
    let immediate = item.dimension == .immediateMemory
    let key = immediate ? "evalops.immediate.\(fixture.lowercased())" : "evalops.fixture.\(fixture.lowercased())"
    let sources: Set<String> = immediate ? ["evalops_immediate_fixture", "memory_edit"] : ["evalops_fixture"]
    let memory = memories.first {
      sources.contains($0.source) && $0.key == key && $0.value.lowercased().hasPrefix("\(fixture.lowercased()) =")
    }
    let eligibleAt = memory.map { $0.timestampMillis + Int64(item.expectation.memoryHorizonDays) * 86_400_000 } ?? 0
    if let memory, item.expectation.memoryHorizonDays == 0 || eligibleAt <= nowMillis, !memory.isExpired(nowMillis: nowMillis) {
      return ready(item)
    }
    return waiting(item, "memory_horizon_not_reached", eligibleAt: eligibleAt)
  }

  private static func fixtureId(_ caseId: String) -> String {
    if caseId.hasPrefix("immediate-memory-"), let suffix = caseId.split(separator: "-").last {
      return suffix == "09" ? "IM-09-B" : "IM-\(suffix)"
    }
    let parts = caseId.split(separator: "-")
    if parts.count == 3, parts[0] == "memory" { return "M\(parts[1])-\(parts[2])" }
    return caseId
  }

  private static func ready(_ item: AgentBenchmarkCase) -> AgentBenchmarkCaseReadiness {
    AgentBenchmarkCaseReadiness(caseId: item.id, status: .ready)
  }

  private static func waiting(_ item: AgentBenchmarkCase, _ reason: String, eligibleAt: Int64 = 0) -> AgentBenchmarkCaseReadiness {
    AgentBenchmarkCaseReadiness(caseId: item.id, status: .waiting, reasonCode: reason, eligibleAtMillis: eligibleAt)
  }

  private static func blocked(_ item: AgentBenchmarkCase, _ reason: String) -> AgentBenchmarkCaseReadiness {
    AgentBenchmarkCaseReadiness(caseId: item.id, status: .blocked, reasonCode: reason)
  }
}
