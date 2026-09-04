import Foundation

enum AgentEvalBenchmarkCatalog {
  static let standard = AgentBenchmarkSuite(
    id: "galaxyssi-ios-real-agent",
    version: "1.2.0",
    title: "GalaxySSI iOS Real Agent EvalOps",
    cases: taskQualityCases + planningCases + iosWorldCases + immediateMemoryCases + recoveryCases + multiAgentCases,
    targetPassRate: 0.95
  )

  static let longitudinalMemory = AgentBenchmarkSuite(
    id: "galaxyssi-ios-longitudinal-memory",
    version: "1.0.0",
    title: "GalaxySSI iOS 30/90-day Memory Certification",
    cases: longTermMemoryCases,
    targetPassRate: 0.95,
    minimumTaskCount: 10,
    maximumTaskCount: 10
  )

  static let suites = [standard, longitudinalMemory]

  static func suite(id: String, version: String) -> AgentBenchmarkSuite? {
    suites.first { $0.id == id && $0.version == version }
  }

  private static let taskQualityCases: [AgentBenchmarkCase] = [
    quality("quality-01", "Multi-step arithmetic", "Calculate (17 x 23) - (144 / 12). Return only the final integer.", "^379$"),
    quality("quality-02", "Constrained sorting", "Sort 9, 2, 5, 2, 1 ascending. Return a JSON array without explanation.", "^\\[\\s*1\\s*,\\s*2\\s*,\\s*2\\s*,\\s*5\\s*,\\s*9\\s*\\]$"),
    qualityJSON("quality-03", "Structured output", "Return only a valid JSON object where status is ready and count is 3.", ["status": "ready", "count": "3"]),
    quality("quality-04", "Dependency path", "A takes 2 minutes. B follows A and takes 3. C follows A and takes 4. D waits for B and C and takes 1. Give the minimum duration and critical path.", "(?is)(7\\s*(minutes?|min)).*(A.*C.*D)"),
    quality("quality-05", "Weighted score", "Weights are 0.5, 0.3, 0.2 and scores are 80, 90, 70. Return only the weighted total.", "^81$"),
    quality("quality-06", "Conditional reasoning", "Every blue box is heavy. Box K is not heavy. Can K be blue? Answer no and give one sentence of reasoning.", "(?is)^no.*(blue.*heavy|not heavy.*blue)"),
    qualityJSON("quality-07", "Information extraction", "Extract device, os, and ram from: iPhone 15 Pro, iOS 18, 8GB. Return one JSON line.", ["device": "iPhone 15 Pro", "os": "iOS 18", "ram": "8GB"]),
    quality("quality-08", "Unit conversion", "How many MiB are in 1.5 GiB? Return only the number.", "^1536$"),
    quality("quality-09", "Distinct events", "For [a,b,a,c,b,d], return the distinct count and events in first-seen order.", "(?is)(4).*(a.*b.*c.*d)"),
    quality("quality-10", "Conflict resolution", "Record 1 says screen understanding is enabled. A newer record 2 says it was removed. What is the current state?", "(?is)(removed|disabled).*(record 2|newer|latest)")
  ]

  private static let planningCases: [AgentBenchmarkCase] = [
    planning("plan-tool-01", "Device version", "Plan briefly, use an available tool to verify this device model and iOS version, then report tool evidence."),
    planning("plan-tool-02", "App version", "Plan, use a tool to read the current GalaxySSI version and build, then report evidence."),
    planning("plan-tool-03", "Network state", "Plan, use a tool to check network availability and validation, then report evidence."),
    planning("plan-tool-04", "Battery state", "Plan, use a tool to read battery level, charging state, and thermal state, then report evidence."),
    planning("plan-tool-05", "Storage state", "Plan, use a tool to read available app storage, then report the value and evidence."),
    planning("plan-tool-06", "Trusted time", "Plan, call a trusted time tool for local date and time zone, then identify the tool source."),
    planning("plan-tool-07", "File integrity", "Plan, create a text file in an allowed test directory, read it, calculate SHA-256, then report the digest."),
    planning("plan-tool-08", "Tool recovery", "Plan, attempt a side-effect-free tool check, adjust the approach once if it fails, and report every step."),
    planning("plan-tool-09", "Primary research", "Plan, find two primary sources with a search tool, cross-check them, and return a sourced conclusion.", sources: true),
    planning("plan-tool-10", "Artifact validation", "Plan, generate a small JSON artifact, validate that a tool can parse it, and report the validation result.")
  ]

