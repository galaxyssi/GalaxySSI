import CryptoKit
import Foundation

enum AgentIOSDesktopRemoteToolKind: String, Codable, CaseIterable, Identifiable {
  case systemStatus = "windows.system.status"
  case processList = "windows.process.list"
  case fileList = "workspace.file.list"
  case fileReadText = "workspace.file.read.text"
  case fileWriteText = "workspace.file.write.text"
  case fileSha256 = "workspace.file.sha256"
  case archiveCreate = "workspace.archive.create"
  case terminalRun = "terminal.run"
  case officeInspect = "office.document.inspect"
  case officeConvert = "office.document.convert"

  var id: String { rawValue }
}

protocol AgentIOSDesktopRemoteToolProviding {
  var implementationId: String { get }
  var transportId: String { get }
  func availability(kind: AgentIOSDesktopRemoteToolKind) -> AgentNativeToolAvailability
  func invoke(
    kind: AgentIOSDesktopRemoteToolKind,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult
}

struct AgentIOSUnavailableDesktopRemoteToolProvider: AgentIOSDesktopRemoteToolProviding {
  var implementationId: String = "galaxyssi.ios.desktop_remote_unconfigured"
  var transportId: String = "galaxyssi-link-v2"

  func availability(kind: AgentIOSDesktopRemoteToolKind) -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Waiting for a secure paired Desktop capability manifest"
    )
  }

  func invoke(
    kind: AgentIOSDesktopRemoteToolKind,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "desktop_remote_provider_unavailable",
      message: "iOS Desktop remote provider is not connected",
      retryable: true
    )
  }
}

enum AgentIOSDesktopRemoteNativeToolCatalog {
  static let systemStatus = "galaxyssi.desktop.windows.system.status"
  static let processList = "galaxyssi.desktop.windows.process.list"
  static let fileList = "galaxyssi.desktop.workspace.file.list"
  static let fileReadText = "galaxyssi.desktop.workspace.file.read.text"
  static let fileWriteText = "galaxyssi.desktop.workspace.file.write.text"
  static let fileSha256 = "galaxyssi.desktop.workspace.file.sha256"
  static let archiveCreate = "galaxyssi.desktop.workspace.archive.create"
  static let terminalRun = "galaxyssi.desktop.terminal.run"
  static let officeInspect = "galaxyssi.desktop.office.document.inspect"
  static let officeConvert = "galaxyssi.desktop.office.document.convert"

  static let version = "1.1.0"
  static let executorId = "galaxyssi.desktop_remote"
  static let readConsent = "galaxyssi.consent.desktop.read"
  static let executeConsent = "galaxyssi.consent.desktop.execute"
  static let linkPermission = "galaxyssi.scope.secure_paired_desktop_link"
  static let workspacePermission = "galaxyssi.scope.desktop_task_workspace"
  static let noAdditionalConsent = "galaxyssi.consent.none"

  static let orderedToolIds = [
    systemStatus,
    processList,
    fileList,
    fileReadText,
    fileWriteText,
    fileSha256,
    archiveCreate,
    terminalRun,
    officeInspect,
    officeConvert
  ]
  static let toolIds: Set<String> = Set(orderedToolIds)
  static let workspaceToolIds: Set<String> = [
    fileList,
    fileReadText,
    fileWriteText,
    fileSha256,
    archiveCreate,
    terminalRun,
    officeInspect,
    officeConvert
  ]
  static let alwaysConfirmToolIds: Set<String> = [terminalRun]

  static func definitions(
    provider: AgentIOSDesktopRemoteToolProviding = AgentIOSUnavailableDesktopRemoteToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    AgentIOSDesktopRemoteToolKind.allCases.map { kind in
      definition(provider: provider, kind: kind)
    }
  }

  static func kind(for toolId: String) -> AgentIOSDesktopRemoteToolKind? {
    switch toolId {
    case systemStatus:
      return .systemStatus
    case processList:
      return .processList
    case fileList:
      return .fileList
    case fileReadText:
      return .fileReadText
    case fileWriteText:
      return .fileWriteText
    case fileSha256:
      return .fileSha256
    case archiveCreate:
      return .archiveCreate
    case terminalRun:
      return .terminalRun
    case officeInspect:
      return .officeInspect
    case officeConvert:
      return .officeConvert
    default:
      return nil
    }
  }

