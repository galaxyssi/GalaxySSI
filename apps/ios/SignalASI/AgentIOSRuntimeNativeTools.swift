import CryptoKit
import Foundation

enum AgentIOSOnDeviceRuntimeToolOperation: String, Codable, CaseIterable, Identifiable {
  case status
  case workspaceStatus = "workspace.status"
  case workspaceRollback = "workspace.rollback"
  case listPacks = "packs.list"
  case installPack = "packs.install"
  case softwareCatalog = "software.catalog"
  case softwareSearch = "software.search"
  case softwareInspect = "software.inspect"
  case softwareInstall = "software.install"
  case softwareRemove = "software.remove"
  case execute

  var id: String { rawValue }
}

protocol AgentIOSOnDeviceRuntimeToolProviding {
  var implementationId: String { get }
  var runtimeWorkspaceManager: AgentRuntimeProjectWorkspaceManager? { get }
  func availability(operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentNativeToolAvailability
  func invoke(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult
}

extension AgentIOSOnDeviceRuntimeToolProviding {
  var runtimeWorkspaceManager: AgentRuntimeProjectWorkspaceManager? { nil }
}

struct AgentIOSUnavailableOnDeviceRuntimeToolProvider: AgentIOSOnDeviceRuntimeToolProviding {
  var implementationId: String = "signalasi.ios.runtime_unconfigured"

  func availability(operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "iOS on-device runtime provider is not connected"
    )
  }

  func invoke(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "runtime_provider_unavailable",
      message: "iOS on-device runtime provider is not connected",
      retryable: true
    )
  }
}

enum AgentIOSOnDeviceRuntimeNativeToolCatalog {
  static let status = "signalasi.runtime.status"
  static let workspaceStatus = "signalasi.runtime.workspace.status"
  static let workspaceRollback = "signalasi.runtime.workspace.rollback"
  static let listPacks = "signalasi.runtime.packs.list"
  static let installPack = "signalasi.runtime.packs.install"
  static let softwareCatalog = "signalasi.runtime.software.catalog"
  static let softwareSearch = "signalasi.runtime.software.search"
  static let softwareInspect = "signalasi.runtime.software.inspect"
  static let softwareInstall = "signalasi.runtime.software.install"
  static let softwareRemove = "signalasi.runtime.software.remove"
  static let execute = "signalasi.runtime.execute"

  static let brokerExecutorId = "signalasi.ios_runtime_broker"
  static let workspaceExecutorId = "signalasi.ios_runtime_workspace"
  static let packManagerExecutorId = "signalasi.ios_runtime_pack_manager"
  static let runtimePermission = "signalasi.scope.ios_on_device_runtime"
  static let workspacePermission = "signalasi.scope.runtime_workspace"
  static let packInstallPermission = "signalasi.scope.signed_runtime_pack_install"
  static let noAdditionalConsent = "signalasi.consent.none"

  static let maxTimeoutMillis: Int64 = 30 * 60_000
  static let maxSoftwareResults: Int64 = 50
  static let softwareSourceAuto = "auto"
  static let softwareSourceRuntimePack = "runtime_pack"
  static let softwareSourceLinuxPackage = "linux_package"
  static let orderedToolIds = [
    status,
    workspaceStatus,
    workspaceRollback,
    listPacks,
    installPack,
    softwareCatalog,
    softwareSearch,
    softwareInspect,
    softwareInstall,
    softwareRemove,
    execute
  ]
  static let toolIds: Set<String> = Set(orderedToolIds)
  static let requiredPacks = [
    "linux-base",
    "python-uv",
    "node-js",
    "go",
    "rust",
    "cpp",
    "java",
    "browser-automation",
    "ffmpeg"
  ]

  static func definitions(
    provider: AgentIOSOnDeviceRuntimeToolProviding = AgentIOSUnavailableOnDeviceRuntimeToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    AgentIOSOnDeviceRuntimeToolOperation.allCases.map { operation in
      definition(provider: provider, operation: operation)
    }
  }