  private static let iosWorldCases: [AgentBenchmarkCase] = [
    world("ios-world-01", "Foreground app", "Verify that GalaxySSI is foreground and report the observed screen."),
    world("ios-world-02", "Visible title", "Read and report the current GalaxySSI screen title."),
    world("ios-world-03", "Bundle identity", "Verify and report the GalaxySSI application bundle identifier."),
    world("ios-world-04", "App version", "Read and report the installed GalaxySSI version."),
    world("ios-world-05", "App build", "Read and report the installed GalaxySSI build number."),
    world("ios-world-06", "Interface locale", "Read and report the current interface locale identifier."),
    world("ios-world-07", "Time zone", "Read and report the current time zone identifier."),
    world("ios-world-08", "Low power mode", "Read and report whether iOS Low Power Mode is enabled."),
    world("ios-world-09", "Device model", "Read and report this iOS device model."),
    world("ios-world-10", "System version", "Read and report the current iOS system version.")
  ]

  private static let immediateMemoryCases: [AgentBenchmarkCase] = [
    immediateMemory("immediate-memory-01", "Immediate identity", "Return the cross-session memory value for IM-01 only.", "GSSI-IM-NOVA"),
    immediateMemory("immediate-memory-02", "Immediate preference", "Return the cross-session memory value for IM-02 only.", "GSSI-IM-DARK"),
    immediateMemory("immediate-memory-03", "Immediate device", "Return the cross-session memory value for IM-03 only.", "GSSI-IM-PHONE"),
    immediateMemory("immediate-memory-04", "Immediate project", "Return the cross-session memory value for IM-04 only.", "GSSI-IM-PROJECT"),
    immediateMemory("immediate-memory-05", "Immediate knowledge", "Return the cross-session memory value for IM-05 only.", "GSSI-IM-KNOWLEDGE"),
    immediateMemory("immediate-memory-06", "Immediate workflow", "Return the cross-session memory value for IM-06 only.", "GSSI-IM-WORKFLOW"),
    immediateMemory("immediate-memory-07", "Immediate decision", "Return the cross-session memory value for IM-07 only.", "GSSI-IM-DECISION"),
    immediateMemory("immediate-memory-08", "Memory update", "Return the current IM-08 value, not the superseded value.", "GSSI-IM-CURRENT", "GSSI-IM-OLD"),
    immediateMemory("immediate-memory-09", "Entity disambiguation", "Return only the value belonging to IM-09-B, not IM-09-A.", "GSSI-IM-BETA", "GSSI-IM-ALPHA"),
    immediateMemory("immediate-memory-10", "Source tracing", "Return the provenance-linked cross-session memory value for IM-10 only.", "GSSI-IM-PROVENANCE")
  ]

  private static let longTermMemoryCases: [AgentBenchmarkCase] = [
    memory("memory-30-01", "30-day identity", "Return the value of memory fixture M30-01 without guessing.", 30, "GSSI-M30-ALPHA"),
    memory("memory-30-02", "30-day preference", "Return the value of memory fixture M30-02 without guessing.", 30, "GSSI-M30-BRAVO"),
    memory("memory-30-03", "30-day device", "Return the value of memory fixture M30-03 without guessing.", 30, "GSSI-M30-CHARLIE"),
    memory("memory-30-04", "30-day project", "Return the value of memory fixture M30-04 without guessing.", 30, "GSSI-M30-DELTA"),
    memory("memory-30-05", "30-day decision", "Return the value of memory fixture M30-05 without guessing.", 30, "GSSI-M30-ECHO"),
    memory("memory-90-01", "90-day identity", "Return the value of memory fixture M90-01 without guessing.", 90, "GSSI-M90-FOXTROT"),
    memory("memory-90-02", "90-day preference", "Return the value of memory fixture M90-02 without guessing.", 90, "GSSI-M90-GOLF"),
    memory("memory-90-03", "90-day device", "Return the value of memory fixture M90-03 without guessing.", 90, "GSSI-M90-HOTEL"),
    memory("memory-90-04", "90-day project", "Return the value of memory fixture M90-04 without guessing.", 90, "GSSI-M90-INDIA"),
    memory("memory-90-05", "90-day update", "Return the current value of memory fixture M90-05, not its retired value.", 90, "GSSI-M90-JULIET")
  ]

