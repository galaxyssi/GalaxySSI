import CryptoKit
import Foundation

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
  var implementationId: String = "galaxyssi.ios.notification_unconfigured"

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

struct AgentIOSNotificationBoundaryToolProvider: AgentIOSNotificationToolProviding {
  var implementationId: String = "galaxyssi.ios.notification_boundary"

  func availability() -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS exposes only GalaxySSI-owned notification state; third-party notification history and cross-app replies are unavailable."
    )
  }

  func snapshot(limit: Int) -> AgentIOSNotificationContext {
    AgentIOSNotificationContext(
      hasAccess: true,
      items: [],
      sensitiveFlags: [
        "ios_galaxyssi_owned_notifications_only",
        "ios_third_party_notification_history_unavailable",
        "ios_cross_app_notification_reply_unavailable"
      ],
      totalCount: 0
    )
  }

  func reply(notificationKey: String, text: String) -> AgentIOSNotificationReplyResult {
    AgentIOSNotificationReplyResult(
      success: false,
      message: "iOS does not expose third-party notification reply actions to GalaxySSI.",
      code: "notification_reply_unsupported",
      retryable: false
    )
  }
}

enum AgentIOSNotificationNativeToolCatalog {
  static let notificationsList = AgentPhoneCapabilityNativeCoverage.notificationsList
  static let notificationReply = AgentPhoneCapabilityNativeCoverage.notificationReply

  static let notificationAccessPermission = "galaxyssi.scope.ios_galaxyssi_notifications"
  static let readConsent = "galaxyssi.consent.notification_read"
  static let replyConsent = "galaxyssi.consent.sensitive_action_confirmation"
  static let executorId = "galaxyssi.ios_notification_tools"

  static let defaultLimit = 6
  static let maxNotifications = 12
  static let maxKeyCharacters = 8_192
  static let maxReplyCharacters = 2_000
  static let maxTitleCharacters = 160
  static let maxTextPreviewCharacters = 320

  static let toolIds: Set<String> = [notificationsList, notificationReply]

  static func definitions(
    provider: AgentIOSNotificationToolProviding = AgentIOSOwnedNotificationToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    [
      definition(
        provider: provider,
        id: notificationsList,
        title: "List current notifications",
        description: "Reads bounded GalaxySSI-visible notification fields; sensitive content is redacted before it reaches the Agent.",
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
        description: "Dispatches text through one live GalaxySSI-owned reply action; sensitive and stale targets are rejected.",
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
          title: "GalaxySSI notification access",
          description: "Limits iOS notification tooling to GalaxySSI-owned notification state and reply actions."
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
        "source": "ios_galaxyssi_notifications",
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
    let contextSensitiveFlags: [AgentMcpJSONValue] = context.sensitiveFlags.prefix(6).map {
      .string(String($0.prefix(80)))
    }
    return AgentNativeToolExecutionResult.success(
      output: [
        "notifications": .array(selected.map { .object(notificationValue($0)) }),
        "result_count": .int(Int64(selected.count)),
        "total_observed": .int(Int64(max(context.totalCount, context.items.count))),
        "truncated": .bool(candidates.count > limit || context.totalCount > context.items.count),
        "sensitive_count": .int(Int64(sensitiveCount)),
        "context_sensitive_flags": .array(contextSensitiveFlags),
        "observed_at_epoch_ms": .int(max(0, nowMillis()))
      ],
      message: "Listed \(selected.count) current notifications with sensitive content redacted",
      metadata: [
        "raw_sensitive_content_exposed": .bool(false),
        "notification_limit": .int(Int64(AgentIOSNotificationNativeToolCatalog.maxNotifications)),
        "context_sensitive_flag_count": .int(Int64(context.sensitiveFlags.count)),
        "platform_boundary": .string("ios_galaxyssi_owned_notifications_only")
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
