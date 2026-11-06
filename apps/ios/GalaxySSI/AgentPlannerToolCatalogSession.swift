import Foundation

final class AgentPlannerToolCatalogSession {
  static let operation = "planner-tool-catalog:v1"

  private let scope: AgentModelLoopScope
  private let registry: AgentNativeToolRegistry
  private let manifestHash: String
  private let contracts: [String: AgentNativeToolDescriptor]
  private let lock = NSLock()
  private var observedMessageCount = 0

  init(scope: AgentModelLoopScope, registry: AgentNativeToolRegistry) {
    self.scope = scope
    self.registry = registry
    manifestHash = AgentModelToolProtocolJSON.sha256(registry.catalogJson(
      additionalDescriptors: [AgentModelObservationHistory.descriptor], useRegisteredContracts: true))
    contracts = Dictionary(uniqueKeysWithValues: registry.registeredContracts().map { ($0.id, $0) })
  }

  func providerCatalog(_ request: AgentModelRequest) throws -> [AgentNativeToolDescriptor] {
    lock.lock()
    defer { lock.unlock() }
    guard request.sessionId == scope.sessionId, request.conversationId == scope.conversationId,
          request.turnId == scope.turnId, request.taskId == scope.taskId,
          request.workspaceId == scope.workspaceId, request.loopId == scope.loopId,
          request.callerId == scope.callerId, request.toolManifestSha256 == manifestHash,
          request.messages.count >= observedMessageCount else {
      throw AgentModelLoopRecoveryError(code: "planner_provider_catalog_owner_changed")
    }
    guard registry.ids() == Set(contracts.keys) else {
      throw AgentModelLoopRecoveryError(code: "planner_tool_contracts_changed")
    }
    if request.messages.dropFirst(observedMessageCount).compactMap(\.toolResult).contains(where: refreshesReadiness) {
      registry.refreshAvailability()
    }
    observedMessageCount = request.messages.count
    return registry.descriptors().filter { $0.availability.status == .available }
  }

  private func refreshesReadiness(_ result: AgentModelToolResultContent) -> Bool {
    guard let contract = contracts[result.toolId], let native = result.nativeResult,
          !native.receipt.replayed else { return false }
    if result.toolId == AgentIOSOnDeviceRuntimeNativeToolCatalog.status { return true }
    return contract.effect != .readOnly &&
      !(contract.effect == nil && contract.concurrency == .parallelReadOnly) &&
      [.succeeded, .failed, .verificationFailed, .timedOut].contains(native.status)
  }
}
