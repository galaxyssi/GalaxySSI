import Foundation

enum AgentExecutionTaskKind: String, Codable, CaseIterable, Identifiable {
  case chat = "CHAT"
  case research = "RESEARCH"
  case artifact = "ARTIFACT"
  case build = "BUILD"
  case install = "INSTALL"
  case device = "DEVICE"

  var id: String { rawValue }
}

enum AgentExecutionReasoningEffort: String, Codable, CaseIterable, Identifiable {
  case low = "LOW"
  case medium = "MEDIUM"
  case high = "HIGH"

  var id: String { rawValue }
}

struct AgentExecutionProfile: Codable, Equatable {
  var taskKind: AgentExecutionTaskKind
  var reasoningEffort: AgentExecutionReasoningEffort
  var noProgressTimeoutMillis: Int64
  var maxSameFailureAttempts: Int
  var requiresArtifact: Bool
  var targetPlatform: String
  var verifyInstallation: Bool
  var taskIntent: AgentTaskIntent
  var taskIntentConfidence: Int
  var taskIntentSignals: [String]

  init(
    taskKind: AgentExecutionTaskKind,
    reasoningEffort: AgentExecutionReasoningEffort,
    noProgressTimeoutMillis: Int64,
    maxSameFailureAttempts: Int = 2,
    requiresArtifact: Bool = false,
    targetPlatform: String = "",
    verifyInstallation: Bool = false,
    taskIntent: AgentTaskIntent = .chat,
    taskIntentConfidence: Int = 100,
    taskIntentSignals: [String] = []
  ) {
    self.taskKind = taskKind
    self.reasoningEffort = reasoningEffort
    self.noProgressTimeoutMillis = noProgressTimeoutMillis
    self.maxSameFailureAttempts = maxSameFailureAttempts
    self.requiresArtifact = requiresArtifact
    self.targetPlatform = targetPlatform
    self.verifyInstallation = verifyInstallation
    self.taskIntent = taskIntent
    self.taskIntentConfidence = taskIntentConfidence
    self.taskIntentSignals = taskIntentSignals
  }

  enum CodingKeys: String, CodingKey {
    case taskKind = "task_kind"
    case reasoningEffort = "reasoning_effort"
    case noProgressTimeoutMillis = "no_progress_timeout_millis"
    case maxSameFailureAttempts = "max_same_failure_attempts"
    case requiresArtifact = "requires_artifact"
    case targetPlatform = "target_platform"
    case verifyInstallation = "verify_installation"
    case taskIntent = "task_intent"
    case taskIntentConfidence = "task_intent_confidence"
    case taskIntentSignals = "task_intent_signals"
  }

  static func forGoal(
    _ goal: String,
    hasAttachments: Bool = false
  ) -> AgentExecutionProfile {
    let normalized = goal
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let install = normalized.containsAny(installTerms)
    let build = normalized.containsAny(buildTerms)
    let artifactRequest = normalized.containsAny(artifactTerms)
    let research = normalized.containsAny(researchTerms)
    let intent = AgentTaskIntentClassifier.classify(
      goal: normalized,
      hasAttachments: hasAttachments
    )
    let device = intent.intent == .phoneControl &&
      intent.matchedSignals.contains("phone-control-action")
    let taskKind: AgentExecutionTaskKind
    if install {
      taskKind = .install
    } else if build {
      taskKind = .build
    } else if artifactRequest || hasAttachments {
      taskKind = .artifact
    } else if research {
      taskKind = .research
    } else if device {
      taskKind = .device
    } else {
      taskKind = .chat
    }
    let complex: Set<AgentExecutionTaskKind> = [.research, .artifact, .build, .install]
    let timeoutMillis: Int64
    switch taskKind {
    case .chat:
      timeoutMillis = 180_000
    case .device:
      timeoutMillis = 120_000
    case .research:
      timeoutMillis = 300_000
    case .artifact:
      timeoutMillis = 360_000
    case .build, .install:
      timeoutMillis = 420_000
    }
    return AgentExecutionProfile(
      taskKind: taskKind,
      reasoningEffort: complex.contains(taskKind) ? .medium : .low,
      noProgressTimeoutMillis: timeoutMillis,
      requiresArtifact: artifactRequest || [.build, .install].contains(taskKind),
      targetPlatform: normalized.containsAny(androidTerms) ? "android" : "",
      verifyInstallation: taskKind == .install,
      taskIntent: intent.intent,
      taskIntentConfidence: intent.confidence,
      taskIntentSignals: intent.matchedSignals
    )
  }

