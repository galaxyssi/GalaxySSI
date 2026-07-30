import CryptoKit
import Foundation

struct AgentPhoneNativeToolDefinition: Codable, Equatable, Identifiable {
  var descriptor: AgentNativeToolDescriptor
  var executorId: String
  var provenanceMetadata: [String: String]

  var id: String { descriptor.id }

  init(
    descriptor: AgentNativeToolDescriptor,
    executorId: String,
    provenanceMetadata: [String: String] = [:]
  ) {
    self.descriptor = descriptor
    self.executorId = executorId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.provenanceMetadata = provenanceMetadata
  }

  enum CodingKeys: String, CodingKey {
    case descriptor
    case executorId = "executor_id"
    case provenanceMetadata = "provenance_metadata"
  }
}

struct AgentIOSNotificationItem: Equatable {
  var key: String
  var packageName: String
  var title: String
  var textPreview: String
  var category: String
  var postedAtMillis: Int64
  var canReply: Bool
  var sensitiveFlags: [String]

  init(
    key: String,
    packageName: String,
    title: String,
    textPreview: String,
    category: String = "",
    postedAtMillis: Int64 = 0,
    canReply: Bool = false,
    sensitiveFlags: [String] = []
  ) {
    self.key = key
    self.packageName = packageName
    self.title = title
    self.textPreview = textPreview
    self.category = category
    self.postedAtMillis = max(0, postedAtMillis)
    self.canReply = canReply
    self.sensitiveFlags = sensitiveFlags
  }
}

struct AgentIOSNotificationContext: Equatable {
  var hasAccess: Bool
  var items: [AgentIOSNotificationItem]
  var sensitiveFlags: [String]
  var totalCount: Int

  init(
    hasAccess: Bool = false,
    items: [AgentIOSNotificationItem] = [],
    sensitiveFlags: [String] = [],
    totalCount: Int? = nil
  ) {
    self.hasAccess = hasAccess
    self.items = items
    self.sensitiveFlags = sensitiveFlags
    self.totalCount = max(0, totalCount ?? items.count)
  }
}

struct AgentIOSNotificationReplyResult: Equatable {
  var success: Bool
  var message: String
  var code: String
  var retryable: Bool
  var notificationPackage: String
  var notificationTitle: String

  init(
    success: Bool,
    message: String,
    code: String = "",
    retryable: Bool = false,
    notificationPackage: String = "",
    notificationTitle: String = ""
  ) {
    self.success = success
    self.message = message
    self.code = code
    self.retryable = retryable
    self.notificationPackage = notificationPackage
    self.notificationTitle = notificationTitle
  }
}

protocol AgentIOSNotificationToolProviding {
  var implementationId: String { get }
  func availability() -> AgentNativeToolAvailability
  func snapshot(limit: Int) -> AgentIOSNotificationContext
  func reply(notificationKey: String, text: String) -> AgentIOSNotificationReplyResult
}

struct AgentIOSUnavailableNotificationToolProvider: AgentIOSNotificationToolProviding {
  var implementationId: String = "signalasi.ios.notification_unconfigured"

  func availability() -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "iOS notification provider is not connected"
    )
  }

  func snapshot(limit: Int) -> AgentIOSNotificationContext {
    AgentIOSNotificationContext(hasAccess: false)
  }

  func reply(notificationKey: String, text: String) -> AgentIOSNotificationReplyResult {
    AgentIOSNotificationReplyResult(
      success: false,
      message: "iOS notification reply provider is not connected",
      code: "notification_provider_unavailable",
      retryable: true
    )
  }
}

enum AgentIOSNotificationNativeToolCatalog {
  static let notificationsList = AgentPhoneCapabilityNativeCoverage.notificationsList
  static let notificationReply = AgentPhoneCapabilityNativeCoverage.notificationReply

  static let notificationAccessPermission = "signalasi.scope.ios_signalasi_notifications"
  static let readConsent = "signalasi.consent.notification_read"
  static let replyConsent = "signalasi.consent.sensitive_action_confirmation"
  static let executorId = "signalasi.ios_notification_tools"