  static func toolId(_ kind: AgentIOSDesktopRemoteToolKind) -> String {
    switch kind {
    case .systemStatus:
      return systemStatus
    case .processList:
      return processList
    case .fileList:
      return fileList
    case .fileReadText:
      return fileReadText
    case .fileWriteText:
      return fileWriteText
    case .fileSha256:
      return fileSha256
    case .archiveCreate:
      return archiveCreate
    case .terminalRun:
      return terminalRun
    case .officeInspect:
      return officeInspect
    case .officeConvert:
      return officeConvert
    }
  }

  static func title(_ kind: AgentIOSDesktopRemoteToolKind) -> String {
    switch kind {
    case .systemStatus:
      return "Read Windows system status"
    case .processList:
      return "List Windows processes"
    case .fileList:
      return "List Desktop workspace"
    case .fileReadText:
      return "Read Desktop workspace text"
    case .fileWriteText:
      return "Write Desktop workspace text"
    case .fileSha256:
      return "Hash Desktop workspace file"
    case .archiveCreate:
      return "Create Desktop workspace archive"
    case .terminalRun:
      return "Run Desktop workspace command"
    case .officeInspect:
      return "Inspect Office document"
    case .officeConvert:
      return "Convert Office document"
    }
  }

  private static func definition(
    provider: AgentIOSDesktopRemoteToolProviding,
    kind: AgentIOSDesktopRemoteToolKind
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: toolId(kind),
      version: version,
      title: title(kind),
      description: description(kind),
      location: .desktop,
      inputSchema: inputSchema(kind),
      outputSchema: outputSchema(),
      risk: risk(kind),
      capabilities: capabilities(kind),
      requiredPermissions: permissionRequirements(kind),
      requiredConsents: consentRequirements(kind),
      timeoutMillis: timeoutMillis(kind),
      idempotency: idempotency(kind),
      availability: provider.availability(kind: kind)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "implementation": provider.implementationId,
        "transport": provider.transportId,
        "platform": "ios_phone",
        "compatibility_source": "AgentDesktopRemoteNativeTools",
        "execution_target": "paired_desktop",
        "argument_policy": kind == .terminalRun ? "argv_no_shell" : "bounded_inputs"
      ]
    )
  }

  private static func description(_ kind: AgentIOSDesktopRemoteToolKind) -> String {
    switch kind {
    case .systemStatus:
      return "Reads bounded operating-system, CPU, and memory status from a paired Desktop."
    case .processList:
      return "Lists bounded process names, identifiers, and memory use without command lines."
    case .fileList:
      return "Lists bounded entries inside a paired Desktop task workspace."
    case .fileReadText:
      return "Reads bounded UTF-8 text from a paired Desktop task workspace."
    case .fileWriteText:
      return "Atomically writes bounded UTF-8 text in a paired Desktop task workspace."
    case .fileSha256:
      return "Calculates SHA-256 for a file in a paired Desktop task workspace."
    case .archiveCreate:
      return "Creates a bounded ZIP from explicit files in a paired Desktop workspace."
    case .terminalRun:
      return "Runs an allowlisted executable with an argument array and no command shell on a paired Desktop."
    case .officeInspect:
      return "Extracts bounded structure and text from XLSX, DOCX, or PPTX on a paired Desktop."
    case .officeConvert:
      return "Converts a Desktop workspace Office document to PDF, CSV, or text and verifies the artifact."
    }
  }

  private static func risk(_ kind: AgentIOSDesktopRemoteToolKind) -> AgentNativeToolRisk {
    switch kind {
    case .systemStatus, .processList, .fileList, .fileReadText, .fileSha256, .officeInspect:
      return .low
    case .fileWriteText, .archiveCreate, .officeConvert:
      return .medium
    case .terminalRun:
      return .high
    }
  }

  private static func idempotency(_ kind: AgentIOSDesktopRemoteToolKind) -> AgentNativeToolIdempotency {
    switch kind {
    case .fileWriteText, .archiveCreate, .terminalRun, .officeConvert:
      return .idempotencyKeyRequired
    case .systemStatus, .processList, .fileList, .fileReadText, .fileSha256, .officeInspect:
      return .idempotent
    }
  }

  private static func timeoutMillis(_ kind: AgentIOSDesktopRemoteToolKind) -> Int64 {
    switch kind {
    case .archiveCreate:
      return 60_000
    case .terminalRun:
      return 185_000
    case .officeConvert:
      return 90_000
    case .systemStatus, .processList, .fileList, .fileReadText, .fileWriteText, .fileSha256, .officeInspect:
      return 30_000
    }
  }

  private static func capabilities(_ kind: AgentIOSDesktopRemoteToolKind) -> Set<String> {
    switch kind {
    case .systemStatus:
      return ["windows.status.read"]
    case .processList:
      return ["windows.process.list"]
    case .fileList, .fileReadText:
      return ["desktop.workspace.read"]
    case .fileWriteText:
      return ["desktop.workspace.write"]
    case .fileSha256:
      return ["desktop.workspace.read", "hash.sha256"]
    case .archiveCreate:
      return ["desktop.workspace.read", "desktop.workspace.write", "archive.zip"]
    case .terminalRun:
      return ["desktop.terminal.execute", "desktop.workspace.read", "desktop.workspace.write"]
    case .officeInspect:
      return ["desktop.office.inspect", "desktop.workspace.read"]
    case .officeConvert:
      return ["desktop.office.convert", "desktop.workspace.read", "desktop.workspace.write"]
    }
  }

  private static func permissionRequirements(_ kind: AgentIOSDesktopRemoteToolKind) -> [AgentNativePermissionRequirement] {
    var requirements = [
      AgentNativePermissionRequirement(
        id: linkPermission,
        title: "Secure paired Desktop link",
        description: "Requires an online encrypted GalaxySSI Link session to the selected Desktop."
      )
    ]
    if workspaceToolIds.contains(toolId(kind)) {
      requirements.append(
        AgentNativePermissionRequirement(
          id: workspacePermission,
          title: "Desktop task workspace",
          description: "Restricts Desktop file, archive, Office, and terminal operations to the current task workspace."
        )
      )
    }
    return requirements.sorted { $0.id < $1.id }
  }

  private static func consentRequirements(_ kind: AgentIOSDesktopRemoteToolKind) -> [AgentNativeConsentRequirement] {
    if kind == .terminalRun {
      return [
        AgentNativeConsentRequirement(
          id: executeConsent,
          title: "Execute command on paired Desktop",
          description: "Approval is bound to the exact paired Desktop tool call."
        )
      ]
    }
    return [
      AgentNativeConsentRequirement(
        id: noAdditionalConsent,
        title: "No additional consent",
        description: "This paired Desktop tool follows the native descriptor risk and idempotency policy.",
        required: false
      )
    ]
  }

  private static func inputSchema(_ kind: AgentIOSDesktopRemoteToolKind) -> AgentMcpJSONObject {
    switch kind {
    case .systemStatus:
      return schema()
    case .processList:
      return schema([
        "query": stringSchema(maxLength: 128),
        "max_entries": integerSchema(minimum: 1, maximum: 200)
      ])
    case .fileList:
      return schema([
        "desktop_id": desktopIdSchema(),
        "path": pathSchema(),
        "recursive": boolSchema(),
        "max_entries": integerSchema(minimum: 1, maximum: 1_000)
      ])
    case .fileReadText:
      return schema([
        "desktop_id": desktopIdSchema(),
        "path": pathSchema(),
        "max_bytes": integerSchema(minimum: 1, maximum: 131_072)
      ], required: ["path"])
    case .fileWriteText:
      return schema([
        "desktop_id": desktopIdSchema(),
        "path": pathSchema(),
        "content": stringSchema(maxLength: 1_048_576),
        "mode": stringSchema(enumValues: ["create", "overwrite"]),
        "expected_sha256": stringSchema(maxLength: 64)
      ], required: ["path", "content", "mode"])
    case .fileSha256:
      return workspacePathSchema()
    case .archiveCreate:
      return schema([
        "desktop_id": desktopIdSchema(),
        "paths": arraySchema(itemSchema: pathSchema(), maxItems: 256),
        "output_path": pathSchema()
      ], required: ["paths", "output_path"])
    case .terminalRun:
      return schema([
        "desktop_id": desktopIdSchema(),
        "argv": arraySchema(itemSchema: stringSchema(maxLength: 1_024), maxItems: 64),
        "cwd": pathSchema(),
        "timeout_seconds": integerSchema(minimum: 1, maximum: 180)
      ], required: ["argv"])
    case .officeInspect:
      return schema([
        "desktop_id": desktopIdSchema(),
        "path": pathSchema(),
        "max_items": integerSchema(minimum: 1, maximum: 200)
      ], required: ["path"])
    case .officeConvert:
      return schema([
        "desktop_id": desktopIdSchema(),
        "path": pathSchema(),
        "output_format": stringSchema(enumValues: ["pdf", "csv", "txt"]),
        "output_path": pathSchema()
      ], required: ["path", "output_format"])
    }
  }

  private static func outputSchema() -> AgentMcpJSONObject {
    objectSchema([
      "desktop_id": stringSchema(maxLength: 160),
      "tool_id": stringSchema(maxLength: 160),
      "remote_receipt": objectSchema(additionalProperties: true),
      "remote_provenance": objectSchema(additionalProperties: true),
      "remote_artifacts": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 256),
      "remote_forwarded": boolSchema(),
      "workspace_id": stringSchema(maxLength: 160)
    ], additionalProperties: true)
  }

  private static func workspacePathSchema() -> AgentMcpJSONObject {
    schema([
      "desktop_id": desktopIdSchema(),
      "path": pathSchema()
    ], required: ["path"])
  }

  private static func desktopIdSchema() -> AgentMcpJSONObject {
    stringSchema(maxLength: 160)
  }

  private static func pathSchema() -> AgentMcpJSONObject {
    stringSchema(maxLength: 4_096)
  }

  private static func schema(
    _ properties: [String: AgentMcpJSONObject] = [:],
    required: [String] = []
  ) -> AgentMcpJSONObject {
    objectSchema(properties, required: required)
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

  private static func arraySchema(itemSchema: AgentMcpJSONObject, maxItems: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(itemSchema),
      "maxItems": .int(maxItems)
    ]
  }
}