  var contract: String {
    var result = "GalaxySSI execution contract: task=\(taskKind.rawValue.lowercased()), intent=\(taskIntent.rawValue.lowercased()), reasoning_effort=\(reasoningEffort.rawValue.lowercased()). Use Plan -> Act -> Observe -> Replan -> Verify -> Finalize. "
    result += "Checkpoint useful work before long or risky actions. "
    result += "Do not repeat an unchanged failing approach. "
    if requiresArtifact {
      result += "A single deliverable remains in its native format; package a directory or multi-file project as ZIP. "
    }
    if verifyInstallation {
      result += "Only report installation or launch after the target runtime returns a verified execution receipt. "
    }
    result += "Do not report success without verification evidence."
    return result
  }

  private static let buildTerms = [
    "build", "compile", "implement", "develop", "write a program", "create an app",
    "create a game", "fix bug", "run tests",
    "\u{7f16}\u{8bd1}", "\u{6784}\u{5efa}", "\u{5f00}\u{53d1}", "\u{5b9e}\u{73b0}",
    "\u{5199}\u{4e00}\u{4e2a}\u{7a0b}\u{5e8f}", "\u{505a}\u{4e00}\u{4e2a}\u{6e38}\u{620f}",
    "\u{751f}\u{6210}\u{7a0b}\u{5e8f}", "\u{4fee}\u{590d} bug", "\u{8fd0}\u{884c}\u{6d4b}\u{8bd5}"
  ]
  private static let installTerms = [
    "install", "install and open", "install apk", "deploy to phone", "launch the app",
    "\u{5b89}\u{88c5}", "\u{5b89}\u{88c5}\u{5e76}\u{6253}\u{5f00}", "\u{5b89}\u{88c5} apk",
    "\u{5b89}\u{88c5}\u{5230}\u{624b}\u{673a}", "\u{7f16}\u{8bd1}\u{5e76}\u{5b89}\u{88c5}"
  ]
  private static let artifactTerms = [
    "return the file", "send the file", "export", "generate image", "create file",
    "downloadable", "zip project", "apk",
    "\u{53d1}\u{56de}\u{6587}\u{4ef6}", "\u{8fd4}\u{56de}\u{6587}\u{4ef6}", "\u{5bfc}\u{51fa}",
    "\u{751f}\u{6210}\u{56fe}\u{7247}", "\u{6253}\u{5305}", "\u{538b}\u{7f29}\u{5305}"
  ]
  private static let researchTerms = [
    "latest", "today", "news", "weather", "research", "search the web",
    "\u{6700}\u{65b0}", "\u{4eca}\u{5929}", "\u{65b0}\u{95fb}", "\u{5929}\u{6c14}",
    "\u{8c03}\u{67e5}", "\u{641c}\u{7d22}", "\u{8054}\u{7f51}"
  ]
  private static let androidTerms = [
    "android", "apk", "mobile app", "phone game", "on the phone",
    "\u{5b89}\u{5353}", "\u{624b}\u{673a} app", "\u{624b}\u{673a}\u{4e0a}\u{73a9}",
    "\u{624b}\u{673a}\u{6e38}\u{620f}", "\u{5b89}\u{88c5}\u{5230}\u{624b}\u{673a}"
  ]
}

private extension String {
  func containsAny(_ terms: [String]) -> Bool {
    terms.contains { contains($0) }
  }
}
