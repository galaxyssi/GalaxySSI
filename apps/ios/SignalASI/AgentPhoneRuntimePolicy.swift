import Foundation

enum AgentPhoneRuntimePolicy {
  static func shouldUsePhoneRuntime(goal: String) -> Bool {
    let normalized = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
    guard !normalized.isEmpty else { return false }
    guard !AgentCodeDiscussionPolicy.isInformational(normalized) else { return false }

    let isDevelopmentTask = developmentTerms.contains { normalized.contains($0) } &&
      creationTerms.contains { normalized.contains($0) }
    let isProjectReadTask = projectScopeTerms.contains { normalized.contains($0) } &&
      projectReadTerms.contains { normalized.contains($0) }
    guard isDevelopmentTask || isProjectReadTask else { return false }

    if phoneTerms.contains(where: { normalized.contains($0) }) {
      return true
    }
    if desktopTerms.contains(where: { normalized.contains($0) }) ||
      projectScopeTerms.contains(where: { normalized.contains($0) }) {
      return false
    }

    let isSelfContained = selfContainedTerms.contains { normalized.contains($0) }
    let isCodeArtifact = implicitPhoneCodeTerms.contains { normalized.contains($0) }
    return isSelfContained && isCodeArtifact && normalized.count <= maximumInteractiveGoalCharacters
  }

  static func isPhoneRuntimeTool(_ toolId: String) -> Bool {
    toolId.hasPrefix("signalasi.workspace.") ||
      toolId.hasPrefix("signalasi.runtime.") ||
      toolId.hasPrefix("signalasi.project.")
  }

  static func acceptsModelPlan(goal: String, actions: [AgentAction]) -> Bool {
    shouldUsePhoneRuntime(goal: goal) || !actions.contains { action in
      action.kind == .callNativeTool && isPhoneRuntimeTool(action.parameters["tool_id"] ?? "")
    }
  }

  private static let developmentTerms = [
    "python", "program", "programme", "code", "script", "app", "function", "algorithm",
    "write code", "create code", "run code", "verify code", "validate code", "test code", "execute code",
    "\u{7a0b}\u{5e8f}", "\u{4ee3}\u{7801}", "\u{811a}\u{672c}", "\u{51fd}\u{6570}", "\u{7b97}\u{6cd5}",
    "\u{5f00}\u{53d1}", "\u{7f16}\u{7a0b}"
  ]

  private static let creationTerms = [
    "write", "create", "make", "implement", "build", "generate", "fix", "debug", "run", "verify", "test",
    "\u{5199}", "\u{521b}\u{5efa}", "\u{751f}\u{6210}", "\u{5b9e}\u{73b0}", "\u{4fee}\u{590d}",
    "\u{8c03}\u{8bd5}", "\u{8fd0}\u{884c}", "\u{9a8c}\u{8bc1}", "\u{6d4b}\u{8bd5}"
  ]

  private static let phoneTerms = [
    "on this phone", "on the phone", "phone local", "phone project", "on-device", "locally on phone",
    "\u{624b}\u{673a}\u{672c}\u{673a}", "\u{5728}\u{624b}\u{673a}", "\u{672c}\u{673a}\u{6267}\u{884c}",
    "\u{672c}\u{5730}\u{6267}\u{884c}", "\u{672c}\u{4f53}\u{6267}\u{884c}", "\u{624b}\u{673a}\u{9879}\u{76ee}"
  ]

  private static let desktopTerms = [
    "desktop", "on pc", "on the pc", "on the computer", "use codex", "send to codex",
    "claude code", "hermes agent", "\u{5728}\u{7535}\u{8111}", "\u{7535}\u{8111}\u{4e0a}\u{6267}\u{884c}",
    "\u{684c}\u{9762}\u{7aef}", "\u{684c}\u{9762}\u{7248}", "\u{4ea4}\u{7ed9}codex", "\u{53d1}\u{7ed9}codex", "\u{4f7f}\u{7528}codex"
  ]

  private static let projectScopeTerms = [
    "repository", "repo", "phone project", "entire project", "whole project", "ios project", "xcode", "codebase", "workspace",
    "existing app", "existing application", "ios app", "backend", "frontend", "docker", "windows app", "desktop app",
    "build ipa", "release build", "github", "pull request", "offline recovery", "all features", "every feature",
    "ui responsiveness", "\u{9879}\u{76ee}", "\u{4ee3}\u{7801}\u{5e93}", "\u{4ed3}\u{5e93}", "\u{73b0}\u{6709}app",
    "\u{73b0}\u{6709}\u{5e94}\u{7528}", "\u{540e}\u{7aef}", "\u{524d}\u{7aef}", "\u{6240}\u{6709}\u{529f}\u{80fd}",
    "\u{5168}\u{90e8}\u{529f}\u{80fd}", "\u{5168}\u{9762}\u{6d4b}\u{8bd5}", "\u{79bb}\u{7ebf}\u{6062}\u{590d}", "\u{9875}\u{9762}\u{6d41}\u{7545}\u{5ea6}",
    "\u{6027}\u{80fd}\u{95ee}\u{9898}", "\u{7f16}\u{8bd1}ipa", "\u{6253}\u{5305}ipa", "\u{63d0}\u{4ea4}github"
  ]

  private static let projectReadTerms = [
    "continue", "inspect", "review", "status", "diff", "history", "log", "recent commits", "current branch",
    "\u{7ee7}\u{7eed}", "\u{68c0}\u{67e5}", "\u{67e5}\u{770b}", "\u{5ba1}\u{67e5}", "\u{72b6}\u{6001}", "\u{5dee}\u{5f02}",
    "\u{5386}\u{53f2}", "\u{63d0}\u{4ea4}\u{8bb0}\u{5f55}", "\u{5f53}\u{524d}\u{5206}\u{652f}"
  ]

  private static let implicitPhoneCodeTerms = [
    "python", "program", "programme", "code", "script", "function", "algorithm",
    "\u{7a0b}\u{5e8f}", "\u{4ee3}\u{7801}", "\u{811a}\u{672c}", "\u{51fd}\u{6570}", "\u{7b97}\u{6cd5}", "\u{7f16}\u{7a0b}"
  ]

  private static let selfContainedTerms = [
    "simple", "small", "single-file", "one-file", "standalone", "snippet",
    "\u{7b80}\u{5355}", "\u{5c0f}\u{578b}", "\u{5355}\u{6587}\u{4ef6}", "\u{72ec}\u{7acb}", "\u{4ee3}\u{7801}\u{7247}\u{6bb5}"
  ]

  private static let maximumInteractiveGoalCharacters = 4_000
}