  private static let recoveryCases: [AgentBenchmarkCase] = [
    recovery("recovery-network-01", "Network recovery 1", "Complete the reliability echo after one network interruption. Return RECOVERED-NET-01 exactly once.", .networkLoss, "RECOVERED-NET-01"),
    recovery("recovery-network-02", "Network recovery 2", "Checkpoint the task and recover after a network interruption. Return RECOVERED-NET-02 exactly once.", .networkLoss, "RECOVERED-NET-02"),
    recovery("recovery-network-03", "Network recovery 3", "Execute a recoverable task across network loss. Return RECOVERED-NET-03 exactly once.", .networkLoss, "RECOVERED-NET-03"),
    recovery("recovery-process-01", "Process recovery 1", "Checkpoint before simulated process termination. Return RECOVERED-PROC-01 exactly once after recovery.", .processDeath, "RECOVERED-PROC-01"),
    recovery("recovery-process-02", "Process recovery 2", "Recover this task after simulated process termination. Return RECOVERED-PROC-02 exactly once.", .processDeath, "RECOVERED-PROC-02"),
    recovery("recovery-process-03", "Process recovery 3", "Remain idempotent across simulated process termination. Return RECOVERED-PROC-03 exactly once.", .processDeath, "RECOVERED-PROC-03"),
    recovery("recovery-doze-01", "Background recovery 1", "Recover after iOS background suspension. Return RECOVERED-IDLE-01 exactly once.", .doze, "RECOVERED-IDLE-01"),
    recovery("recovery-doze-02", "Background recovery 2", "Checkpoint and recover after iOS background suspension. Return RECOVERED-IDLE-02 exactly once.", .doze, "RECOVERED-IDLE-02"),
    recovery("recovery-reboot-01", "Restart recovery 1", "Recover after a device restart. Return RECOVERED-BOOT-01 exactly once.", .reboot, "RECOVERED-BOOT-01"),
    recovery("recovery-reboot-02", "Restart recovery 2", "Remain idempotent across a device restart. Return RECOVERED-BOOT-02 exactly once.", .reboot, "RECOVERED-BOOT-02")
  ]

  private static let multiAgentCases: [AgentBenchmarkCase] = [
    multi("multi-agent-01", "Implement and review", "Use two distinct Agents: one proposes an implementation and one independently reviews it, then merge the conclusion."),
    multi("multi-agent-02", "Research and challenge", "Use two distinct Agents: one researches and one seeks counterexamples, then merge the conclusion."),
    multi("multi-agent-03", "Plan and risk", "Use two distinct Agents: one decomposes a plan and one reviews risks, then merge the conclusion."),
    multi("multi-agent-04", "Code and test", "Use two distinct Agents: one designs code and one independently designs tests, then merge the conclusion."),
    multi("multi-agent-05", "Performance and UX", "Use two distinct Agents: one analyzes performance and one analyzes UX, then prioritize findings."),
    multi("multi-agent-06", "Security dual review", "Use two distinct Agents to independently assess one security design and identify agreement and disagreement."),
    multi("multi-agent-07", "Three-Agent review", "Use three distinct Agents for proposal, verification, and challenge, then return one synthesis.", agents: 3),
    multi("multi-agent-08", "Blind model review", "Use two distinct Agents independently, compare their hidden-identity results, and explain the selection."),
    multi("multi-agent-09", "Failure diagnosis", "Use two distinct Agents: one diagnoses root cause and one verifies the fix against regression."),
    multi("multi-agent-10", "Evidence merge", "Use two distinct Agents to provide evidence, deduplicate it, and return one traceable conclusion.")
  ]

