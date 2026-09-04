import CryptoKit
import Foundation

struct AgentIOSFfmpegRuntimeResourceLimits: Equatable {
  var wallClockMillis: Int64
  var cpuMillis: Int64
  var memoryBytes: Int64
  var diskBytes: Int64
  var maxProcesses: Int
  var maxOutputBytes: Int64
  var maxArtifactBytes: Int64
}

struct AgentIOSFfmpegRuntimeRequest: Equatable {
  var language: String
  var source: String
  var arguments: [String]
  var timeoutMillis: Int64
  var networkEnabled: Bool
  var artifactPaths: [String]
  var workspaceId: String
  var workspaceURL: URL
  var requestId: String
  var resourceLimits: AgentIOSFfmpegRuntimeResourceLimits
}

struct AgentIOSFfmpegRuntimeResult: Equatable {
  var exitCode: Int
  var stderr: String
  var durationMillis: Int64
  var artifacts: [AgentMcpJSONObject]
  var executionReceipt: AgentMcpJSONObject
}

protocol AgentIOSFfmpegRuntimeExecuting {
  var implementationId: String { get }
  func availability() -> AgentNativeToolAvailability
  func execute(_ request: AgentIOSFfmpegRuntimeRequest) throws -> AgentIOSFfmpegRuntimeResult
}

struct AgentIOSUnavailableFfmpegRuntime: AgentIOSFfmpegRuntimeExecuting {
  var implementationId: String = "galaxyssi.ios.ffmpeg_runtime_unconfigured"

  func availability() -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "iOS signed FFmpeg runtime is not connected"
    )
  }

  func execute(_ request: AgentIOSFfmpegRuntimeRequest) throws -> AgentIOSFfmpegRuntimeResult {
    throw AgentIOSFfmpegMediaProviderError.ffmpegRequiresSetup("iOS signed FFmpeg runtime is not connected")
  }
}

struct AgentIOSSignedFfmpegMediaProvider: AgentIOSMediaNativeToolProviding {
  var implementationId: String
  var runtime: AgentIOSFfmpegRuntimeExecuting
  var passthroughProvider: AgentIOSMediaNativeToolProviding
  var projectRoot: URL
  var fileManager: FileManager
  var nowMillis: () -> Int64

  init(
    runtime: AgentIOSFfmpegRuntimeExecuting = AgentIOSUnavailableFfmpegRuntime(),
    passthroughProvider: AgentIOSMediaNativeToolProviding = AgentIOSUnavailableMediaNativeToolProvider(),
    projectRoot: URL? = nil,
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.runtime = runtime
    self.passthroughProvider = passthroughProvider
    self.projectRoot = (projectRoot ?? Self.defaultProjectRoot(fileManager: fileManager)).standardizedFileURL
    self.fileManager = fileManager
    self.nowMillis = nowMillis
    self.implementationId = "galaxyssi.ios_runtime.ffmpeg"
  }

  func availability(kind: AgentIOSMediaNativeToolKind) -> AgentNativeToolAvailability {
    switch kind {
    case .transcode:
      return runtime.availability()
    case .metadata, .playback:
      return passthroughProvider.availability(kind: kind)
    }
  }

  func inspectMetadata(
    contentUri: String,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    passthroughProvider.inspectMetadata(contentUri: contentUri, invocation: invocation)
  }

  func handoffPlayback(
    contentUri: String,
    contentType: String,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    passthroughProvider.handoffPlayback(contentUri: contentUri, contentType: contentType, invocation: invocation)
  }

