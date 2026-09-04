import Foundation

enum AgentIOSMediaNativeToolKind: String, Codable, CaseIterable, Identifiable {
  case metadata
  case playback
  case transcode

  var id: String { rawValue }
}

struct AgentIOSMediaTranscodeRequest: Equatable {
  var contentUri: String
  var sourcePath: String
  var destinationPath: String
  var targetFormat: String
  var preset: String
  var startMillis: Int64
  var durationMillis: Int64
  var maxWidth: Int
  var maxHeight: Int
  var audioBitrateKbps: Int
  var timeoutMillis: Int64
  var workspaceId: String
  var invocationId: String
}

protocol AgentIOSMediaNativeToolProviding {
  var implementationId: String { get }
  func availability(kind: AgentIOSMediaNativeToolKind) -> AgentNativeToolAvailability
  func inspectMetadata(contentUri: String, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
  func handoffPlayback(contentUri: String, contentType: String, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
  func transcode(request: AgentIOSMediaTranscodeRequest, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
}

struct AgentIOSUnavailableMediaNativeToolProvider: AgentIOSMediaNativeToolProviding {
  var implementationId: String = "galaxyssi.ios.media_unconfigured"

  func availability(kind: AgentIOSMediaNativeToolKind) -> AgentNativeToolAvailability {
    let reason: String
    switch kind {
    case .metadata, .playback:
      reason = "iOS media provider is not connected"
    case .transcode:
      reason = "iOS signed FFmpeg media runtime is not connected"
    }
    return AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: reason
    )
  }

  func inspectMetadata(contentUri: String, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    unavailable("iOS media metadata provider is not connected")
  }

  func handoffPlayback(contentUri: String, contentType: String, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    unavailable("iOS media playback provider is not connected")
  }

  func transcode(request: AgentIOSMediaTranscodeRequest, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    unavailable("iOS signed FFmpeg media runtime is not connected")
  }

  private func unavailable(_ message: String) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "media_provider_unavailable",
      message: message,
      retryable: true
    )
  }
}

enum AgentIOSMediaNativeToolCatalog {
  static let mediaMetadata = "galaxyssi.media.metadata"
  static let mediaPlaybackHandoff = AgentPhoneCapabilityNativeCoverage.mediaPlaybackHandoff
  static let mediaFFmpegTranscode = AgentPhoneCapabilityNativeCoverage.mediaFFmpegTranscode

  static let contentUriPermission = "galaxyssi.scope.user_authorized_content_uri"
  static let workspaceMediaPermission = "galaxyssi.scope.app_private_workspace"
  static let mediaRuntimePermission = "galaxyssi.scope.signed_media_runtime"
  static let contentUriReadConsent = "galaxyssi.consent.content_uri_read"
  static let contentUriWriteConsent = "galaxyssi.consent.content_uri_write"
  static let mediaPlaybackConsent = "galaxyssi.consent.media_playback"
  static let mediaTranscodeConsent = "galaxyssi.consent.media_transcode"
  static let executorId = "galaxyssi.ios_media_tools"

  static let maxContentUriCharacters = 4_096
  static let maxPathCharacters = 1_024
  static let maxToolTimeoutMillis: Int64 = 15_000
  static let maxTranscodeTimeoutMillis: Int64 = 15 * 60_000
  static let maxMediaBytes: Int64 = 256 * 1_024 * 1_024

  static let toolIds: Set<String> = [mediaMetadata, mediaPlaybackHandoff, mediaFFmpegTranscode]

