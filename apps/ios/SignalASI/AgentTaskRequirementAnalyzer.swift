import Foundation

enum AgentTaskRequirementAnalyzer {
  static func analyze(_ goal: String) -> AgentTaskRequirements {
    let trustedGoal = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)
    let normalized = normalizeSearchText(trustedGoal)
    let tokens = searchTokens(trustedGoal)
    // Web tools are disclosed to the selected model; the host must not infer web use from keywords.
    let live = false
    let code = containsAny(normalized, codeTerms)
    let codeExecution = code &&
      containsAny(normalized, codeExecutionTerms) &&
      !AgentCodeDiscussionPolicy.isInformational(trustedGoal)
    let device = containsAny(normalized, deviceTerms)
    let screen = containsAny(normalized, screenTerms)
    let knowledge = containsAny(normalized, knowledgeTerms)
    let mcp = containsAny(normalized, mcpTerms)
    let skill = containsAny(normalized, skillTerms)
    let localOnly = containsAny(normalized, privateTerms)
    let complexReasoning = code ||
      normalized.count > 220 ||
      containsAny(normalized, qualityTerms) ||
      normalized.contains("architecture") ||
      normalized.contains("difficult") ||
      tokens.contains("analyze")
    var capabilities = Set<AgentCapability>()
    if live {
      capabilities.formUnion([.liveData, .research, .toolUse])
    }
    if code {
      capabilities.insert(.code)
      if codeExecution {
        capabilities.insert(.taskExecution)
      }
    }
    if device {
      capabilities.insert(.deviceControl)
    }
    if screen {
      capabilities.insert(.appNavigation)
    }
    if knowledge {
      capabilities.insert(.knowledgeSearch)
    }
    if mcp {
      capabilities.formUnion([.mcp, .toolUse])
    }
    if skill {
      capabilities.formUnion([.skill, .toolUse])
    }
    if complexReasoning {
      capabilities.insert(.reasoning)
    }
    let dataSensitivity: AgentDataSensitivity
    if containsAny(normalized, restrictedTerms) {
      dataSensitivity = .restricted
    } else if localOnly || containsAny(normalized, confidentialTerms) {
      dataSensitivity = .confidential
    } else {
      dataSensitivity = .personal
    }
    let mode: AgentRoutingMode
    if localOnly {
      mode = .private
    } else if containsAny(normalized, fastTerms) {
      mode = .fast
    } else if containsAny(normalized, economyTerms) {
      mode = .economy
    } else if containsAny(normalized, qualityTerms) {
      mode = .quality
    } else {
      mode = .balanced
    }
    let executionHorizon: AgentExecutionHorizon
    if containsAny(normalized, longRunningTerms) {
      executionHorizon = .longRunning
    } else if containsAny(normalized, backgroundTerms) {
      executionHorizon = .background
    } else {
      executionHorizon = .interactive
    }
    return AgentTaskRequirements(
      capabilities: capabilities,
      mode: mode,
      liveDataRequired: capabilities.contains(.liveData),
      localOnly: localOnly,
      complexReasoning: complexReasoning,
      estimatedInputTokens: max(64, goal.count / 3),
      dataSensitivity: dataSensitivity,
      executionHorizon: executionHorizon
    )
  }

  private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
    terms.contains { text.contains($0) }
  }

  private static let codeTerms = [
    "code", "coding", "python", "program", "script", "debug", "repository", "compile", "build", "codex",
    "android project", "software project", "codebase", "apk", "bug", "pull request", "git repository",
    "function", "unit test", "test case", "test scenario", "verify the program", "test the program", "implement", "api",
    "\u{4ee3}\u{7801}", "\u{7a0b}\u{5e8f}", "\u{811a}\u{672c}", "\u{51fd}\u{6570}", "\u{7f16}\u{7a0b}",
    "\u{5f00}\u{53d1}", "\u{5355}\u{5143}\u{6d4b}\u{8bd5}", "\u{6d4b}\u{8bd5}\u{7528}\u{4f8b}",
    "\u{6d4b}\u{8bd5}\u{573a}\u{666f}", "\u{8fd0}\u{884c}\u{9a8c}\u{8bc1}", "\u{7f16}\u{8bd1}",
    "\u{9879}\u{76ee}", "\u{4fee}\u{590d} bug"
  ]
  private static let codeExecutionTerms = [
    "write", "create", "implement", "develop", "build", "compile", "debug", "fix", "modify", "edit",
    "refactor", "run", "execute", "verify", "test", "clone", "checkout", "pull", "fetch", "commit", "push",
    "open pull request", "create pull request",
    "\u{5199}", "\u{521b}\u{5efa}", "\u{5b9e}\u{73b0}", "\u{5f00}\u{53d1}", "\u{6784}\u{5efa}",
    "\u{7f16}\u{8bd1}", "\u{8c03}\u{8bd5}", "\u{4fee}\u{590d}", "\u{4fee}\u{6539}", "\u{7f16}\u{8f91}",
    "\u{91cd}\u{6784}", "\u{8fd0}\u{884c}", "\u{6267}\u{884c}", "\u{9a8c}\u{8bc1}", "\u{6d4b}\u{8bd5}",
    "\u{514b}\u{9686}", "\u{68c0}\u{51fa}", "\u{62c9}\u{53d6}", "\u{63d0}\u{4ea4}", "\u{63a8}\u{9001}",
    "\u{521b}\u{5efa} pr", "\u{63d0}\u{4ea4} pr"
  ]
  private static let deviceTerms = [
    "home assistant", "smart home", "light", "scene", "device",
    "\u{667a}\u{80fd}\u{5bb6}\u{5c45}", "\u{5f00}\u{706f}", "\u{5173}\u{706f}",
    "\u{8bbe}\u{5907}", "\u{573a}\u{666f}"
  ]
  private static let screenTerms = [
    "screen", "tap", "click", "swipe", "open app",
    "\u{5c4f}\u{5e55}", "\u{70b9}\u{51fb}", "\u{6ed1}\u{52a8}",
    "\u{6253}\u{5f00} app"
  ]
  private static let knowledgeTerms = [
    "knowledge", "memory", "document", "pdf", "documentation", "docs", "doc",
    "\u{77e5}\u{8bc6}\u{5e93}", "\u{8bb0}\u{5fc6}", "\u{6587}\u{6863}"
  ]
  private static let mcpTerms = [
    "mcp", "model context protocol", "\u{4e0a}\u{4e0b}\u{6587}\u{534f}\u{8bae}"
  ]
  private static let skillTerms = [
    "skill", "skills", "\u{6280}\u{80fd}"
  ]
  private static let privateTerms = [
    "private", "local only", "locally only", "offline",
    "\u{9690}\u{79c1}", "\u{4ec5}\u{672c}\u{5730}", "\u{79bb}\u{7ebf}",
    "\u{5bc6}\u{7801}", "\u{79d8}\u{5bc6}"
  ]
  private static let fastTerms = [
    "fast", "quick", "low latency", "\u{5feb}\u{901f}", "\u{7acb}\u{5373}",
    "\u{4f4e}\u{5ef6}\u{8fdf}"
  ]
  private static let economyTerms = [
    "cheap", "save token", "few tokens", "economy",
    "\u{7701} token", "\u{7701}\u{8d39}\u{7528}", "\u{7ecf}\u{6d4e}"
  ]
  private static let qualityTerms = [
    "best", "strongest", "deep reasoning", "high quality", "quality",
    "\u{6700}\u{5f3a}", "\u{6700}\u{597d}", "\u{6df1}\u{5ea6}\u{601d}\u{8003}",
    "\u{9ad8}\u{8d28}\u{91cf}"
  ]
  private static let backgroundTerms = [
    "background", "later", "schedule", "monitor", "overnight",
    "\u{540e}\u{53f0}", "\u{7a0d}\u{540e}", "\u{5b9a}\u{65f6}",
    "\u{76d1}\u{63a7}", "\u{6574}\u{591c}"
  ]
  private static let longRunningTerms = [
    "long running", "keep running", "until complete",
    "\u{957f}\u{65f6}\u{95f4}", "\u{6301}\u{7eed}\u{8fd0}\u{884c}",
    "\u{76f4}\u{5230}\u{5b8c}\u{6210}"
  ]
  private static let confidentialTerms = [
    "sms", "contact", "calendar", "health", "medical", "private message",
    "private", "confidential", "password", "secret",
    "\u{77ed}\u{4fe1}", "\u{8054}\u{7cfb}\u{4eba}", "\u{65e5}\u{5386}",
    "\u{5065}\u{5eb7}", "\u{533b}\u{7597}", "\u{79c1}\u{4fe1}",
    "\u{9690}\u{79c1}", "\u{5bc6}\u{7801}", "\u{79d8}\u{5bc6}"
  ]
  private static let restrictedTerms = [
    "private key", "seed phrase", "biometric", "payment", "bank", "identity document", "restricted",
    "\u{79c1}\u{94a5}", "\u{52a9}\u{8bb0}\u{8bcd}", "\u{751f}\u{7269}\u{8bc6}\u{522b}",
    "\u{652f}\u{4ed8}", "\u{94f6}\u{884c}", "\u{8eab}\u{4efd}\u{8bc1}"
  ]
}