  func transcode(
    request: AgentIOSMediaTranscodeRequest,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    do {
      return try performTranscode(request: request)
    } catch let error as AgentIOSFfmpegMediaProviderError {
      return error.executionResult
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "ffmpeg_runtime_failed",
        message: "The iOS FFmpeg runtime could not complete the conversion: \(friendlyDiagnostic(error.localizedDescription))",
        retryable: true
      )
    }
  }

  private func performTranscode(request: AgentIOSMediaTranscodeRequest) throws -> AgentNativeToolExecutionResult {
    guard request.workspaceId.range(of: workspaceIdPattern, options: .regularExpression) != nil else {
      throw AgentIOSFfmpegMediaProviderError.invalidWorkspace
    }
    guard !request.invocationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentIOSFfmpegMediaProviderError.missingInvocation
    }
    let runtimeAvailability = runtime.availability()
    guard runtimeAvailability.status == .available else {
      throw AgentIOSFfmpegMediaProviderError.ffmpegRequiresSetup(
        runtimeAvailability.reason.ifBlank("iOS signed FFmpeg runtime is not ready")
      )
    }
    let requestedTargetFormat = try targetFormat(request)

    return try AgentWorkspaceScope.withLock(workspaceId: request.workspaceId) {
      let workspace = try openWorkspace(request.workspaceId)
      let sourcePath = try sourcePath(in: workspace, request: request)
      let sourceFile = try resolveWorkspaceFile(workspace: workspace, relativePath: sourcePath)
      guard isRegularFile(sourceFile), !isSymbolicLink(sourceFile) else {
        throw AgentIOSFfmpegMediaProviderError.mediaSourceNotFound
      }
      guard try fileSize(sourceFile) <= Self.maxSourceBytes else {
        throw AgentIOSFfmpegMediaProviderError.mediaSourceTooLarge
      }

      let destinationPath = try request.destinationPath.nonEmpty.map {
        try AgentIOSMediaWorkspacePaths.normalizeRelative($0, field: "destination_path")
      } ?? AgentIOSFfmpegTranscodePlanner.defaultDestination(
        invocationId: request.invocationId,
        targetFormat: requestedTargetFormat
      )
      let destinationFile = try resolveWorkspaceFile(workspace: workspace, relativePath: destinationPath)
      guard sourceFile.standardizedFileURL != destinationFile.standardizedFileURL else {
        throw AgentIOSFfmpegMediaProviderError.mediaDestinationConflict
      }
      if fileManager.fileExists(atPath: destinationFile.path), isSymbolicLink(destinationFile) {
        throw AgentIOSFfmpegMediaProviderError.unsafeMediaDestination
      }
      try createDirectory(destinationFile.deletingLastPathComponent())

      let plan = try AgentIOSFfmpegTranscodePlanner.create(
        request: request,
        sourcePath: sourcePath,
        destinationPath: destinationPath
      )
      let runtimeRequest = runtimeRequest(request: request, workspace: workspace, plan: plan)
      let response = try executeRuntime(runtimeRequest)
      guard response.exitCode == 0 else {
        throw AgentIOSFfmpegMediaProviderError.ffmpegTranscodeFailed(
          exitCode: response.exitCode,
          stderr: response.stderr,
          receipt: response.executionReceipt
        )
      }
      guard isRegularFile(destinationFile), !isSymbolicLink(destinationFile) else {
        throw AgentIOSFfmpegMediaProviderError.ffmpegOutputMissing
      }
      guard try fileSize(destinationFile) <= Self.maxArtifactBytes else {
        throw AgentIOSFfmpegMediaProviderError.ffmpegOutputTooLarge
      }

      let artifact = response.artifacts.first {
        $0["relative_path"]?.stringValue == plan.destinationPath
      }
      let outputSize: Int64
      if let artifactSize = artifact?["size_bytes"]?.intValue {
        outputSize = artifactSize
      } else {
        outputSize = try fileSize(destinationFile)
      }
      let outputSha: String
      if let artifactSha = artifact?["sha256"]?.stringValue?.nonEmpty {
        outputSha = artifactSha
      } else {
        outputSha = try sha256File(destinationFile)
      }
      let artifacts = response.artifacts.map { AgentMcpJSONValue.object($0) }

      return AgentNativeToolExecutionResult.success(
        output: [
          "source_path": .string(plan.sourcePath),
          "destination_path": .string(plan.destinationPath),
          "target_format": .string(request.targetFormat),
          "mime_type": .string(AgentIOSMediaNativeToolCatalog.targetMimeType(request.targetFormat) ?? requestedTargetFormat.mimeType),
          "size_bytes": .int(outputSize),
          "sha256": .string(outputSha),
          "execution_duration_ms": .int(response.durationMillis),
          "artifacts": .array(artifacts),
          "execution_receipt": .object(response.executionReceipt),
          "network_enabled": .bool(false),
          "completed_at_epoch_ms": .int(max(0, nowMillis()))
        ],
        message: "Media converted in the local iOS FFmpeg runtime",
        metadata: [
          "runtime_implementation": .string(runtime.implementationId),
          "ffmpeg_request_id": .string(runtimeRequest.requestId),
          "ffmpeg_argument_count": .int(Int64(runtimeRequest.arguments.count)),
          "ffmpeg_network_enabled": .bool(false),
          "workspace_path_redacted": .bool(true)
        ]
      )
    }
  }

  private func sourcePath(in workspace: URL, request: AgentIOSMediaTranscodeRequest) throws -> String {
    if !request.contentUri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return try importFileURLMedia(workspace: workspace, request: request)
    }
    return try AgentIOSMediaWorkspacePaths.normalizeRelative(request.sourcePath, field: "source_path")
  }

  private func importFileURLMedia(workspace: URL, request: AgentIOSMediaTranscodeRequest) throws -> String {
    guard let sourceURL = URL(string: request.contentUri.trimmingCharacters(in: .whitespacesAndNewlines)),
          sourceURL.isFileURL else {
      throw AgentIOSFfmpegMediaProviderError.contentUriRequired
    }
    let didAccess = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }
    guard isRegularFile(sourceURL), !isSymbolicLink(sourceURL) else {
      throw AgentIOSFfmpegMediaProviderError.mediaSourceNotFound
    }
    guard try fileSize(sourceURL) <= Self.maxSourceBytes else {
      throw AgentIOSFfmpegMediaProviderError.mediaSourceTooLarge
    }

    let relative = "inputs/media/\(runtimeRequestId(request)).\(safeExtension(sourceURL.lastPathComponent).ifBlank("bin"))"
    let target = try resolveWorkspaceFile(workspace: workspace, relativePath: relative)
    try createDirectory(target.deletingLastPathComponent())
    let temporary = target.deletingLastPathComponent()
      .appendingPathComponent(".\(target.lastPathComponent).part", isDirectory: false)
    try? fileManager.removeItem(at: temporary)
    do {
      try fileManager.copyItem(at: sourceURL, to: temporary)
      guard try fileSize(temporary) <= Self.maxSourceBytes else {
        throw AgentIOSFfmpegMediaProviderError.mediaSourceTooLarge
      }
      if fileManager.fileExists(atPath: target.path) {
        try fileManager.removeItem(at: target)
      }
      try fileManager.moveItem(at: temporary, to: target)
    } catch let error as AgentIOSFfmpegMediaProviderError {
      try? fileManager.removeItem(at: temporary)
      throw error
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw AgentIOSFfmpegMediaProviderError.contentUriUnavailable
    }
    return relative
  }

  private func runtimeRequest(
    request: AgentIOSMediaTranscodeRequest,
    workspace: URL,
    plan: AgentIOSFfmpegTranscodePlan
  ) -> AgentIOSFfmpegRuntimeRequest {
    AgentIOSFfmpegRuntimeRequest(
      language: "ffmpeg",
      source: operationManifest(request: request, plan: plan),
      arguments: plan.arguments,
      timeoutMillis: request.timeoutMillis,
      networkEnabled: false,
      artifactPaths: [plan.destinationPath],
      workspaceId: request.workspaceId,
      workspaceURL: workspace,
      requestId: runtimeRequestId(request),
      resourceLimits: AgentIOSFfmpegRuntimeResourceLimits(
        wallClockMillis: request.timeoutMillis,
        cpuMillis: max(100, request.timeoutMillis * 9 / 10),
        memoryBytes: 768 * 1_024 * 1_024,
        diskBytes: 768 * 1_024 * 1_024,
        maxProcesses: 32,
        maxOutputBytes: 512 * 1_024,
        maxArtifactBytes: Self.maxArtifactBytes
      )
    )
  }

  private func executeRuntime(_ request: AgentIOSFfmpegRuntimeRequest) throws -> AgentIOSFfmpegRuntimeResult {
    do {
      return try runtime.execute(request)
    } catch let error as AgentIOSFfmpegMediaProviderError {
      throw error
    } catch {
      throw AgentIOSFfmpegMediaProviderError.ffmpegRuntimeFailed(error.localizedDescription)
    }
  }

  private func operationManifest(
    request: AgentIOSMediaTranscodeRequest,
    plan: AgentIOSFfmpegTranscodePlan
  ) -> String {
    AgentMcpJSONCodec.stringify([
      "operation": .string("media_transcode"),
      "source_path": .string(plan.sourcePath),
      "destination_path": .string(plan.destinationPath),
      "target_format": .string(request.targetFormat),
      "preset": .string(request.preset),
      "network_enabled": .bool(false)
    ])
  }

  private func openWorkspace(_ workspaceId: String) throws -> URL {
    let root = projectRoot.standardizedFileURL
    if fileManager.fileExists(atPath: root.path), isSymbolicLink(root) {
      throw AgentIOSFfmpegMediaProviderError.unsafeMediaWorkspace
    }
    try createDirectory(root)
    let workspace = root.appendingPathComponent(workspaceId, isDirectory: true).standardizedFileURL
    guard isPath(workspace, inside: root) else {
      throw AgentIOSFfmpegMediaProviderError.unsafeMediaWorkspace
    }
    if fileManager.fileExists(atPath: workspace.path), isSymbolicLink(workspace) {
      throw AgentIOSFfmpegMediaProviderError.unsafeMediaWorkspace
    }
    try createDirectory(workspace)
    return workspace
  }

  private func resolveWorkspaceFile(workspace: URL, relativePath: String) throws -> URL {
    let relative = try AgentIOSMediaWorkspacePaths.normalizeRelative(relativePath, field: "path")
    let candidate = workspace.appendingPathComponent(relative, isDirectory: false).standardizedFileURL
    guard isPath(candidate, inside: workspace) else {
      throw AgentIOSFfmpegMediaProviderError.mediaPathEscapedWorkspace
    }
    return candidate
  }

  private func createDirectory(_ url: URL) throws {
    do {
      try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
      throw AgentIOSFfmpegMediaProviderError.mediaStorageUnavailable
    }
  }

  private func isPath(_ child: URL, inside parent: URL) -> Bool {
    let parentPath = parent.standardizedFileURL.path
    let childPath = child.standardizedFileURL.path
    return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
  }

  private func isRegularFile(_ url: URL) -> Bool {
    fileAttributeType(url) == .typeRegular
  }

  private func isSymbolicLink(_ url: URL) -> Bool {
    fileAttributeType(url) == .typeSymbolicLink
  }

  private func fileAttributeType(_ url: URL) -> FileAttributeType? {
    (try? fileManager.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType
  }

  private func fileSize(_ url: URL) throws -> Int64 {
    guard let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber else {
      throw AgentIOSFfmpegMediaProviderError.mediaSourceNotFound
    }
    return size.int64Value
  }

  private func sha256File(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer {
      try? handle.close()
    }
    var hasher = SHA256()
    while true {
      let chunk = try handle.read(upToCount: 64 * 1_024) ?? Data()
      if chunk.isEmpty { break }
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func safeExtension(_ value: String) -> String {
    guard value.contains(".") else { return "" }
    let ext = value.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
    guard ext.range(of: #"^[a-z0-9]{1,10}$"#, options: .regularExpression) != nil else {
      return ""
    }
    return ext
  }

  private func targetFormat(_ request: AgentIOSMediaTranscodeRequest) throws -> AgentIOSMediaTargetFormat {
    guard let format = AgentIOSMediaTargetFormat.fromWireValue(request.targetFormat) else {
      throw AgentIOSFfmpegMediaProviderError.invalidTranscodeRequest("Target media format is invalid")
    }
    return format
  }

  private func runtimeRequestId(_ request: AgentIOSMediaTranscodeRequest) -> String {
    "media-\(sha256(Data(request.invocationId.utf8)).prefix(32))"
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func friendlyDiagnostic(_ value: String) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxFriendlyDiagnosticCharacters))
  }

  private static func defaultProjectRoot(fileManager: FileManager) -> URL {
    let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    return base.appendingPathComponent("agent-native-workspaces", isDirectory: true)
  }

  private static let maxSourceBytes: Int64 = 256 * 1_024 * 1_024
  private static let maxArtifactBytes: Int64 = 256 * 1_024 * 1_024
  private static let maxFriendlyDiagnosticCharacters = 320
  private let workspaceIdPattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#
}

