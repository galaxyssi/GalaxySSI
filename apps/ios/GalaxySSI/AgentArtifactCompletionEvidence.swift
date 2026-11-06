import CryptoKit
import Darwin
import Foundation

struct AgentArtifactRequirement: Codable, Equatable, Hashable {
  let path: String
  let sourceSha256: String
  let workspaceId: String

  init?(path: String, sourceSha256: String = "", workspaceId: String = "") {
    guard Self.validPath(path), sourceSha256.isEmpty || Self.validDigest(sourceSha256),
          workspaceId.utf8.count <= 256, workspaceId == workspaceId.trimmingCharacters(in: .whitespacesAndNewlines),
          workspaceId.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
    self.path = path
    self.sourceSha256 = sourceSha256.lowercased()
    self.workspaceId = workspaceId
  }

  static func validPath(_ path: String) -> Bool {
    guard !path.isBlank, path.utf8.count <= 4_096, !path.contains("\\"), !path.contains(":"),
          path.rangeOfCharacter(from: .controlCharacters) == nil,
          case .success(let segments) = AgentWorkspaceFilePathPolicy.normalizeRelativePath(path, allowRoot: false)
    else { return false }
    return segments.joined(separator: "/") == path
  }

  static func validDigest(_ digest: String) -> Bool {
    digest.range(of: #"\A[0-9a-fA-F]{64}\z"#, options: .regularExpression) != nil
  }

  enum CodingKeys: String, CodingKey {
    case path
    case sourceSha256 = "source_sha256"
    case workspaceId = "workspace_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let path = try container.decode(String.self, forKey: .path)
    guard let value = try Self(path: path,
      sourceSha256: container.decodeIfPresent(String.self, forKey: .sourceSha256) ?? "",
      workspaceId: container.decodeIfPresent(String.self, forKey: .workspaceId) ?? "") else {
      throw DecodingError.dataCorruptedError(forKey: .path, in: container, debugDescription: "Invalid artifact requirement")
    }
    self = value
  }
}

struct AgentArtifactOperationReceipt: Codable, Equatable {
  static let metadataKey = "host_artifact_receipt"

  let toolId: String
  let workspaceId: String
  let conversationId: String
  let turnId: String
  let invocationId: String
  var originalInvocationId: String? = nil
  let replayed: Bool
  let succeeded: Bool
  let inspection: Inspection?

  struct Inspection: Codable, Equatable {
    let path: String
    let digest: String
    let size: Int64

    var artifact: AgentMcpJSONObject {
      ["relative_path": .string(path), "sha256": .string(digest.lowercased()),
       "size_bytes": .int(size), "artifact_kind": .string(AgentVerifiedArtifactSnapshot.kind), "file_count": .int(1)]
    }
  }

  static func from(_ result: AgentActionResult) -> Self? {
    guard let json = result.metadata[metadataKey] else { return nil }
    return try? JSONDecoder().decode(Self.self, from: Data(json.utf8))
  }

  static func make(result: AgentNativeToolResult, input: AgentMcpJSONObject,
                   context: AgentNativeToolInvocationContext) -> Self? {
    let toolId = result.provenance.toolId
    guard AgentArtifactCompletionEvidence.tracked(toolId) else { return nil }
    let hostWorkspace = context.attributes["workspace_id"] ?? ""
    let workspace = AgentArtifactCompletionEvidence.scopeId(tool: toolId, input: input, workspace: hostWorkspace)
    let scopeMatches = result.output.string("workspace_id") == hostWorkspace
    let inspection: Inspection?
    if toolId == AgentPhoneNativeToolCatalog.workspaceExport,
       let item = result.output["artifacts"]?.arrayValue?.first?.objectValue,
       let readback = item["openability"]?.objectValue,
       readback.string("status") == "verified", readback.string("sha256") == item.string("sha256"),
       item.string("relative_path") == input.string("path"),
       result.output.string("artifact_workspace_id") == workspace,
       let size = item["size_bytes"]?.intValue, size >= 0 {
      inspection = Inspection(path: item.string("relative_path"), digest: item.string("sha256"), size: size)
    } else if AgentArtifactCompletionEvidence.sourceReaders.contains(toolId),
              result.output.string("path") == input.string("path"),
              let size = result.output["size_bytes"]?.intValue, size >= 0 {
      inspection = Inspection(path: input.string("path"),
        digest: result.output.string("sha256").ifBlank(result.output.string("hex")), size: size)
    } else {
      inspection = nil
    }
    return Self(toolId: toolId, workspaceId: workspace, conversationId: context.conversationId,
      turnId: context.turnId, invocationId: result.receipt.invocationId,
      originalInvocationId: result.receipt.originalInvocationId, replayed: result.receipt.replayed,
      succeeded: result.isSuccess && scopeMatches, inspection: inspection)
  }
}

enum AgentArtifactCompletionEvidence {
  static let sourceReaders: Set<String> = [AgentPhoneNativeToolCatalog.workspaceSha256,
    AgentPhoneNativeToolCatalog.workspaceReadText]
  private static let mutations: Set<String> = [
    AgentPhoneNativeToolCatalog.workspaceMkdir, AgentPhoneNativeToolCatalog.workspaceWriteText,
    AgentPhoneNativeToolCatalog.workspaceWriteTextBatch, AgentPhoneNativeToolCatalog.workspaceCreateText,
    AgentPhoneNativeToolCatalog.workspaceAppendText, AgentPhoneNativeToolCatalog.workspaceWriteBytes,
    AgentPhoneNativeToolCatalog.workspaceCreateBytes, AgentPhoneNativeToolCatalog.workspaceAppendBytes,
    AgentPhoneNativeToolCatalog.workspaceMove, AgentPhoneNativeToolCatalog.workspaceCopy,
    AgentPhoneNativeToolCatalog.workspaceDelete, AgentPhoneNativeToolCatalog.workspaceApplyExactPatch,
    AgentPhoneNativeToolCatalog.workspaceZipCreate, AgentPhoneNativeToolCatalog.workspaceZipExtract,
    AgentIOSOnDeviceRuntimeNativeToolCatalog.execute, AgentIOSOnDeviceRuntimeNativeToolCatalog.workspaceRollback
  ]