  static let defaultLimit = 6
  static let maxNotifications = 12
  static let maxKeyCharacters = 8_192
  static let maxReplyCharacters = 2_000
  static let maxTitleCharacters = 160
  static let maxTextPreviewCharacters = 320

  static let toolIds: Set<String> = [notificationsList, notificationReply]

  static func definitions(
    provider: AgentIOSNotificationToolProviding = AgentIOSUnavailableNotificationToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    [
      definition(
        provider: provider,
        id: notificationsList,
        title: "List current notifications",
        description: "Reads bounded SignalASI-visible notification fields; sensitive content is redacted before it reaches the Agent.",
        inputSchema: objectSchema(properties: [
          "limit": integerSchema(minimum: 1, maximum: Int64(maxNotifications)),
          "reply_capable_only": boolSchema()
        ]),
        capabilities: ["notifications.posted.read", "notifications.sensitive.redaction"],
        consentId: readConsent,
        idempotency: .idempotent
      ),
      definition(
        provider: provider,
        id: notificationReply,
        title: "Reply to a current notification",
        description: "Dispatches text through one live SignalASI-owned reply action; sensitive and stale targets are rejected.",
        inputSchema: objectSchema(
          properties: [
            "notification_key": stringSchema(minLength: 1, maxLength: Int64(maxKeyCharacters)),
            "reply_text": stringSchema(minLength: 1, maxLength: Int64(maxReplyCharacters))
          ],
          required: ["notification_key", "reply_text"]
        ),
        capabilities: ["notifications.remote_input.reply", "notifications.stale_target_guard"],
        consentId: replyConsent,
        idempotency: .idempotencyKeyRequired
      )
    ]
  }

  private static func definition(
    provider: AgentIOSNotificationToolProviding,
    id: String,
    title: String,
    description: String,
    inputSchema: AgentMcpJSONObject,
    capabilities: Set<String>,
    consentId: String,
    idempotency: AgentNativeToolIdempotency
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: id,
      version: AgentPhoneNativeToolCatalog.version,
      title: title,
      description: description,
      location: .application,
      inputSchema: inputSchema,
      outputSchema: AgentNativeToolDescriptor.objectSchema(),
      risk: .high,
      capabilities: capabilities,
      requiredPermissions: [
        AgentNativePermissionRequirement(
          id: notificationAccessPermission,
          title: "SignalASI notification access",
          description: "Limits iOS notification tooling to SignalASI-owned notification state and reply actions."
        )
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(
          id: consentId,
          title: consentId == readConsent ? "Read current notifications" : "Send notification reply",
          description: consentId == readConsent
            ? "Allows this invocation to read bounded, redacted notification metadata."
            : "Confirms dispatch of this exact external reply."
        )
      ],
      timeoutMillis: 10_000,
      idempotency: idempotency,
      availability: provider.availability()
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "implementation": provider.implementationId,
        "source": "ios_signalasi_notifications",
        "sensitive_content_policy": "redact",
        "reply_completion_semantics": "reply_action_dispatched_not_delivered"
      ]
    )
  }

  private static func objectSchema(
    properties: [String: AgentMcpJSONObject] = [:],
    required: [String] = []
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties.mapValues { .object($0) }),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(false)
    ]
  }

  private static func stringSchema(minLength: Int64? = nil, maxLength: Int64) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = [
      "type": .string("string"),
      "maxLength": .int(maxLength)
    ]
    if let minLength { schema["minLength"] = .int(minLength) }
    return schema
  }

  private static func integerSchema(minimum: Int64, maximum: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("integer"),
      "minimum": .int(minimum),
      "maximum": .int(maximum)
    ]
  }

  private static func boolSchema() -> AgentMcpJSONObject {
    ["type": .string("boolean")]
  }
}

struct AgentIOSNotificationNativeToolExecutor {
  var provider: AgentIOSNotificationToolProviding
  var nowMillis: () -> Int64