  static func operation(for toolId: String) -> AgentIOSOnDeviceRuntimeToolOperation? {
    switch toolId {
    case status:
      return .status
    case workspaceStatus:
      return .workspaceStatus
    case workspaceRollback:
      return .workspaceRollback
    case listPacks:
      return .listPacks
    case installPack:
      return .installPack
    case softwareCatalog:
      return .softwareCatalog
    case softwareSearch:
      return .softwareSearch
    case softwareInspect:
      return .softwareInspect
    case softwareInstall:
      return .softwareInstall
    case softwareRemove:
      return .softwareRemove
    case execute:
      return .execute
    default:
      return nil
    }
  }

  static func toolId(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> String {
    switch operation {
    case .status:
      return status
    case .workspaceStatus:
      return workspaceStatus
    case .workspaceRollback:
      return workspaceRollback
    case .listPacks:
      return listPacks
    case .installPack:
      return installPack
    case .softwareCatalog:
      return softwareCatalog
    case .softwareSearch:
      return softwareSearch
    case .softwareInspect:
      return softwareInspect
    case .softwareInstall:
      return softwareInstall
    case .softwareRemove:
      return softwareRemove
    case .execute:
      return execute
    }
  }

  static func title(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> String {
    switch operation {
    case .status:
      return "Inspect on-device runtime"
    case .workspaceStatus:
      return "Inspect the on-device project workspace"
    case .workspaceRollback:
      return "Restore an on-device project checkpoint"
    case .listPacks:
      return "List on-device runtime packs"
    case .installPack:
      return "Install a trusted on-device runtime pack"
    case .softwareCatalog:
      return "List compatible on-device software"
    case .softwareSearch:
      return "Search compatible on-device software"
    case .softwareInspect:
      return "Inspect compatible on-device software"
    case .softwareInstall:
      return "Install compatible on-device software"
    case .softwareRemove:
      return "Remove on-device Linux software"
    case .execute:
      return "Execute in the on-device Linux sandbox"
    }
  }

  private static func definition(
    provider: AgentIOSOnDeviceRuntimeToolProviding,
    operation: AgentIOSOnDeviceRuntimeToolOperation
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: toolId(operation),
      version: AgentPhoneNativeToolCatalog.version,
      title: title(operation),
      description: description(operation),
      location: .application,
      inputSchema: inputSchema(operation),
      outputSchema: outputSchema(operation),
      risk: risk(operation),
      capabilities: ["runtime.ios_local", "runtime.linux", "runtime.sandboxed"],
      requiredPermissions: permissionRequirements(operation),
      requiredConsents: [
        AgentNativeConsentRequirement(
          id: noAdditionalConsent,
          title: "No additional consent",
          description: "Runtime execution policy is enforced by the runtime broker and task workspace scope.",
          required: false
        )
      ],
      timeoutMillis: timeoutMillis(operation),
      idempotency: .nonIdempotent,
      availability: provider.availability(operation: operation)
    )
    var metadata = provenance(operation)
    metadata["implementation"] = provider.implementationId
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId(operation),
      provenanceMetadata: metadata
    )
  }