  static func tracked(_ tool: String) -> Bool {
    mutations.contains(tool) || sourceReaders.contains(tool) || tool == AgentPhoneNativeToolCatalog.workspaceExport
  }

  static func scopeId(tool: String, input: AgentMcpJSONObject, workspace: String) -> String {
    guard !workspace.isEmpty else { return "" }
    let linux = tool.hasPrefix("galaxyssi.runtime.") ||
      (tool == AgentPhoneNativeToolCatalog.workspaceExport && input.string("source") == "phone_linux")
    return linux ? workspace + ":linux" : workspace
  }

  static func missing(_ requirements: [AgentArtifactRequirement], history: [AgentAction],
                      scope: AgentPlanContinuationScope) -> [String] {
    assess(requirements, history: history, scope: scope).missing
  }

  static func assess(_ requirements: [AgentArtifactRequirement], history: [AgentAction],
                     scope: AgentPlanContinuationScope) -> (
    missing: [String], verified: [AgentArtifactOperationReceipt.Inspection]
  ) {
    guard !requirements.isEmpty else { return ([], []) }
    let observations = AgentDurablePlanHistoryPolicy.latestSnapshots(history.filter(scope.owns)).compactMap {
      Observation(action: $0, scope: scope)
    }
    var verified: [AgentArtifactOperationReceipt.Inspection] = []
    let missing: [String] = requirements.compactMap { requirement in
      let relevant = observations.filter { $0.affects(requirement.path) }
      let workspaces = Set(relevant.filter { $0.isExport && $0.receipt != nil }.map(\.workspace).filter { !$0.isEmpty })
      let failure: (String) -> String = { code in
        "\(code): \(requirement.path). Inspect the current file, then export it again after operations settle. Do not repeat a mutation just to obtain evidence."
      }
      if requirement.workspaceId.isEmpty && workspaces.count > 1 {
        return failure("artifact_workspace_ambiguous")
      }
      let workspace = requirement.workspaceId.ifBlank(workspaces.first ?? "")
      let scoped = relevant.filter {
        workspace.isEmpty || $0.workspace == workspace ||
          ($0.workspace.isEmpty && $0.linux == workspace.hasSuffix(":linux"))
      }
      if scoped.contains(where: \.pending) {
        return failure("artifact_operation_pending")
      }
      let originals = Set(scoped.compactMap { $0.receipt?.replayed == false ? $0.receipt?.invocationId : nil })
      guard let latest = scoped.last(where: {
        guard $0.action.status == .completed, let receipt = $0.receipt, receipt.replayed else { return true }
        return !$0.isExport && !originals.contains(receipt.originalInvocationId ?? "")
      }),
            latest.isExport, !workspace.isEmpty, latest.workspace == workspace,
            let inspection = latest.verifiedInspection, inspection.path == requirement.path else {
        return failure("artifact_export_missing_stale_or_failed")
      }
      if !requirement.sourceSha256.isEmpty {
        let previous = scoped.dropLast().filter { $0.receipt?.replayed != true }
        guard inspection.digest.lowercased() != requirement.sourceSha256,
              let change = previous.lastIndex(where: { !$0.isExport }),
              let source = observations.last(where: {
                $0.workspace == workspace && $0.verifiedInspection?.path == requirement.path &&
                  $0.indexBefore(previous[change], in: observations)
              })?.verifiedInspection,
              source.digest.lowercased() == requirement.sourceSha256 else {
          return failure("artifact_source_not_verified")
        }
      }
      verified.append(inspection)
      return nil
    }
    return (missing, verified)
  }