  init(
    provider: AgentIOSNotificationToolProviding,
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
        let result = self.execute(invocation)
        try invocation.checkpoint()
        return result
      }
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    switch invocation.descriptor.id {
    case AgentIOSNotificationNativeToolCatalog.notificationsList:
      return list(invocation)
    case AgentIOSNotificationNativeToolCatalog.notificationReply:
      return reply(invocation)
    default:
      return AgentNativeToolExecutionResult.failure(
        code: "notification_unknown_tool",
        message: "Unknown notification native tool."
      )
    }
  }

  private func list(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let limit = int(
      invocation.input,
      "limit",
      defaultValue: AgentIOSNotificationNativeToolCatalog.defaultLimit,
      minimum: 1,
      maximum: AgentIOSNotificationNativeToolCatalog.maxNotifications
    )
    let replyOnly = invocation.input["reply_capable_only"]?.boolValue == true
    let context = provider.snapshot(limit: AgentIOSNotificationNativeToolCatalog.maxNotifications)
    guard context.hasAccess else {
      return AgentNativeToolExecutionResult.failure(
        code: "notification_access_unavailable",
        message: "iOS notification access is not connected",
        retryable: true
      )
    }
    let candidates = context.items.filter { item in
      !replyOnly || (item.canReply && item.sensitiveFlags.isEmpty)
    }
    let selected = Array(candidates.prefix(limit))
    let sensitiveCount = context.items.filter { !$0.sensitiveFlags.isEmpty }.count
    return AgentNativeToolExecutionResult.success(
      output: [
        "notifications": .array(selected.map { .object(notificationValue($0)) }),
        "result_count": .int(Int64(selected.count)),
        "total_observed": .int(Int64(max(context.totalCount, context.items.count))),
        "truncated": .bool(candidates.count > limit || context.totalCount > context.items.count),
        "sensitive_count": .int(Int64(sensitiveCount)),
        "observed_at_epoch_ms": .int(max(0, nowMillis()))
      ],
      message: "Listed \(selected.count) current notifications with sensitive content redacted",
      metadata: [
        "raw_sensitive_content_exposed": .bool(false),
        "notification_limit": .int(Int64(AgentIOSNotificationNativeToolCatalog.maxNotifications))
      ]
    )
  }

  private func reply(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let key = string(invocation.input, "notification_key", limit: AgentIOSNotificationNativeToolCatalog.maxKeyCharacters)
    let text = string(invocation.input, "reply_text", limit: AgentIOSNotificationNativeToolCatalog.maxReplyCharacters)
    let result = provider.reply(notificationKey: key, text: text)
    let keyHash = sha256Hex(Data(key.utf8))
    if !result.success {
      return AgentNativeToolExecutionResult.failure(
        code: result.code.isEmpty ? "notification_reply_failed" : result.code,
        message: result.message.isEmpty ? "Notification reply failed" : result.message,
        retryable: result.retryable,
        details: [
          "notification_key_sha256": .string(keyHash),
          "package_name": .string(String(result.notificationPackage.prefix(255)))
        ]
      )
    }
    return AgentNativeToolExecutionResult.success(
      output: [
        "dispatch_accepted": .bool(true),
        "delivery_verified": .bool(false),
        "package_name": .string(String(result.notificationPackage.prefix(255))),
        "target_title": .string(String(result.notificationTitle.prefix(AgentIOSNotificationNativeToolCatalog.maxTitleCharacters))),
        "reply_length": .int(Int64(text.count)),
        "notification_key_sha256": .string(keyHash),
        "dispatched_at_epoch_ms": .int(max(0, nowMillis()))
      ],
      message: result.message,
      metadata: [
        "handoff_only": .bool(true),
        "delivery_receipt_available": .bool(false),
        "reply_text_retained": .bool(false)
      ]
    )
  }

  private func notificationValue(_ item: AgentIOSNotificationItem) -> AgentMcpJSONObject {
    let redacted = !item.sensitiveFlags.isEmpty
    return [
      "notification_key": .string(redacted ? "" : String(item.key.prefix(AgentIOSNotificationNativeToolCatalog.maxKeyCharacters))),
      "package_name": .string(String(item.packageName.prefix(255))),
      "title": .string(redacted ? "" : String(item.title.prefix(AgentIOSNotificationNativeToolCatalog.maxTitleCharacters))),
      "text_preview": .string(redacted ? "" : String(item.textPreview.prefix(AgentIOSNotificationNativeToolCatalog.maxTextPreviewCharacters))),
      "category": .string(String(item.category.prefix(32))),
      "posted_at_epoch_ms": .int(max(0, item.postedAtMillis)),
      "can_reply": .bool(item.canReply && !redacted),
      "redacted": .bool(redacted),
      "sensitive_flag_count": .int(Int64(item.sensitiveFlags.count))
    ]
  }

  private func string(_ input: AgentMcpJSONObject, _ key: String, limit: Int) -> String {
    String((input[key]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }

  private func int(_ input: AgentMcpJSONObject, _ key: String, defaultValue: Int, minimum: Int, maximum: Int) -> Int {
    let value = Int(input[key]?.intValue ?? Int64(defaultValue))
    return max(minimum, min(value, maximum))
  }

  private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

enum AgentIOSVisibleCaptureKind: String, Codable, CaseIterable, Identifiable {
  case photo
  case audio

  var id: String { rawValue }
}

enum AgentIOSVisibleCaptureStatus: String, Codable, CaseIterable, Identifiable {
  case succeeded
  case cancelled
  case failed

  var id: String { rawValue }
}

struct AgentIOSVisibleCaptureArtifact: Equatable {
  var kind: AgentIOSVisibleCaptureKind
  var contentUri: String
  var mimeType: String
  var sizeBytes: Int64
  var widthPixels: Int
  var heightPixels: Int
  var durationMillis: Int64
  var capturedAtEpochMillis: Int64
  var completedBy: String

  init(
    kind: AgentIOSVisibleCaptureKind,
    contentUri: String,
    mimeType: String,
    sizeBytes: Int64 = 0,
    widthPixels: Int = 0,
    heightPixels: Int = 0,
    durationMillis: Int64 = 0,
    capturedAtEpochMillis: Int64 = 0,
    completedBy: String
  ) {
    self.kind = kind
    self.contentUri = contentUri
    self.mimeType = mimeType
    self.sizeBytes = max(0, sizeBytes)
    self.widthPixels = max(0, widthPixels)
    self.heightPixels = max(0, heightPixels)
    self.durationMillis = max(0, durationMillis)
    self.capturedAtEpochMillis = max(0, capturedAtEpochMillis)
    self.completedBy = completedBy
  }
}

struct AgentIOSVisibleCaptureOutcome: Equatable {
  var status: AgentIOSVisibleCaptureStatus
  var artifact: AgentIOSVisibleCaptureArtifact?
  var code: String
  var message: String
  var retryable: Bool

  init(
    status: AgentIOSVisibleCaptureStatus,
    artifact: AgentIOSVisibleCaptureArtifact? = nil,
    code: String = "",
    message: String = "",
    retryable: Bool = false
  ) {
    self.status = status
    self.artifact = artifact
    self.code = code
    self.message = message
    self.retryable = retryable
  }
}

protocol AgentIOSVisibleCaptureToolProviding {
  var implementationId: String { get }
  func availability(kind: AgentIOSVisibleCaptureKind) -> AgentNativeToolAvailability
  func capturePhoto(facing: String, invocation: AgentNativeToolInvocation) -> AgentIOSVisibleCaptureOutcome
  func recordAudio(maxDurationSeconds: Int, invocation: AgentNativeToolInvocation) -> AgentIOSVisibleCaptureOutcome
}

struct AgentIOSUnavailableVisibleCaptureToolProvider: AgentIOSVisibleCaptureToolProviding {
  var implementationId: String = "signalasi.ios.visible_capture_unconfigured"

  func availability(kind: AgentIOSVisibleCaptureKind) -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "iOS visible capture provider is not connected"
    )
  }

  func capturePhoto(facing: String, invocation: AgentNativeToolInvocation) -> AgentIOSVisibleCaptureOutcome {
    AgentIOSVisibleCaptureOutcome(
      status: .failed,
      code: "visible_capture_provider_unavailable",
      message: "iOS visible photo capture provider is not connected",
      retryable: true
    )
  }

  func recordAudio(maxDurationSeconds: Int, invocation: AgentNativeToolInvocation) -> AgentIOSVisibleCaptureOutcome {
    AgentIOSVisibleCaptureOutcome(
      status: .failed,
      code: "visible_capture_provider_unavailable",
      message: "iOS visible audio capture provider is not connected",
      retryable: true
    )
  }
}

