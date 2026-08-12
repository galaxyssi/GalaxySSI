import Foundation

struct SignalASIGlobalAgentBackupData: Codable, Equatable {
  var cognitionTasks: [GlobalCognitionTask]
  var autonomousRuns: [GlobalAutonomousRun]
  var longHorizonGoals: [GlobalLongHorizonGoal]
  var proactiveDiscovery: GlobalProactiveDiscoveryState
  var research: GlobalResearchExecutorState
  var memoryEvolution: GlobalMemoryEvolutionArchive

  init(
    cognitionTasks: [GlobalCognitionTask] = [],
    autonomousRuns: [GlobalAutonomousRun] = [],
    longHorizonGoals: [GlobalLongHorizonGoal] = [],
    proactiveDiscovery: GlobalProactiveDiscoveryState = GlobalProactiveDiscoveryState(),
    research: GlobalResearchExecutorState = GlobalResearchExecutorState(),
    memoryEvolution: GlobalMemoryEvolutionArchive = GlobalMemoryEvolutionArchive()
  ) {
    self.cognitionTasks = Array(cognitionTasks.suffix(300))
    self.autonomousRuns = Array(autonomousRuns.suffix(200))
    self.longHorizonGoals = Array(longHorizonGoals.suffix(200))
    self.proactiveDiscovery = proactiveDiscovery
    self.research = research
    self.memoryEvolution = memoryEvolution
  }

  enum CodingKeys: String, CodingKey {
    case cognitionTasks = "cognition_tasks"
    case autonomousRuns = "autonomous_runs"
    case longHorizonGoals = "long_horizon_goals"
    case proactiveDiscovery = "proactive_discovery"
    case research
    case memoryEvolution = "memory_evolution"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      cognitionTasks: try container.decodeIfPresent([GlobalCognitionTask].self, forKey: .cognitionTasks) ?? [],
      autonomousRuns: try container.decodeIfPresent([GlobalAutonomousRun].self, forKey: .autonomousRuns) ?? [],
      longHorizonGoals: try container.decodeIfPresent([GlobalLongHorizonGoal].self, forKey: .longHorizonGoals) ?? [],
      proactiveDiscovery: try container.decodeIfPresent(
        GlobalProactiveDiscoveryState.self,
        forKey: .proactiveDiscovery
      ) ?? GlobalProactiveDiscoveryState(),
      research: try container.decodeIfPresent(GlobalResearchExecutorState.self, forKey: .research)
        ?? GlobalResearchExecutorState(),
      memoryEvolution: try container.decodeIfPresent(
        GlobalMemoryEvolutionArchive.self,
        forKey: .memoryEvolution
      ) ?? GlobalMemoryEvolutionArchive()
    )
  }
}

extension SignalASIStore {
  func exportGlobalAgentBackupData() -> SignalASIGlobalAgentBackupData {
    let deliberationStore = GlobalAgentDeliberationStore()
    return SignalASIGlobalAgentBackupData(
      cognitionTasks: deliberationStore.exportCognitionTasks(),
      autonomousRuns: deliberationStore.exportAutonomousRuns(),
      longHorizonGoals: GlobalLongHorizonGoalStore().exportGoals(),
      proactiveDiscovery: SignalASIGlobalProactiveDiscoveryRuntimeStore().state(),
      research: SignalASIGlobalResearchRuntimeStore().state(),
      memoryEvolution: GlobalMemoryEvolutionStore().exportArchive()
    )
  }

  func restoreGlobalAgentBackupData(_ data: SignalASIGlobalAgentBackupData) {
    let deliberationStore = GlobalAgentDeliberationStore()
    deliberationStore.restoreCognitionTasks(data.cognitionTasks)
    deliberationStore.restoreAutonomousRuns(data.autonomousRuns)
    GlobalLongHorizonGoalStore().restore(data.longHorizonGoals)
    SignalASIGlobalProactiveDiscoveryRuntimeStore().save(data.proactiveDiscovery)
    SignalASIGlobalResearchRuntimeStore().save(data.research)
    GlobalMemoryEvolutionStore().restore(data.memoryEvolution)
  }

  func destroyGlobalAgentBackupData() {
    GlobalAgentDeliberationStore.destroyPersistentStore()
    GlobalLongHorizonGoalStore.destroyPersistentStore()
    SignalASIGlobalProactiveDiscoveryRuntimeStore.destroyPersistentStore()
    SignalASIGlobalResearchRuntimeStore.destroyPersistentStore()
    GlobalMemoryEvolutionStore().clear()
  }
}