  private static func description(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> String {
    switch operation {
    case .status:
      return "Reports iOS-local Linux backend, language, toolchain, and media-pack readiness."
    case .workspaceStatus:
      return "Reports the current conversation project size and durable recovery checkpoints without exposing host paths."
    case .workspaceRollback:
      return "Atomically restores this conversation project from a durable checkpoint after an execution failure or unwanted change."
    case .listPacks:
      return "Lists iOS-local Linux, language, FFmpeg, and toolchain pack state."
    case .installPack:
      return "Downloads, verifies, and installs a signed Linux, language, or media runtime pack and its dependencies."
    case .softwareCatalog:
      return "Lists signed runtime packs and reports the iOS boundary for Linux package management."
    case .softwareSearch:
      return "Searches signed runtime packs by name, capability, and language alias."
    case .softwareInspect:
      return "Reports installation, compatibility, capability, and version details for one signed runtime pack."
    case .softwareInstall:
      return "Downloads, verifies, and installs a compatible signed runtime pack and its dependencies."
    case .softwareRemove:
      return "Reports the iOS boundary for unmanaged Linux package removal; signed runtime packs remain lifecycle-managed."
    case .execute:
      return "Runs bounded shell, language, build, test, or FFmpeg work in a persistent conversation project inside the iOS-local Linux runtime."
    }
  }

  private static func risk(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentNativeToolRisk {
    switch operation {
    case .status, .workspaceStatus, .listPacks, .softwareCatalog, .softwareSearch, .softwareInspect:
      return .low
    case .workspaceRollback, .installPack, .softwareInstall, .softwareRemove, .execute:
      return .medium
    }
  }

  private static func timeoutMillis(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> Int64 {
    switch operation {
    case .installPack, .softwareInstall, .execute:
      return maxTimeoutMillis
    case .status, .workspaceStatus, .workspaceRollback, .listPacks,
         .softwareCatalog, .softwareSearch, .softwareInspect, .softwareRemove:
      return 30_000
    }
  }

  private static func executorId(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> String {
    switch operation {
    case .workspaceStatus, .workspaceRollback:
      return workspaceExecutorId
    case .installPack, .softwareInstall:
      return packManagerExecutorId
    case .status, .listPacks, .softwareCatalog, .softwareSearch, .softwareInspect,
         .softwareRemove, .execute:
      return brokerExecutorId
    }
  }

  private static func provenance(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> [String: String] {
    var value = [
      "platform": "ios",
      "compatibility_source": "AgentOnDeviceRuntimeTools",
      "sandbox": "ios_local_linux_guest",
      "network_default": "disabled"
    ]
    if operation == .workspaceRollback {
      value["operation"] = "atomic_checkpoint_restore"
    }
    if operation == .installPack || operation == .softwareInstall {
      value["verification"] = "signed_catalog_and_pack"
    }
    if [.softwareCatalog, .softwareSearch, .softwareInspect, .softwareInstall, .softwareRemove].contains(operation) {
      value["software_sources"] = "runtime_pack,linux_package"
    }
    return value
  }

  private static func permissionRequirements(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> [AgentNativePermissionRequirement] {
    var requirements = [
      AgentNativePermissionRequirement(
        id: runtimePermission,
        title: "iOS on-device runtime",
        description: "Requires a configured local sandboxed runtime broker."
      )
    ]
    if operation == .workspaceStatus || operation == .workspaceRollback || operation == .execute {
      requirements.append(
        AgentNativePermissionRequirement(
          id: workspacePermission,
          title: "Runtime task workspace",
          description: "Restricts runtime files and checkpoints to the current conversation project workspace."
        )
      )
    }
    if operation == .installPack || operation == .softwareInstall {
      requirements.append(
        AgentNativePermissionRequirement(
          id: packInstallPermission,
          title: "Signed runtime pack install",
          description: "Requires signed runtime catalogs and verified pack archives."
        )
      )
    }
    return requirements.sorted { $0.id < $1.id }
  }

  private static func inputSchema(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentMcpJSONObject {
    switch operation {
    case .status, .workspaceStatus, .listPacks, .softwareCatalog:
      return objectSchema()
    case .workspaceRollback:
      return objectSchema([
        "checkpoint_id": stringSchema(maxLength: 128)
      ], required: ["checkpoint_id"])
    case .installPack:
      return objectSchema([
        "pack_id": stringSchema(enumValues: requiredPacks)
      ], required: ["pack_id"])
    case .softwareSearch:
      return objectSchema([
        "query": stringSchema(maxLength: 160),
        "source": softwareSourceSchema(),
        "limit": integerSchema(minimum: 1, maximum: maxSoftwareResults)
      ], required: ["query"])
    case .softwareInspect, .softwareInstall, .softwareRemove:
      return objectSchema([
        "software_id": stringSchema(maxLength: 128),
        "source": softwareSourceSchema()
      ], required: ["software_id"])
    case .execute:
      return objectSchema([
        "language": stringSchema(enumValues: AgentRuntimeLanguage.allCases.map(\.rawValue)),
        "source": stringSchema(maxLength: 256 * 1_024),
        "arguments": arraySchema(itemSchema: stringSchema(maxLength: 8 * 1_024), maxItems: 256),
        "timeout_ms": integerSchema(minimum: 100, maximum: maxTimeoutMillis),
        "network_enabled": boolSchema(),
        "allowed_network_domains": arraySchema(itemSchema: stringSchema(maxLength: 253), maxItems: 64),
        "artifact_paths": arraySchema(itemSchema: stringSchema(maxLength: 1_024), maxItems: 32),
        "phone_development_manifest": phoneDevelopmentManifestSchema()
      ], required: ["language"])
    }
  }

  private static func outputSchema(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentMcpJSONObject {
    switch operation {
    case .status:
      return objectSchema([
        "backend": stringSchema(maxLength: 64),
        "backend_ready": boolSchema(),
        "reason": stringSchema(maxLength: 2_048),
        "packs": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 128),
        "languages": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 128)
      ], additionalProperties: true)
    case .workspaceStatus:
      return objectSchema([
        "workspace_id": stringSchema(maxLength: 128),
        "workspace_file_count": integerSchema(minimum: 0),
        "workspace_bytes": integerSchema(minimum: 0),
        "checkpoints": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 128)
      ], additionalProperties: true)
    case .workspaceRollback:
      return objectSchema([
        "checkpoint_id": stringSchema(maxLength: 128),
        "workspace_file_count": integerSchema(minimum: 0),
        "workspace_bytes": integerSchema(minimum: 0),
        "workspace_disposition": stringSchema(maxLength: 64)
      ], additionalProperties: true)
    case .listPacks:
      return objectSchema([
        "packs": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 128)
      ], required: ["packs"], additionalProperties: true)
    case .installPack:
      return objectSchema([
        "requested_pack": stringSchema(enumValues: requiredPacks),
        "installed": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 128)
      ], additionalProperties: true)
    case .softwareCatalog:
      return objectSchema([
        "architecture": stringSchema(maxLength: 64),
        "linux_ready": boolSchema(),
        "sources": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 8),
        "software": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 128)
      ], additionalProperties: true)
    case .softwareSearch:
      return objectSchema([
        "query": stringSchema(maxLength: 160),
        "results": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: maxSoftwareResults),
        "source_errors": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 8)
      ], additionalProperties: true)
    case .softwareInspect, .softwareInstall, .softwareRemove:
      return objectSchema(additionalProperties: true)
    case .execute:
      return objectSchema([
        "exit_code": integerSchema(minimum: -1),
        "stdout": stringSchema(maxLength: 1_048_576),
        "stderr": stringSchema(maxLength: 1_048_576),
        "duration_ms": integerSchema(minimum: 0),
        "workspace_file_count": integerSchema(minimum: 0),
        "workspace_bytes": integerSchema(minimum: 0),
        "checkpoint_id": stringSchema(maxLength: 128),
        "workspace_disposition": stringSchema(maxLength: 64),
        "artifacts": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 256),
        "execution_receipt": objectSchema(additionalProperties: true)
      ], additionalProperties: true)
    }
  }

  private static func objectSchema(
    _ properties: [String: AgentMcpJSONObject] = [:],
    required: [String] = [],
    additionalProperties: Bool = false
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties.mapValues { .object($0) }),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(additionalProperties)
    ]
  }

  private static func stringSchema(
    maxLength: Int64? = nil,
    enumValues: [String] = []
  ) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("string")]
    if let maxLength { schema["maxLength"] = .int(maxLength) }
    if !enumValues.isEmpty {
      schema["enum"] = .array(enumValues.map(AgentMcpJSONValue.string))
    }
    return schema
  }

  private static func integerSchema(minimum: Int64, maximum: Int64? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = [
      "type": .string("integer"),
      "minimum": .int(minimum)
    ]
    if let maximum { schema["maximum"] = .int(maximum) }
    return schema
  }

  private static func boolSchema() -> AgentMcpJSONObject {
    ["type": .string("boolean")]
  }

  private static func softwareSourceSchema() -> AgentMcpJSONObject {
    stringSchema(enumValues: [
      softwareSourceAuto,
      softwareSourceRuntimePack,
      softwareSourceLinuxPackage
    ])
  }

  private static func phoneDevelopmentManifestSchema() -> AgentMcpJSONObject {
    objectSchema([
      "schema": stringSchema(enumValues: [AgentPhoneDevelopmentManifest.schema]),
      "decision_summary": stringSchema(maxLength: 600),
      "language": stringSchema(enumValues: [AgentRuntimeLanguage.python.rawValue]),
      "entry_file": stringSchema(maxLength: 160),
      "files": arraySchema(
        itemSchema: objectSchema([
          "path": stringSchema(maxLength: 160),
          "content": stringSchema(maxLength: 128 * 1_024)
        ], required: ["path", "content"]),
        maxItems: 64
      ),
      "required_packs": arraySchema(itemSchema: stringSchema(maxLength: 64), maxItems: 8),
      "artifact_paths": arraySchema(itemSchema: stringSchema(maxLength: 1_024), maxItems: 16)
    ], required: ["schema", "decision_summary", "language", "entry_file", "files"])
  }

  private static func arraySchema(itemSchema: AgentMcpJSONObject, maxItems: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(itemSchema),
      "maxItems": .int(maxItems)
    ]
  }
}

