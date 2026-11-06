import Foundation

struct AgentGoalResultRequirement: Codable, Equatable {
  let id: String
  let description: String
  let outcomeIds: [String]
  let artifactPaths: [String]
  let answer: String

  enum CodingKeys: String, CodingKey {
    case id, description, answer
    case outcomeIds = "outcome_ids"
    case artifactPaths = "artifact_paths"
  }

  init?(json: AgentMcpJSONObject) {
    guard let id = json["id"]?.strictStringValue, Self.validId(id),
          let description = json["description"]?.strictStringValue,
          !description.isBlank, description.utf8.count <= 2_048,
          let answer = (json["answer"] ?? .string("")).strictStringValue, answer.utf8.count <= 16_000,
          let outcomes = Self.strings(json["outcome_ids"]), outcomes.allSatisfy(Self.validId),
          let artifacts = Self.strings(json["artifact_paths"]), artifacts.allSatisfy(AgentArtifactRequirement.validPath)
    else { return nil }
    self.id = id
    self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
    self.outcomeIds = outcomes
    self.artifactPaths = artifacts
    self.answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let json = try container.decode(AgentMcpJSONObject.self)
    guard let value = Self(json: json) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid requested result")
    }
    self = value
  }

  static func validId(_ id: String) -> Bool {
    id.range(of: #"\A[A-Za-z0-9_.-]{1,128}\z"#, options: .regularExpression) != nil
  }

  private static func strings(_ value: AgentMcpJSONValue?) -> [String]? {
    guard let value else { return [] }
    guard let list = value.arrayValue, list.count <= 32 else { return nil }
    let strings = list.compactMap(\.strictStringValue)
    guard strings.count == list.count, Set(strings).count == strings.count else { return nil }
    return strings
  }
}

enum AgentGoalResultEvidence {
  static let declarationGuidance = "List every requested result with an id and description before execution. Leave outcome_ids, artifact_paths and answer empty until observed. Do not substitute tool steps for deliverables."

  static func requiresDeclaration(for actions: [AgentAction]) -> Bool {
    actions.contains { action in
      guard action.kind == .callNativeTool else { return false }
      let tool = (action.parameters["tool_id"] ?? "").ifBlank(action.target)
      return AgentIOSHardwareNativeToolCatalog.executableToolIds.contains(tool) ||
        tool.hasPrefix("galaxyssi.agent_action.") ||
        tool == AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture ||
        tool == AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord
    }
  }

  static func missing(
    _ requirements: AgentCompletionRequirements?, finalAnswer: String, required: Bool
  ) -> [String] {
    guard let requirements, let results = requirements.results, !results.isEmpty else {
      return required ? [declarationGuidance] : []
    }
    let outcomes = Set((requirements.outcomes ?? []).map(\.id))
    let artifacts = Set((requirements.artifacts ?? []).map(\.path) + (requirements.fileArtifacts ?? []).map(\.path))
    var missing: [String] = []
    for result in results {
      let label = "Requested result \(result.id)"
      if result.outcomeIds.isEmpty && result.artifactPaths.isEmpty {
        missing.append("\(label) needs outcome_ids or artifact_paths bound to verified evidence")
      }
      for id in result.outcomeIds where !outcomes.contains(id) {
        missing.append("\(label) references undeclared outcome \(id)")
      }
      for path in result.artifactPaths where !artifacts.contains(path) {
        missing.append("\(label) references undeclared artifact \(path)")
      }
      if result.answer.isEmpty {
        missing.append("\(label) needs an evidence-grounded answer")
      } else if finalAnswer.range(of: result.answer, options: .literal) == nil {
        missing.append("\(label) is missing from the final answer; include its answer verbatim")
      }
    }
    return missing
  }
}