  private struct Observation: Equatable {
    let action: AgentAction
    let tool: String
    let input: AgentMcpJSONObject
    let receipt: AgentArtifactOperationReceipt?
    let workspace: String
    var isExport: Bool { tool == AgentPhoneNativeToolCatalog.workspaceExport }
    var linux: Bool { AgentArtifactCompletionEvidence.scopeId(tool: tool, input: input, workspace: "test").hasSuffix(":linux") }
    var pending: Bool {
      [.running, .waitingResponse].contains(action.status) ||
        (action.status == .rolledBack && receipt == nil &&
          [AgentActionStatus.running.rawValue, AgentActionStatus.waitingResponse.rawValue]
            .contains(action.parameters[AgentDurablePlanHistoryPolicy.supersededStatusParameter] ?? ""))
    }

    init?(action: AgentAction, scope: AgentPlanContinuationScope) {
      let tool = action.parameters["tool_id"] ?? action.target
      guard action.kind == .callNativeTool, AgentArtifactCompletionEvidence.tracked(tool),
            ![.proposed, .pendingConfirmation, .blocked].contains(action.status),
            !(action.status == .rolledBack &&
              [AgentActionStatus.proposed.rawValue, AgentActionStatus.pendingConfirmation.rawValue]
                .contains(action.parameters[AgentDurablePlanHistoryPolicy.supersededStatusParameter] ?? "")) else { return nil }
      let raw = action.parameters["input_json"] ?? "{}"
      let input = (try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))) ?? [:]
      self.action = action
      self.tool = tool
      self.input = input
      receipt = action.artifactReceipt.flatMap {
        $0.toolId == tool && $0.conversationId == scope.conversationId && $0.turnId == scope.turnId &&
          !$0.workspaceId.isEmpty && !$0.invocationId.isEmpty ? $0 : nil
      }
      workspace = receipt?.workspaceId ?? ""
    }

    var verifiedInspection: AgentArtifactOperationReceipt.Inspection? {
      guard action.status == .completed, let receipt, receipt.succeeded, !receipt.replayed,
            let inspection = receipt.inspection, AgentArtifactRequirement.validDigest(inspection.digest) else { return nil }
      return inspection
    }

    func indexBefore(_ other: Self, in observations: [Self]) -> Bool {
      guard let first = observations.firstIndex(of: self), let second = observations.firstIndex(of: other) else { return false }
      return first < second
    }

    func affects(_ path: String) -> Bool {
      let catalog = AgentPhoneNativeToolCatalog.self
      switch tool {
      case AgentIOSOnDeviceRuntimeNativeToolCatalog.execute, AgentIOSOnDeviceRuntimeNativeToolCatalog.workspaceRollback:
        return true
      case catalog.workspaceExport:
        return input.string("path").isEmpty || AgentWorkspaceFilePathPolicy.displayPath(input.string("path")) == path
      default:
        guard AgentArtifactCompletionEvidence.mutations.contains(tool) else { return false }
        let paths: [String]
        switch tool {
        case catalog.workspaceMove: paths = [input.string("source_path"), input.string("destination_path")]
        case catalog.workspaceCopy, catalog.workspaceZipExtract: paths = [input.string("destination_path")]
        case catalog.workspaceZipCreate: paths = [input.string("archive_path")]
        case catalog.workspaceWriteTextBatch:
          paths = input["files"]?.arrayValue?.map { $0.objectValue?.string("path") ?? "" } ?? []
        default: paths = [input.string("path")]
        }
        return paths.isEmpty || paths.contains { candidate in
          guard case .success(let parts) = AgentWorkspaceFilePathPolicy.normalizeRelativePath(candidate, allowRoot: false)
          else { return true }
          let target = parts.joined(separator: "/")
          return path == target || path.hasPrefix(target + "/")
        }
      }
    }
  }
}