struct AgentIOSOnDeviceRuntimeNativeToolExecutor {
  private struct WorkspaceTransaction {
    var workspaceId: String
    var checkpointId: String
  }

  var provider: AgentIOSOnDeviceRuntimeToolProviding
  private var workspaceManager: AgentRuntimeProjectWorkspaceManager?

  init(
    provider: AgentIOSOnDeviceRuntimeToolProviding,
    workspaceManager: AgentRuntimeProjectWorkspaceManager? = nil
  ) {
    self.provider = provider
    self.workspaceManager = workspaceManager ?? provider.runtimeWorkspaceManager
  }

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = try self.execute(invocation)
        try invocation.checkpoint()
        return result
      }
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    guard let operation = AgentIOSOnDeviceRuntimeNativeToolCatalog.operation(for: invocation.descriptor.id) else {
      return AgentNativeToolExecutionResult.failure(
        code: "runtime_unknown_tool",
        message: "Unknown on-device runtime native tool."
      )
    }
    try invocation.reportProgress(
      stage: "runtime",
      message: AgentIOSOnDeviceRuntimeNativeToolCatalog.title(operation),
      percent: 10
    )
    let effectiveInput: AgentMcpJSONObject
    do {
      effectiveInput = try AgentPhoneDevelopmentManifestCodec.materializedInput(invocation.input)
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_phone_development_manifest",
        message: error.localizedDescription
      )
    }
    let transaction: WorkspaceTransaction?
    do {
      transaction = try beginTransaction(operation: operation, invocation: invocation)
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "runtime_workspace_checkpoint_failed",
        message: error.localizedDescription.ifBlank("iOS runtime workspace checkpoint could not be created"),
        retryable: true
      )
    }
    let execution = provider.invoke(operation: operation, input: effectiveInput, invocation: invocation)
    var output = execution.output
    let workspace = workspaceId(invocation.context)
    if let transaction {
      output["checkpoint_id"] = output["checkpoint_id"] ?? .string(transaction.checkpointId)
      let disposition: AgentRuntimeProjectWorkspaceDisposition
      if execution.isSuccess {
        disposition = .committed
      } else {
        disposition = rollback(transaction: transaction)
      }
      output["workspace_disposition"] = output["workspace_disposition"] ?? .string(disposition.rawValue)
      if let manager = workspaceManager, let status = try? manager.workspaceStatus(workspace) {
        output["workspace_file_count"] = output["workspace_file_count"] ?? .int(Int64(status.fileCount))
        output["workspace_bytes"] = output["workspace_bytes"] ?? .int(status.totalBytes)
      }
      if !execution.isSuccess, let error = execution.error {
        var details = error.details
        details["checkpoint_id"] = .string(transaction.checkpointId)
        details["workspace_disposition"] = output["workspace_disposition"] ?? .string(AgentRuntimeProjectWorkspaceDisposition.unchanged.rawValue)
        return AgentNativeToolExecutionResult(
          output: output,
          message: execution.message,
          metadata: execution.metadata,
          error: AgentNativeToolError(
            code: error.code,
            message: error.message,
            retryable: error.retryable,
            details: details
          )
        )
      }
    }
    guard execution.isSuccess else { return execution }
    switch operation {
    case .workspaceStatus, .workspaceRollback, .execute:
      output["workspace_id"] = output["workspace_id"] ?? .string(workspace)
    case .listPacks:
      output["packs"] = output["packs"] ?? .array([])
    case .installPack:
      output["requested_pack"] = output["requested_pack"] ?? invocation.input["pack_id"] ?? .string("")
      output["installed"] = output["installed"] ?? .array([])
    case .softwareCatalog:
      output["software"] = output["software"] ?? .array([])
      output["sources"] = output["sources"] ?? .array([])
    case .softwareSearch:
      output["results"] = output["results"] ?? .array([])
      output["source_errors"] = output["source_errors"] ?? .array([])
    case .softwareInspect, .softwareInstall, .softwareRemove:
      output["software_id"] = output["software_id"] ?? invocation.input["software_id"] ?? .string("")
    case .status:
      output["backend"] = output["backend"] ?? .string("ios_local")
    }
    if operation == .execute {
      output["artifacts"] = output["artifacts"] ?? .array([])
      output["workspace_disposition"] = output["workspace_disposition"] ?? .string("preserved")
    }
    var metadata = execution.metadata
    metadata["implementation"] = metadata["implementation"] ?? .string(provider.implementationId)
    metadata["platform"] = metadata["platform"] ?? .string("ios")
    metadata["sandbox"] = metadata["sandbox"] ?? .string("ios_local_linux_guest")
    metadata["network_default"] = metadata["network_default"] ?? .string("disabled")
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "\(AgentIOSOnDeviceRuntimeNativeToolCatalog.title(operation)) completed" : execution.message,
      metadata: metadata
    )
  }

  private func beginTransaction(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    invocation: AgentNativeToolInvocation
  ) throws -> WorkspaceTransaction? {
    guard operation == .execute,
          provider.availability(operation: .execute).status == .available,
          let workspaceManager else { return nil }
    let workspaceId = workspaceId(invocation.context)
    let digest = SHA256.hash(data: Data(invocation.context.invocationId.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    let checkpointId = "pre-\(digest.prefix(24))"
    _ = try workspaceManager.checkpoint(
      workspaceId: workspaceId,
      checkpointId: checkpointId,
      byteLimit: maxTransactionBytes
    )
    return WorkspaceTransaction(workspaceId: workspaceId, checkpointId: checkpointId)
  }

  private func rollback(transaction: WorkspaceTransaction) -> AgentRuntimeProjectWorkspaceDisposition {
    guard let workspaceManager else { return .unchanged }
    do {
      _ = try workspaceManager.rollback(
        workspaceId: transaction.workspaceId,
        checkpointId: transaction.checkpointId,
        byteLimit: maxTransactionBytes
      )
      return .rolledBack
    } catch {
      return .rollbackFailed
    }
  }

  private func workspaceId(_ context: AgentNativeToolInvocationContext) -> String {
    let values = [
      context.attributes["workspace_id"],
      context.turnId,
      context.conversationId,
      context.invocationId
    ]
    return values
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? "default"
  }

  private let maxTransactionBytes: Int64 = 512 * 1_024 * 1_024
}