  static func definitions(
    provider: AgentIOSMediaNativeToolProviding = AgentIOSUnavailableMediaNativeToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    [
      definition(
        provider: provider,
        kind: .metadata,
        id: mediaMetadata,
        title: "Inspect selected media",
        description: "Reads bounded metadata from a user-authorized iOS media content URI or security-scoped file URL.",
        inputSchema: mediaContentInputSchema(),
        outputSchema: mediaMetadataOutputSchema(),
        risk: .low,
        capabilities: ["media.metadata.inspect", "content_uri.user_authorized", "result.bounded"],
        permissions: [contentUriRequirement()],
        consents: [consent(contentUriReadConsent, "Read selected media", "Allows reading metadata from the selected media reference.")],
        timeoutMillis: maxToolTimeoutMillis
      ),
      definition(
        provider: provider,
        kind: .playback,
        id: mediaPlaybackHandoff,
        title: "Hand media to iOS playback",
        description: "Opens selected media in a user-visible iOS playback handler without claiming playback completion.",
        inputSchema: objectSchema([
          "content_uri": contentUriSchema(),
          "content_type": stringSchema(maxLength: 255)
        ], required: ["content_uri"]),
        outputSchema: mediaPlaybackOutputSchema(),
        risk: .medium,
        capabilities: ["media.playback.handoff", "content_uri.user_authorized", "completion.handoff_only"],
        permissions: [contentUriRequirement()],
        consents: [
          consent(contentUriReadConsent, "Read selected media", "Allows opening the selected media reference."),
          consent(mediaPlaybackConsent, "Open media playback", "Allows a user-visible iOS media playback handoff.")
        ],
        timeoutMillis: maxToolTimeoutMillis,
        idempotency: .nonIdempotent
      ),
      definition(
        provider: provider,
        kind: .transcode,
        id: mediaFFmpegTranscode,
        title: "Transcode media with FFmpeg",
        description: "Converts one user-authorized or conversation-workspace media file in a bounded, offline iOS media runtime.",
        inputSchema: mediaTranscodeInputSchema(),
        outputSchema: mediaTranscodeOutputSchema(),
        risk: .medium,
        capabilities: [
          "media.transcode.ffmpeg",
          "runtime.ios_local",
          "runtime.sandboxed",
          "workspace.conversation_scoped",
          "network.disabled"
        ],
        permissions: [
          AgentNativePermissionRequirement(
            id: workspaceMediaPermission,
            title: "App-private media workspace",
            description: "Limits media conversion to the current GalaxySSI workspace."
          ),
          AgentNativePermissionRequirement(
            id: mediaRuntimePermission,
            title: "Signed media runtime",
            description: "Requires a signed local media runtime with FFmpeg capability."
          )
        ],
        consents: [
          consent(contentUriReadConsent, "Read source media", "Allows reading one selected or workspace-scoped media source."),
          consent(contentUriWriteConsent, "Write converted media", "Allows writing one converted media artifact."),
          consent(mediaTranscodeConsent, "Run media conversion", "Allows bounded offline media conversion with typed presets.")
        ],
        timeoutMillis: maxTranscodeTimeoutMillis,
        idempotency: .nonIdempotent
      )
    ]
  }

  static func kind(for toolId: String) -> AgentIOSMediaNativeToolKind? {
    switch toolId {
    case mediaMetadata:
      return .metadata
    case mediaPlaybackHandoff:
      return .playback
    case mediaFFmpegTranscode:
      return .transcode
    default:
      return nil
    }
  }

  static func targetMimeType(_ format: String) -> String? {
    targetFormats[format.lowercased()]?.mimeType
  }

  static func targetExtension(_ format: String) -> String? {
    targetFormats[format.lowercased()]?.fileExtension
  }