enum AgentIOSFfmpegMediaProviderError: LocalizedError, Equatable {
  case invalidWorkspace
  case missingInvocation
  case unsafeMediaWorkspace
  case mediaPathEscapedWorkspace
  case mediaStorageUnavailable
  case mediaSourceNotFound
  case mediaSourceTooLarge
  case mediaDestinationConflict
  case unsafeMediaDestination
  case contentUriRequired
  case contentUriUnavailable
  case invalidTranscodeRequest(String)
  case ffmpegRequiresSetup(String)
  case ffmpegRuntimeFailed(String)
  case ffmpegTranscodeFailed(exitCode: Int, stderr: String, receipt: AgentMcpJSONObject)
  case ffmpegOutputMissing
  case ffmpegOutputTooLarge

  var errorDescription: String? {
    switch self {
    case .invalidWorkspace:
      return "Media workspace ID is invalid"
    case .missingInvocation:
      return "Media invocation ID is required"
    case .unsafeMediaWorkspace:
      return "The media workspace is unsafe"
    case .mediaPathEscapedWorkspace:
      return "Media path escapes its workspace"
    case .mediaStorageUnavailable:
      return "Media workspace storage is unavailable"
    case .mediaSourceNotFound:
      return "The selected media source is unavailable"
    case .mediaSourceTooLarge:
      return "The selected media exceeds the 256 MB limit"
    case .mediaDestinationConflict:
      return "Source and destination must be different files"
    case .unsafeMediaDestination:
      return "The media destination is unsafe"
    case .contentUriRequired:
      return "A user-authorized file URL is required on iOS"
    case .contentUriUnavailable:
      return "The selected media cannot be opened"
    case .invalidTranscodeRequest(let message), .ffmpegRequiresSetup(let message), .ffmpegRuntimeFailed(let message):
      return message
    case .ffmpegTranscodeFailed(_, let stderr, _):
      return Self.friendlyFailure(stderr)
    case .ffmpegOutputMissing:
      return "FFmpeg completed without producing the requested media file"
    case .ffmpegOutputTooLarge:
      return "Converted media exceeds the 256 MB output limit"
    }
  }

