import Foundation

enum GlobalGoalProgressState: String, Codable, CaseIterable, Identifiable {
  case active = "ACTIVE"
  case completed = "COMPLETED"
  case blocked = "BLOCKED"
  case paused = "PAUSED"

  var id: String { rawValue }
}

struct GlobalModelUnderstanding: Codable, Equatable {
  var topic: String
  var project: String
  var relatedTopics: [String]
  var intent: String
  var entities: Set<String>
  var goals: [String]
  var tasks: [String]
  var decisions: [String]
  var preferences: [String]
  var risks: [String]
  var opportunities: [String]
  var researchQuestions: [String]
  var goalDependencies: [GlobalGoalDependencyProposal]
  var actions: [GlobalAutonomousAction]
  var userInsight: String
  var goalState: GlobalGoalProgressState
  var progressSummary: String
  var nextCheckHours: Int
  var confidence: Double

  var meaningful: Bool {
    !topic.isEmpty ||
      !project.isEmpty ||
      !relatedTopics.isEmpty ||
      !goals.isEmpty ||
      !tasks.isEmpty ||
      !decisions.isEmpty ||
      !preferences.isEmpty ||
      !risks.isEmpty ||
      !opportunities.isEmpty ||
      !researchQuestions.isEmpty ||
      !goalDependencies.isEmpty ||
      !actions.isEmpty ||
      !userInsight.isEmpty ||
      !progressSummary.isEmpty ||
      goalState != .active
  }

  init(
    topic: String = "",
    project: String = "",
    relatedTopics: [String] = [],
    intent: String = "",
    entities: Set<String> = [],
    goals: [String] = [],
    tasks: [String] = [],
    decisions: [String] = [],
    preferences: [String] = [],
    risks: [String] = [],
    opportunities: [String] = [],
    researchQuestions: [String] = [],
    goalDependencies: [GlobalGoalDependencyProposal] = [],
    actions: [GlobalAutonomousAction] = [],
    userInsight: String = "",
    goalState: GlobalGoalProgressState = .active,
    progressSummary: String = "",
    nextCheckHours: Int = 24,
    confidence: Double = 0
  ) {
    self.topic = Self.clean(topic, limit: 160)
    self.project = Self.clean(project, limit: 160)
    self.relatedTopics = Self.cleanArray(relatedTopics, limit: 16, itemLimit: 160)
    self.intent = Self.clean(intent, limit: 120)
    self.entities = Set(Self.cleanArray(Array(entities), limit: 48, itemLimit: 160))
    self.goals = Self.cleanArray(goals, limit: 16, itemLimit: 1_000)
    self.tasks = Self.cleanArray(tasks, limit: 32, itemLimit: 1_000)
    self.decisions = Self.cleanArray(decisions, limit: 16, itemLimit: 1_000)
    self.preferences = Self.cleanArray(preferences, limit: 16, itemLimit: 1_000)
    self.risks = Self.cleanArray(risks, limit: 16, itemLimit: 1_000)
    self.opportunities = Self.cleanArray(opportunities, limit: 16, itemLimit: 1_000)
    self.researchQuestions = Self.cleanArray(researchQuestions, limit: 16, itemLimit: 1_000)
    self.goalDependencies = Array(goalDependencies.prefix(32))
    self.actions = Array(actions.prefix(32))
    self.userInsight = Self.clean(userInsight, limit: 2_000)
    self.goalState = goalState
    self.progressSummary = Self.clean(progressSummary, limit: 2_000)
    self.nextCheckHours = max(1, min(nextCheckHours, 24 * 30))
    self.confidence = min(max(confidence, 0), 1)
  }

  enum CodingKeys: String, CodingKey {
    case topic
    case project
    case relatedTopics
    case intent
    case entities
    case goals
    case tasks
    case decisions
    case preferences
    case risks
    case opportunities
    case researchQuestions
    case goalDependencies
    case actions
    case userInsight
    case goalState
    case progressSummary
    case nextCheckHours
    case confidence
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      topic: try container.decodeIfPresent(String.self, forKey: .topic) ?? "",
      project: try container.decodeIfPresent(String.self, forKey: .project) ?? "",
      relatedTopics: try container.decodeIfPresent([String].self, forKey: .relatedTopics) ?? [],
      intent: try container.decodeIfPresent(String.self, forKey: .intent) ?? "",
      entities: try container.decodeIfPresent(Set<String>.self, forKey: .entities) ?? [],
      goals: try container.decodeIfPresent([String].self, forKey: .goals) ?? [],
      tasks: try container.decodeIfPresent([String].self, forKey: .tasks) ?? [],
      decisions: try container.decodeIfPresent([String].self, forKey: .decisions) ?? [],
      preferences: try container.decodeIfPresent([String].self, forKey: .preferences) ?? [],
      risks: try container.decodeIfPresent([String].self, forKey: .risks) ?? [],
      opportunities: try container.decodeIfPresent([String].self, forKey: .opportunities) ?? [],
      researchQuestions: try container.decodeIfPresent([String].self, forKey: .researchQuestions) ?? [],
      goalDependencies: try container.decodeIfPresent([GlobalGoalDependencyProposal].self, forKey: .goalDependencies) ?? [],
      actions: try container.decodeIfPresent([GlobalAutonomousAction].self, forKey: .actions) ?? [],
      userInsight: try container.decodeIfPresent(String.self, forKey: .userInsight) ?? "",
      goalState: try container.decodeIfPresent(GlobalGoalProgressState.self, forKey: .goalState) ?? .active,
      progressSummary: try container.decodeIfPresent(String.self, forKey: .progressSummary) ?? "",
      nextCheckHours: try container.decodeIfPresent(Int.self, forKey: .nextCheckHours) ?? 24,
      confidence: try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
    )
  }

  private static func cleanArray(
    _ values: [String],
    limit: Int,
    itemLimit: Int
  ) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      let clean = clean(value, limit: itemLimit)
      let key = GlobalAgentText.normalize(clean)
      guard !clean.isEmpty, seen.insert(key).inserted else { continue }
      result.append(clean)
      if result.count >= limit { break }
    }
    return result
  }

  private static func clean(_ value: String, limit: Int) -> String {
    String(value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .prefix(limit))
  }
}