  private static func definition(
    provider: AgentIOSMediaNativeToolProviding,
    kind: AgentIOSMediaNativeToolKind,
    id: String,
    title: String,
    description: String,
    inputSchema: AgentMcpJSONObject,
    outputSchema: AgentMcpJSONObject,
    risk: AgentNativeToolRisk,
    capabilities: Set<String>,
    permissions: [AgentNativePermissionRequirement],
    consents: [AgentNativeConsentRequirement],
    timeoutMillis: Int64,
    idempotency: AgentNativeToolIdempotency = .idempotent
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: id,
      version: AgentPhoneNativeToolCatalog.version,
      title: title,
      description: description,
      location: .application,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      risk: risk,
      capabilities: capabilities,
      requiredPermissions: permissions,
      requiredConsents: consents,
      timeoutMillis: timeoutMillis,
      idempotency: idempotency,
      availability: provider.availability(kind: kind)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "implementation": provider.implementationId,
        "platform": "ios_phone",
        "source_scope": kind == .transcode ? "workspace_or_user_authorized_media" : "user_authorized_content_uri",
        "completion_semantics": kind == .playback ? "handoff_only" : "bounded_result",
        "network": kind == .transcode ? "disabled" : "not_required",
        "argument_policy": kind == .transcode ? "typed_presets_only" : "bounded_inputs"
      ]
    )
  }

  private static func mediaContentInputSchema() -> AgentMcpJSONObject {
    objectSchema(["content_uri": contentUriSchema()], required: ["content_uri"])
  }

  private static func mediaMetadataOutputSchema() -> AgentMcpJSONObject {
    objectSchema([
      "content_uri": contentUriSchema(),
      "content_type": stringSchema(maxLength: 255),
      "display_name": stringSchema(maxLength: 1_024),
      "size_bytes": integerSchema(minimum: -1),
      "duration_ms": integerSchema(minimum: 0),
      "width": integerSchema(minimum: 0),
      "height": integerSchema(minimum: 0),
      "rotation_degrees": integerSchema(minimum: 0, maximum: 359),
      "has_audio": boolSchema(),
      "has_video": boolSchema(),
      "observed_at_epoch_ms": integerSchema(minimum: 0),
      "source": contentSourceSchema()
    ], required: [
      "content_uri", "content_type", "display_name", "size_bytes", "duration_ms", "width", "height",
      "rotation_degrees", "has_audio", "has_video", "observed_at_epoch_ms", "source"
    ])
  }

  private static func mediaPlaybackOutputSchema() -> AgentMcpJSONObject {
    objectSchema([
      "launched": boolSchema(),
      "action": stringSchema(maxLength: 255),
      "handler_package": stringSchema(maxLength: 255),
      "completed": boolSchema(),
      "handed_off_at_epoch_ms": integerSchema(minimum: 0),
      "source": contentSourceSchema()
    ], required: ["launched", "action", "handler_package", "completed", "handed_off_at_epoch_ms", "source"])
  }

  private static func mediaTranscodeInputSchema() -> AgentMcpJSONObject {
    objectSchema([
      "content_uri": contentUriSchema(),
      "source_path": stringSchema(minLength: 1, maxLength: Int64(maxPathCharacters)),
      "destination_path": stringSchema(minLength: 1, maxLength: Int64(maxPathCharacters)),
      "target_format": stringSchema(enumValues: Array(targetFormats.keys).sorted()),
      "preset": stringSchema(enumValues: ["compact", "balanced", "high_quality"]),
      "start_ms": integerSchema(minimum: 0, maximum: 6 * 60 * 60 * 1_000),
      "duration_ms": integerSchema(minimum: 0, maximum: 6 * 60 * 60 * 1_000),
      "max_width": integerSchema(minimum: 16, maximum: 8_192),
      "max_height": integerSchema(minimum: 16, maximum: 8_192),
      "audio_bitrate_kbps": integerSchema(minimum: 32, maximum: 512),
      "timeout_ms": integerSchema(minimum: 100, maximum: maxTranscodeTimeoutMillis)
    ], required: ["target_format"])
  }

  private static func mediaTranscodeOutputSchema() -> AgentMcpJSONObject {
    objectSchema([
      "source_path": stringSchema(minLength: 1, maxLength: Int64(maxPathCharacters)),
      "destination_path": stringSchema(minLength: 1, maxLength: Int64(maxPathCharacters)),
      "target_format": stringSchema(enumValues: Array(targetFormats.keys).sorted()),
      "mime_type": stringSchema(minLength: 1, maxLength: 255),
      "size_bytes": integerSchema(minimum: 0, maximum: maxMediaBytes),
      "sha256": stringSchema(minLength: 64, maxLength: 64, pattern: "^[a-f0-9]{64}$"),
      "execution_duration_ms": integerSchema(minimum: 0, maximum: maxTranscodeTimeoutMillis),
      "artifacts": arraySchema(
        itemSchema: objectSchema([
          "relative_path": stringSchema(minLength: 1, maxLength: Int64(maxPathCharacters)),
          "size_bytes": integerSchema(minimum: 0, maximum: maxMediaBytes),
          "sha256": stringSchema(minLength: 64, maxLength: 64, pattern: "^[a-f0-9]{64}$"),
          "host_path": stringSchema(maxLength: 4_096),
          "artifact_kind": stringSchema(maxLength: 64)
        ], required: ["relative_path", "size_bytes", "sha256"]),
        maxItems: 1
      ),
      "execution_receipt": objectSchema([:]),
      "network_enabled": boolSchema(),
      "completed_at_epoch_ms": integerSchema(minimum: 0)
    ], required: [
      "source_path",
      "destination_path",
      "target_format",
      "mime_type",
      "size_bytes",
      "sha256",
      "execution_duration_ms",
      "artifacts",
      "execution_receipt",
      "network_enabled",
      "completed_at_epoch_ms"
    ])
  }

  private static func contentSourceSchema() -> AgentMcpJSONObject {
    objectSchema(["content_uri": contentUriSchema()])
  }

  private static func contentUriSchema() -> AgentMcpJSONObject {
    stringSchema(minLength: 1, maxLength: Int64(maxContentUriCharacters))
  }

  private static func objectSchema(
    _ properties: [String: AgentMcpJSONObject],
    required: [String] = []
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties.mapValues { .object($0) }),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(true)
    ]
  }

  private static func arraySchema(itemSchema: AgentMcpJSONObject, maxItems: Int) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(itemSchema),
      "maxItems": .int(Int64(maxItems))
    ]
  }

  private static func stringSchema(
    minLength: Int64? = nil,
    maxLength: Int64? = nil,
    pattern: String = "",
    enumValues: [String] = []
  ) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("string")]
    if let minLength { schema["minLength"] = .int(minLength) }
    if let maxLength { schema["maxLength"] = .int(maxLength) }
    if !pattern.isEmpty { schema["pattern"] = .string(pattern) }
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

  private static func contentUriRequirement() -> AgentNativePermissionRequirement {
    AgentNativePermissionRequirement(
      id: contentUriPermission,
      title: "User-authorized media reference",
      description: "Limits media access to a selected content URI or security-scoped file URL."
    )
  }

  private static func consent(_ id: String, _ title: String, _ description: String) -> AgentNativeConsentRequirement {
    AgentNativeConsentRequirement(id: id, title: title, description: description)
  }

  private static let targetFormats: [String: (fileExtension: String, mimeType: String)] = [
    "mp4": ("mp4", "video/mp4"),
    "m4a": ("m4a", "audio/mp4"),
    "wav": ("wav", "audio/wav"),
    "flac": ("flac", "audio/flac"),
    "gif": ("gif", "image/gif"),
    "png": ("png", "image/png"),
    "jpg": ("jpg", "image/jpeg")
  ]
}