  var executionResult: AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: code,
      message: errorDescription ?? "Media conversion failed",
      retryable: retryable,
      details: details
    )
  }

  private var code: String {
    switch self {
    case .invalidWorkspace:
      return "invalid_media_workspace"
    case .missingInvocation:
      return "invalid_media_invocation"
    case .unsafeMediaWorkspace:
      return "unsafe_media_workspace"
    case .mediaPathEscapedWorkspace:
      return "unsafe_media_path"
    case .mediaStorageUnavailable:
      return "media_workspace_unavailable"
    case .mediaSourceNotFound:
      return "media_source_not_found"
    case .mediaSourceTooLarge:
      return "media_source_too_large"
    case .mediaDestinationConflict:
      return "media_destination_conflict"
    case .unsafeMediaDestination:
      return "unsafe_media_destination"
    case .contentUriRequired:
      return "content_uri_required"
    case .contentUriUnavailable:
      return "content_uri_unavailable"
    case .invalidTranscodeRequest:
      return "invalid_transcode_request"
    case .ffmpegRequiresSetup:
      return "ffmpeg_requires_setup"
    case .ffmpegRuntimeFailed:
      return "ffmpeg_runtime_failed"
    case .ffmpegTranscodeFailed:
      return "ffmpeg_transcode_failed"
    case .ffmpegOutputMissing:
      return "ffmpeg_output_missing"
    case .ffmpegOutputTooLarge:
      return "ffmpeg_output_too_large"
    }
  }

  private var retryable: Bool {
    switch self {
    case .ffmpegRequiresSetup, .ffmpegRuntimeFailed:
      return true
    default:
      return false
    }
  }

  private var details: AgentMcpJSONObject {
    switch self {
    case .ffmpegTranscodeFailed(let exitCode, let stderr, let receipt):
      return [
        "exit_code": .int(Int64(exitCode)),
        "diagnostic": .string(String(stderr.prefix(2_000))),
        "execution_receipt": .object(receipt)
      ]
    default:
      return [:]
    }
  }

  private static func friendlyFailure(_ stderr: String) -> String {
    let diagnostic = stderr
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .last { !$0.isEmpty } ?? ""
    guard !diagnostic.isEmpty else {
      return "FFmpeg could not convert the selected media"
    }
    return "FFmpeg could not convert the selected media: \(diagnostic.prefix(320))"
  }
}