enum AgentVerifiedArtifactSnapshot {
  static let folder = "verified-exports"
  static let kind = "verified_snapshot"
  static let maximumBytes: Int64 = 32 * 1_024 * 1_024
  static let maximumReviewCharacters = 8_192
  static let maximumReceiptBytes = 64 * 1_024
  private static let textExtensions: Set<String> = [
    "txt", "md", "csv", "tsv", "html", "htm", "json", "xml", "svg", "py", "js", "ts",
    "kt", "java", "c", "cpp", "h", "css", "yaml", "yml", "toml", "log", "sh"
  ]

  static func write(data: Data, path: String, root: URL) throws -> AgentMcpJSONObject {
    guard AgentArtifactRequirement.validPath(path), Int64(data.count) <= maximumBytes else {
      throw AgentRuntimeProjectWorkspaceError.invalid("Artifact path or size is invalid")
    }
    let digest = sha256(data)
    let destination = url(root: root, digest: digest, path: path)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: destination, options: .atomic)
    guard try AgentDesktopArtifactActions.sha256(source: destination) == digest else {
      throw AgentRuntimeProjectWorkspaceError.invalid("Exported bytes could not be verified")
    }
    return ["relative_path": .string(path), "artifact_kind": .string(kind),
            "file_count": .int(1), "size_bytes": .int(Int64(data.count)), "sha256": .string(digest),
            "openability": .object(openability(data: data, path: path, digest: digest))]
  }

  private static func openability(data: Data, path: String, digest: String) -> AgentMcpJSONObject {
    var result: AgentMcpJSONObject = ["status": .string("verified"), "sha256": .string(digest),
                                      "scope": .string("byte_stream")]
    guard textExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else { return result }
    result["scope"] = .string("utf8_text_read")
    guard let decoded = String(data: data, encoding: .utf8) else {
      result["status"] = .string("unverified")
      result["reason"] = .string("invalid_utf8")
      return result
    }
    // Some decoders strip a UTF-8 BOM; only return text that round-trips to the snapshot bytes.
    let text = decoded.utf8.count + 3 == data.count && data.starts(with: [0xEF, 0xBB, 0xBF])
      ? "\u{FEFF}" + decoded : decoded
    let count = text.utf16.count
    let complete = count <= maximumReviewCharacters && text.utf8.elementsEqual(data)
    var details: AgentMcpJSONObject = ["characters_read": .int(Int64(count)), "text_complete": .bool(complete)]
    if complete { details["text"] = .string(text) }
    result["details"] = .object(details)
    return result
  }

  static func matchesReviewText(_ text: String, digest: String, size: Int64) -> Bool {
    text.utf16.count <= maximumReviewCharacters && Int64(text.utf8.count) == size &&
      sha256(Data(text.utf8)) == digest.lowercased()
  }

  static func omittingReviewText(in output: AgentMcpJSONObject) -> AgentMcpJSONObject {
    var output = output
    guard var artifact = output["artifacts"]?.arrayValue?.first?.objectValue,
          var openability = artifact["openability"]?.objectValue,
          var details = openability["details"]?.objectValue else { return output }
    details["text"] = nil
    details["text_complete"] = .bool(false)
    openability["details"] = .object(details)
    artifact["openability"] = .object(openability)
    output["artifacts"] = .array([.object(artifact)])
    return output
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func readLinuxFile(path: String, project: URL) throws -> Data {
    let parts = path.split(separator: "/").map(String.init)
    let invalid = AgentRuntimeProjectWorkspaceError.invalid("The Linux artifact is not a bounded regular workspace file")
    guard AgentArtifactRequirement.validPath(path), !parts.contains(".galaxyssi-runtime"), !parts.contains(".git")
    else { throw invalid }
    // Open each component relative to its parent so a guest cannot swap in a symlink between validation and read.
    var directory = open(project.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard directory >= 0 else { throw invalid }
    defer { close(directory) }
    for component in parts.dropLast() {
      let child = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
      guard child >= 0 else { throw invalid }
      close(directory)
      directory = child
    }
    guard let file = parts.last else { throw invalid }
    let fd = openat(directory, file, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { throw invalid }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var before = stat()
    guard fstat(fd, &before) == 0, (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
          before.st_size >= 0, before.st_size <= maximumBytes else { throw invalid }
    let data = try handle.read(upToCount: Int(maximumBytes) + 1) ?? Data()
    var after = stat()
    guard fstat(fd, &after) == 0, Int64(data.count) == before.st_size, after.st_size == before.st_size,
          after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
          after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else { throw invalid }
    return data
  }

  static func url(root: URL, digest: String, path: String) -> URL {
    root.appendingPathComponent(folder, isDirectory: true)
      .appendingPathComponent(digest, isDirectory: true)
      .appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent, isDirectory: false)
  }
}