enum AgentIOSVisibleCaptureNativeToolCatalog {
  static let cameraCapture = AgentPhoneCapabilityNativeCoverage.cameraCaptureVisible
  static let microphoneRecord = AgentPhoneCapabilityNativeCoverage.microphoneRecordVisible

  static let cameraPermission = "NSCameraUsageDescription"
  static let microphonePermission = "NSMicrophoneUsageDescription"
  static let runtimePermissionConsent = "signalasi.consent.runtime_permission_dialog"
  static let userVisibleCaptureConsent = "signalasi.consent.user_visible_capture"
  static let executorId = "signalasi.ios_visible_capture"

  static let defaultAudioDurationSeconds = 5
  static let maxAudioDurationSeconds = 30
  static let maxUriCharacters = 4_096
  static let maxMimeTypeCharacters = 128
  static let maxCompletedByCharacters = 64

  static let toolIds: Set<String> = [cameraCapture, microphoneRecord]

  static func definitions(
    provider: AgentIOSVisibleCaptureToolProviding = AgentIOSUnavailableVisibleCaptureToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    [
      definition(
        provider: provider,
        kind: .photo,
        id: cameraCapture,
        title: "Capture a user-visible photo",
        description: "Opens one foreground iOS camera capture flow and returns only a bounded artifact URI receipt.",
        permission: permission(
          cameraPermission,
          "Camera",
          "Allows one foreground, user-visible photo capture."
        ),
        capabilities: ["camera.capture.user_visible", "artifact.image.content_uri"],
        inputSchema: objectSchema(properties: [
          "facing": stringSchema(enumValues: ["back", "front", "any"])
        ]),
        timeoutMillis: 30_000
      ),
      definition(
        provider: provider,
        kind: .audio,
        id: microphoneRecord,
        title: "Record user-visible audio",
        description: "Opens one foreground iOS audio recording flow for a bounded duration and returns only an artifact URI receipt.",
        permission: permission(
          microphonePermission,
          "Microphone",
          "Allows one foreground, user-visible audio recording."
        ),
        capabilities: ["microphone.record.user_visible", "artifact.audio.content_uri"],
        inputSchema: objectSchema(properties: [
          "max_duration_seconds": integerSchema(
            minimum: 1,
            maximum: Int64(maxAudioDurationSeconds)
          )
        ]),
        timeoutMillis: Int64(maxAudioDurationSeconds + 15) * 1_000
      )
    ]
  }

