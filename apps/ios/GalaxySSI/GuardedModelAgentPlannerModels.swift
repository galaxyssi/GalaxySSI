import Foundation

struct AgentModelPlanningInvocation: Codable, Equatable {
  var systemPrompt: String
  var prompt: String
  var nativeTools: [AgentNativeToolDescriptor]
  var request: AgentModelPlanningPromptRequest

  init(
    systemPrompt: String,
    prompt: String,
    nativeTools: [AgentNativeToolDescriptor],
    request: AgentModelPlanningPromptRequest
  ) {
    self.systemPrompt = systemPrompt
    self.prompt = prompt
    self.nativeTools = nativeTools
    self.request = request
  }

  enum CodingKeys: String, CodingKey {
    case systemPrompt = "system_prompt"
    case prompt
    case nativeTools = "native_tools"
    case request
  }
}

protocol AgentModelPlanningProviding {
  func rawPlan(invocation: AgentModelPlanningInvocation) async throws -> String
  func repairPlan(invocation: AgentModelPlanningInvocation) async throws -> String
}

extension AgentModelPlanningProviding {
  func repairPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    try await rawPlan(invocation: invocation)
  }
}

enum AgentModelPlanningProviderError: LocalizedError, Equatable {
  case unavailable(String)

  var errorDescription: String? {
    switch self {
    case .unavailable(let message):
      return message
    }
  }
}