  private static func quality(_ id: String, _ title: String, _ prompt: String, _ pattern: String) -> AgentBenchmarkCase {
    AgentBenchmarkCase(id: id, dimension: .taskQuality, title: title, prompt: prompt,
      expectation: AgentBenchmarkExpectation(requiredOutputPatterns: [pattern]))
  }

  private static func qualityJSON(
    _ id: String,
    _ title: String,
    _ prompt: String,
    _ fields: [String: String]
  ) -> AgentBenchmarkCase {
    AgentBenchmarkCase(id: id, dimension: .taskQuality, title: title, prompt: prompt,
      expectation: AgentBenchmarkExpectation(requiredJsonFields: fields))
  }

  private static func planning(_ id: String, _ title: String, _ prompt: String, sources: Bool = false) -> AgentBenchmarkCase {
    var evidence: Set<AgentOutcomeEvidenceKind> = [.finalResponse, .toolReceipt]
    if sources { evidence.insert(.verifiedSource) }
    return AgentBenchmarkCase(id: id, dimension: .planningAndTools, title: title, prompt: prompt,
      expectation: AgentBenchmarkExpectation(minimumOutputCharacters: 20, minimumPlanEvents: 1,
        minimumToolReceipts: 1, minimumVerifiedSources: sources ? 2 : 0, requiredEvidence: evidence))
  }

  private static func immediateMemory(
    _ id: String,
    _ title: String,
    _ prompt: String,
    _ expected: String,
    _ forbidden: String = ""
  ) -> AgentBenchmarkCase {
    AgentBenchmarkCase(id: id, dimension: .immediateMemory, title: title, prompt: prompt,
      expectation: AgentBenchmarkExpectation(
        requiredOutputPatterns: [NSRegularExpression.escapedPattern(for: expected)],
        forbiddenOutputPatterns: forbidden.isEmpty ? [] : [NSRegularExpression.escapedPattern(for: forbidden)],
        requiredEvidence: [.finalResponse, .memoryProvenance]
      ))
  }

  private static func world(_ id: String, _ title: String, _ prompt: String) -> AgentBenchmarkCase {
    AgentBenchmarkCase(id: id, dimension: .iosWorld, title: title, prompt: prompt,
      expectation: AgentBenchmarkExpectation(requiredEvidence: [.finalResponse, .programmaticVerifier],
        iosWorldTaskId: id, requireIOSObservedValuesInOutput: true))
  }

  private static func memory(_ id: String, _ title: String, _ prompt: String, _ days: Int, _ expected: String) -> AgentBenchmarkCase {
    AgentBenchmarkCase(id: id, dimension: .longTermMemory, title: title,
      prompt: "\(prompt) Use only provenance-linked memory written at least \(days) days ago.",
      expectation: AgentBenchmarkExpectation(requiredOutputPatterns: [NSRegularExpression.escapedPattern(for: expected)],
        requiredEvidence: [.finalResponse, .memoryProvenance], memoryHorizonDays: days))
  }

  private static func recovery(_ id: String, _ title: String, _ prompt: String, _ condition: AgentEvalCondition, _ expected: String) -> AgentBenchmarkCase {
    let escaped = NSRegularExpression.escapedPattern(for: expected)
    return AgentBenchmarkCase(id: id, dimension: .recovery, title: title, prompt: prompt,
      expectation: AgentBenchmarkExpectation(requiredOutputPatterns: [escaped],
        forbiddenOutputPatterns: ["(?s)(\(escaped).*){2,}"], requiredEvidence: [.finalResponse, .recoveryEvent],
        requiredCondition: condition))
  }

  private static func multi(_ id: String, _ title: String, _ prompt: String, agents: Int = 2) -> AgentBenchmarkCase {
    AgentBenchmarkCase(id: id, dimension: .multiAgent, title: title, prompt: prompt,
      expectation: AgentBenchmarkExpectation(minimumOutputCharacters: 40, minimumDistinctAgents: agents,
        minimumHandoffs: agents - 1))
  }
}