struct AgentIOSMediaNativeToolExecutor {
  var provider: AgentIOSMediaNativeToolProviding
  var nowMillis: () -> Int64

  init(
    provider: AgentIOSMediaNativeToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.provider = provider
    self.nowMillis = nowMillis
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
    guard let kind = AgentIOSMediaNativeToolCatalog.kind(for: invocation.descriptor.id) else {
      return AgentNativeToolExecutionResult.failure(
        code: "media_unknown_tool",
        message: "Unknown media native tool."
      )
    }
    switch kind {
    case .metadata:
      return try inspectMetadata(invocation)
    case .playback:
      return try handoffPlayback(invocation)
    case .transcode:
      return try transcode(invocation)
    }
  }

  private func inspectMetadata(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    let uri = contentUri(invocation.input)
    guard isAuthorizedMediaReference(uri) else {
      return failure("invalid_content_uri", "Media content_uri must be a selected content:// or file:// reference")
    }
    let execution = provider.inspectMetadata(contentUri: uri, invocation: invocation)
    guard execution.isSuccess else { return execution }
    var output = execution.output
    output["content_uri"] = output["content_uri"] ?? .string(uri)
    output["source"] = output["source"] ?? .object(["content_uri": .string(uri)])
    output["observed_at_epoch_ms"] = output["observed_at_epoch_ms"] ?? .int(max(0, nowMillis()))
    var metadata = execution.metadata
    metadata["media_implementation"] = metadata["media_implementation"] ?? .string(provider.implementationId)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "Selected media metadata inspected" : execution.message,
      metadata: metadata
    )
  }

  private func handoffPlayback(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    let uri = contentUri(invocation.input)
    guard isAuthorizedMediaReference(uri) else {
      return failure("invalid_content_uri", "Media content_uri must be a selected content:// or file:// reference")
    }
    let execution = provider.handoffPlayback(
      contentUri: uri,
      contentType: string(invocation.input, "content_type", limit: 255),
      invocation: invocation
    )
    guard execution.isSuccess else { return execution }
    var output = execution.output
    output["completed"] = output["completed"] ?? .bool(false)
    output["handed_off_at_epoch_ms"] = output["handed_off_at_epoch_ms"] ?? .int(max(0, nowMillis()))
    output["source"] = output["source"] ?? .object(["content_uri": .string(uri)])
    var metadata = execution.metadata
    metadata["playback_implementation"] = metadata["playback_implementation"] ?? .string(provider.implementationId)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "Media playback handed off to iOS" : execution.message,
      metadata: metadata
    )
  }

  private func transcode(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    guard let request = transcodeRequest(invocation) else {
      return failure("invalid_transcode_source", "Media conversion requires exactly one content_uri or source_path")
    }
    let plannedRequest: AgentIOSMediaTranscodeRequest
    do {
      plannedRequest = try validatedTranscodeRequest(request)
    } catch {
      return failure(
        "invalid_transcode_request",
        error.localizedDescription.ifBlank("Media conversion request is invalid")
      )
    }
    if !plannedRequest.destinationPath.isEmpty,
       let expected = AgentIOSMediaNativeToolCatalog.targetExtension(plannedRequest.targetFormat),
       !plannedRequest.destinationPath.lowercased().hasSuffix(".\(expected)") {
      return failure("extension_mismatch", "Destination extension must match \(plannedRequest.targetFormat)")
    }
    let execution = provider.transcode(request: plannedRequest, invocation: invocation)
    guard execution.isSuccess else { return execution }
    var output = execution.output
    output["target_format"] = output["target_format"] ?? .string(plannedRequest.targetFormat)
    output["mime_type"] = output["mime_type"] ?? .string(AgentIOSMediaNativeToolCatalog.targetMimeType(plannedRequest.targetFormat) ?? "")
    output["network_enabled"] = output["network_enabled"] ?? .bool(false)
    output["completed_at_epoch_ms"] = output["completed_at_epoch_ms"] ?? .int(max(0, nowMillis()))
    var metadata = execution.metadata
    metadata["media_implementation"] = metadata["media_implementation"] ?? .string(provider.implementationId)
    if !plannedRequest.sourcePath.isEmpty, let plan = try? AgentIOSFfmpegTranscodePlanner.create(request: plannedRequest) {
      metadata["ffmpeg_argument_count"] = .int(Int64(plan.arguments.count))
      metadata["ffmpeg_network_enabled"] = .bool(false)
    }
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "Media converted in the local iOS FFmpeg runtime" : execution.message,
      metadata: metadata
    )
  }

  private func validatedTranscodeRequest(
    _ request: AgentIOSMediaTranscodeRequest
  ) throws -> AgentIOSMediaTranscodeRequest {
    var output = request
    if !request.sourcePath.isEmpty {
      let plan = try AgentIOSFfmpegTranscodePlanner.create(request: request)
      output.sourcePath = plan.sourcePath
      output.destinationPath = plan.destinationPath
      return output
    }
    if !request.destinationPath.isEmpty {
      output.destinationPath = try AgentIOSMediaWorkspacePaths.normalizeRelative(
        request.destinationPath,
        field: "destination_path"
      )
    }
    return output
  }

  private func transcodeRequest(_ invocation: AgentNativeToolInvocation) -> AgentIOSMediaTranscodeRequest? {
    let contentUri = contentUri(invocation.input)
    let sourcePath = string(invocation.input, "source_path", limit: AgentIOSMediaNativeToolCatalog.maxPathCharacters)
    guard contentUri.isEmpty != sourcePath.isEmpty else { return nil }
    if !contentUri.isEmpty && !isAuthorizedMediaReference(contentUri) { return nil }
    let targetFormat = string(invocation.input, "target_format", limit: 16).lowercased()
    guard AgentIOSMediaNativeToolCatalog.targetMimeType(targetFormat) != nil else { return nil }
    let requestedTimeout = int64(
      invocation.input,
      "timeout_ms",
      defaultValue: 5 * 60_000,
      minimum: 100,
      maximum: AgentIOSMediaNativeToolCatalog.maxTranscodeTimeoutMillis
    )
    return AgentIOSMediaTranscodeRequest(
      contentUri: contentUri,
      sourcePath: sourcePath,
      destinationPath: string(invocation.input, "destination_path", limit: AgentIOSMediaNativeToolCatalog.maxPathCharacters),
      targetFormat: targetFormat,
      preset: string(invocation.input, "preset", defaultValue: "balanced", allowedValues: ["compact", "balanced", "high_quality"]),
      startMillis: int64(invocation.input, "start_ms", defaultValue: 0, minimum: 0, maximum: 6 * 60 * 60 * 1_000),
      durationMillis: int64(invocation.input, "duration_ms", defaultValue: 0, minimum: 0, maximum: 6 * 60 * 60 * 1_000),
      maxWidth: int(invocation.input, "max_width", defaultValue: 0, minimum: 0, maximum: 8_192),
      maxHeight: int(invocation.input, "max_height", defaultValue: 0, minimum: 0, maximum: 8_192),
      audioBitrateKbps: int(invocation.input, "audio_bitrate_kbps", defaultValue: 0, minimum: 0, maximum: 512),
      timeoutMillis: max(100, min(requestedTimeout, invocation.remainingTimeMillis)),
      workspaceId: invocation.context.attributes["workspace_id"] ?? workspaceId(invocation.context),
      invocationId: invocation.context.invocationId
    )
  }

  private func contentUri(_ input: AgentMcpJSONObject) -> String {
    string(input, "content_uri", limit: AgentIOSMediaNativeToolCatalog.maxContentUriCharacters)
  }

  private func isAuthorizedMediaReference(_ value: String) -> Bool {
    value.hasPrefix("content://") || value.hasPrefix("file://")
  }

  private func workspaceId(_ context: AgentNativeToolInvocationContext) -> String {
    let conversation = context.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let session = context.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    let raw = [conversation, session].filter { !$0.isEmpty }.joined(separator: "-")
    return raw.isEmpty ? "default" : String(raw.prefix(96))
  }

  private func string(_ input: AgentMcpJSONObject, _ key: String, limit: Int) -> String {
    String((input[key]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }

  private func string(
    _ input: AgentMcpJSONObject,
    _ key: String,
    defaultValue: String,
    allowedValues: Set<String>
  ) -> String {
    let value = string(input, key, limit: 64).lowercased()
    return allowedValues.contains(value) ? value : defaultValue
  }

  private func int(_ input: AgentMcpJSONObject, _ key: String, defaultValue: Int, minimum: Int, maximum: Int) -> Int {
    let value = Int(input[key]?.intValue ?? Int64(defaultValue))
    return max(minimum, min(value, maximum))
  }

  private func int64(_ input: AgentMcpJSONObject, _ key: String, defaultValue: Int64, minimum: Int64, maximum: Int64) -> Int64 {
    let value = input[key]?.intValue ?? defaultValue
    return max(minimum, min(value, maximum))
  }

  private func failure(_ code: String, _ message: String) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(code: code, message: message, retryable: false)
  }
}