struct AgentIOSDesktopRemoteNativeToolExecutor {
  var provider: AgentIOSDesktopRemoteToolProviding

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = try self.execute(invocation)
        try invocation.checkpoint()
        return result
      },
      verifier: { invocation, execution in
        try invocation.checkpoint()
        return self.verification(for: execution)
      }
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    guard let kind = AgentIOSDesktopRemoteNativeToolCatalog.kind(for: invocation.descriptor.id) else {
      return AgentNativeToolExecutionResult.failure(
        code: "desktop_remote_unknown_tool",
        message: "Unknown Desktop remote native tool."
      )
    }
    if AgentIOSDesktopRemoteNativeToolCatalog.workspaceToolIds.contains(invocation.descriptor.id),
       workspaceId(invocation.context).isEmpty {
      return AgentNativeToolExecutionResult.failure(
        code: "desktop_workspace_unavailable",
        message: "The current task has no Desktop workspace scope"
      )
    }
    try invocation.reportProgress(
      stage: "desktop_remote",
      message: AgentIOSDesktopRemoteNativeToolCatalog.title(kind),
      percent: 10
    )
    let execution = provider.invoke(kind: kind, input: invocation.input, invocation: invocation)
    guard execution.isSuccess else { return execution }

    var output = execution.output
    var metadata = execution.metadata
    let desktopId = firstNonEmpty([
      output["desktop_id"]?.stringValue,
      metadata["desktop_id"]?.stringValue,
      invocation.input["desktop_id"]?.stringValue
    ])
    if !desktopId.isEmpty {
      output["desktop_id"] = .string(desktopId)
      metadata["desktop_id"] = metadata["desktop_id"] ?? .string(desktopId)
    }
    let workspace = workspaceId(invocation.context)
    if !workspace.isEmpty {
      output["workspace_id"] = output["workspace_id"] ?? .string(workspace)
    }
    output["tool_id"] = output["tool_id"] ?? .string(invocation.descriptor.id)
    output["remote_artifacts"] = output["remote_artifacts"] ?? .array([])
    output["remote_forwarded"] = output["remote_forwarded"] ?? .bool(true)
    metadata["transport"] = metadata["transport"] ?? .string(provider.transportId)
    metadata["implementation"] = metadata["implementation"] ?? .string(provider.implementationId)
    metadata["execution_target"] = metadata["execution_target"] ?? .string("paired_desktop")
    metadata["remote_forwarded"] = metadata["remote_forwarded"] ?? .bool(true)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "\(AgentIOSDesktopRemoteNativeToolCatalog.title(kind)) completed" : execution.message,
      metadata: metadata
    )
  }

  private func verification(for execution: AgentNativeToolExecutionResult) -> AgentNativeToolVerification {
    let status = execution.metadata["remote_verification_status"]?.stringValue?.lowercased() ?? ""
    switch status {
    case "passed":
      return AgentNativeToolVerification(
        status: .passed,
        message: "Paired Desktop returned host-observed verification evidence",
        evidence: execution.metadata["remote_verification_evidence"]?.objectValue ?? [:]
      )
    case "failed":
      return AgentNativeToolVerification(
        status: .failed,
        message: "Paired Desktop verification failed",
        evidence: execution.metadata["remote_verification_evidence"]?.objectValue ?? [:]
      )
    default:
      return AgentNativeToolVerification(
        status: .skipped,
        message: "Paired Desktop did not claim verified completion"
      )
    }
  }

  private func workspaceId(_ context: AgentNativeToolInvocationContext) -> String {
    (context.attributes["workspace_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func firstNonEmpty(_ values: [String?]) -> String {
    values
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
  }
}