  static func artifactValue(_ artifact: AgentIOSVisibleCaptureArtifact) -> AgentMcpJSONObject {
    [
      "kind": .string(artifact.kind.rawValue),
      "content_uri": .string(String(artifact.contentUri.prefix(maxUriCharacters))),
      "mime_type": .string(String(artifact.mimeType.prefix(maxMimeTypeCharacters))),
      "size_bytes": .int(max(0, artifact.sizeBytes)),
      "width_px": .int(Int64(max(0, artifact.widthPixels))),
      "height_px": .int(Int64(max(0, artifact.heightPixels))),
      "duration_ms": .int(max(0, artifact.durationMillis)),
      "captured_at_epoch_ms": .int(max(0, artifact.capturedAtEpochMillis)),
      "user_visible": .bool(true),
      "completed_by": .string(String(artifact.completedBy.prefix(maxCompletedByCharacters)))
    ]
  }

  static func verifyArtifact(_ output: AgentMcpJSONObject) -> AgentNativeToolVerification {
    let uri = output["content_uri"]?.stringValue ?? ""
    let visible = output["user_visible"]?.boolValue == true
    let acceptedScheme = uri.hasPrefix("content://") || uri.hasPrefix("file://")
    let scheme = uriScheme(uri)
    if acceptedScheme && visible {
      return AgentNativeToolVerification(
        status: .passed,
        message: "A user-visible capture artifact URI was returned",
        evidence: ["uri_scheme": .string(scheme)]
      )
    }
    return AgentNativeToolVerification(
      status: .failed,
      message: visible ? "Capture did not return a supported artifact URI" : "Capture was not marked user-visible",
      evidence: [
        "uri_scheme": .string(scheme),
        "user_visible": .bool(visible)
      ]
    )
  }

  private static func uriScheme(_ uri: String) -> String {
    let prefix = String(uri.prefix(16))
    return prefix.split(separator: ":", maxSplits: 1).first.map { String($0) } ?? ""
  }

  private static func definition(
    provider: AgentIOSVisibleCaptureToolProviding,
    kind: AgentIOSVisibleCaptureKind,
    id: String,
    title: String,
    description: String,
    permission: AgentNativePermissionRequirement,
    capabilities: Set<String>,
    inputSchema: AgentMcpJSONObject,
    timeoutMillis: Int64
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: id,
      version: AgentPhoneNativeToolCatalog.version,
      title: title,
      description: description,
      location: .application,
      inputSchema: inputSchema,
      outputSchema: artifactSchema(),
      risk: .high,
      capabilities: capabilities,
      requiredPermissions: [permission],
      requiredConsents: [
        consent(
          runtimePermissionConsent,
          "iOS runtime permission",
          "The iOS runtime permission dialog must be accepted before capture."
        ),
        consent(
          userVisibleCaptureConsent,
          "User-visible capture",
          "Capture must stay visible and may be cancelled by the user."
        )
      ],
      timeoutMillis: timeoutMillis,
      idempotency: .nonIdempotent,
      availability: provider.availability(kind: kind)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "implementation": provider.implementationId,
        "capture_surface": "foreground_user_visible_ios",
        "privacy_indicator": "ios_managed",
        "background_capture": "false",
        "artifact_contract": "content-uri-v1"
      ]
    )
  }

  private static func artifactSchema() -> AgentMcpJSONObject {
    objectSchema(
      properties: [
        "kind": stringSchema(enumValues: AgentIOSVisibleCaptureKind.allCases.map(\.rawValue)),
        "content_uri": stringSchema(minLength: 1, maxLength: Int64(maxUriCharacters)),
        "mime_type": stringSchema(minLength: 1, maxLength: Int64(maxMimeTypeCharacters)),
        "size_bytes": integerSchema(minimum: 0),
        "width_px": integerSchema(minimum: 0, maximum: 100_000),
        "height_px": integerSchema(minimum: 0, maximum: 100_000),
        "duration_ms": integerSchema(minimum: 0, maximum: 60_000),
        "captured_at_epoch_ms": integerSchema(minimum: 0),
        "user_visible": boolSchema(),
        "completed_by": stringSchema(minLength: 1, maxLength: Int64(maxCompletedByCharacters))
      ],
      required: [
        "kind",
        "content_uri",
        "mime_type",
        "size_bytes",
        "width_px",
        "height_px",
        "duration_ms",
        "captured_at_epoch_ms",
        "user_visible",
        "completed_by"
      ]
    )
  }

  private static func objectSchema(
    properties: [String: AgentMcpJSONObject] = [:],
    required: [String] = []
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties.mapValues { .object($0) }),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(false)
    ]
  }

  private static func stringSchema(
    minLength: Int64? = nil,
    maxLength: Int64? = nil,
    enumValues: [String] = []
  ) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("string")]
    if let minLength { schema["minLength"] = .int(minLength) }
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

  private static func permission(
    _ id: String,
    _ title: String,
    _ description: String
  ) -> AgentNativePermissionRequirement {
    AgentNativePermissionRequirement(id: id, title: title, description: description)
  }

  private static func consent(
    _ id: String,
    _ title: String,
    _ description: String
  ) -> AgentNativeConsentRequirement {
    AgentNativeConsentRequirement(id: id, title: title, description: description)
  }
}

struct AgentIOSVisibleCaptureNativeToolExecutor {
  var provider: AgentIOSVisibleCaptureToolProviding

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = try self.execute(invocation)
        try invocation.checkpoint()
        return result
      },
      verifier: { _, execution in
        AgentIOSVisibleCaptureNativeToolCatalog.verifyArtifact(execution.output)
      }
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    try invocation.reportProgress(
      stage: "opening_visible_capture",
      message: "Opening the foreground user-visible iOS capture surface",
      percent: 10
    )
    let outcome: AgentIOSVisibleCaptureOutcome
    switch invocation.descriptor.id {
    case AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture:
      outcome = provider.capturePhoto(
        facing: string(
          invocation.input,
          "facing",
          defaultValue: "back",
          allowedValues: ["back", "front", "any"]
        ),
        invocation: invocation
      )
    case AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord:
      outcome = provider.recordAudio(
        maxDurationSeconds: int(
          invocation.input,
          "max_duration_seconds",
          defaultValue: AgentIOSVisibleCaptureNativeToolCatalog.defaultAudioDurationSeconds,
          minimum: 1,
          maximum: AgentIOSVisibleCaptureNativeToolCatalog.maxAudioDurationSeconds
        ),
        invocation: invocation
      )
    default:
      return AgentNativeToolExecutionResult.failure(
        code: "visible_capture_unknown_tool",
        message: "Unknown visible capture native tool."
      )
    }
    try invocation.checkpoint()
    return try result(outcome, invocation: invocation)
  }

  private func result(
    _ outcome: AgentIOSVisibleCaptureOutcome,
    invocation: AgentNativeToolInvocation
  ) throws -> AgentNativeToolExecutionResult {
    switch outcome.status {
    case .succeeded:
      guard let artifact = outcome.artifact else {
        return AgentNativeToolExecutionResult.failure(
          code: "capture_result_missing",
          message: "The visible capture returned no artifact"
        )
      }
      try invocation.reportProgress(
        stage: "capture_complete",
        message: "User-visible capture completed",
        percent: 100
      )
      let message = artifact.kind == .photo
        ? "Captured one user-visible photo"
        : "Recorded user-visible audio"
      return AgentNativeToolExecutionResult.success(
        output: AgentIOSVisibleCaptureNativeToolCatalog.artifactValue(artifact),
        message: message,
        metadata: [
          "background_capture": .bool(false),
          "raw_media_in_receipt": .bool(false)
        ]
      )
    case .cancelled:
      return AgentNativeToolExecutionResult.failure(
        code: outcome.code.isEmpty ? "capture_cancelled" : outcome.code,
        message: outcome.message.isEmpty ? "The user cancelled the visible capture" : outcome.message
      )
    case .failed:
      return AgentNativeToolExecutionResult.failure(
        code: outcome.code.isEmpty ? "capture_failed" : outcome.code,
        message: outcome.message.isEmpty ? "The visible capture failed" : outcome.message,
        retryable: outcome.retryable || ["capture_busy", "camera_unavailable", "microphone_unavailable"].contains(outcome.code),
        details: ["background_capture": .bool(false)]
      )
    }
  }

  private func string(
    _ input: AgentMcpJSONObject,
    _ key: String,
    defaultValue: String,
    allowedValues: Set<String>
  ) -> String {
    let value = (input[key]?.stringValue ?? defaultValue).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allowedValues.contains(value) ? value : defaultValue
  }

  private func int(_ input: AgentMcpJSONObject, _ key: String, defaultValue: Int, minimum: Int, maximum: Int) -> Int {
    let value = Int(input[key]?.intValue ?? Int64(defaultValue))
    return max(minimum, min(value, maximum))
  }
}
