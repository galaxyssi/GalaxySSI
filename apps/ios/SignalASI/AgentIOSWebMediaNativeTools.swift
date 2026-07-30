import CryptoKit
import Foundation

enum AgentIOSWebMediaOperation: String, Codable, CaseIterable, Identifiable {
  case webSearch = "web.search"
  case webOpen = "web.open"
  case browserRender = "browser.render"
  case browserSessionCreate = "browser.session.create"
  case browserSessionNavigate = "browser.session.navigate"
  case browserSessionClose = "browser.session.close"
  case contentExtract = "content.extract"
  case httpRequest = "http.request"
  case fileDownload = "file.download"
  case webHead = "signalasi.web.head"
  case webFetch = "signalasi.web.fetch"
  case webDownload = "signalasi.web.download"
  case ocrRecognizeContent = "signalasi.ocr.content.recognize"

  var id: String { rawValue }
}

protocol AgentIOSWebMediaToolProviding {
  var implementationId: String { get }
  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability
  func invoke(
    operation: AgentIOSWebMediaOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult
}

struct AgentIOSUnavailableWebMediaToolProvider: AgentIOSWebMediaToolProviding {
  var implementationId: String = "signalasi.ios.web_media_unconfigured"

  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability {
    if operation == .contentExtract {
      return .available
    }
    return AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "iOS WebMedia provider is not connected"
    )
  }

  func invoke(
    operation: AgentIOSWebMediaOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "web_media_provider_unavailable",
      message: "iOS WebMedia provider is not connected",
      retryable: true
    )
  }
}

enum AgentIOSWebMediaNativeToolCatalog {
  static let webSearch = "web.search"
  static let webOpen = "web.open"
  static let browserRender = "browser.render"
  static let browserSessionCreate = "browser.session.create"
  static let browserSessionNavigate = "browser.session.navigate"
  static let browserSessionClose = "browser.session.close"
  static let contentExtract = "content.extract"
  static let httpRequest = "http.request"
  static let fileDownload = "file.download"
  static let webHead = "signalasi.web.head"
  static let webFetch = "signalasi.web.fetch"
  static let webDownload = "signalasi.web.download"
  static let ocrRecognizeContent = "signalasi.ocr.content.recognize"

  static let executorId = "signalasi.ios_web_media_tools"
  static let androidWebExecutorId = "signalasi.bounded_https"
  static let androidContentExecutorId = "signalasi.android_content_uri"
  static let androidContentExtractExecutorId = "signalasi.content_extractor"
  static let androidHandleExecutorId = "signalasi.explicit_tool_handles"
  static let publicHttpsNetworkPermission = "signalasi.scope.public_https_network"
  static let contentUriPermission = "signalasi.scope.user_authorized_content_uri"
  static let browserSessionPermission = "signalasi.scope.explicit_browser_session"
  static let localContentPermission = "signalasi.scope.local_content_transform"
  static let publicWebConsent = "signalasi.consent.public_web"
  static let webDownloadConsent = "signalasi.consent.web_download"
  static let contentUriReadConsent = "signalasi.consent.content_uri_read"
  static let contentUriWriteConsent = "signalasi.consent.content_uri_write"
  static let browserSessionConsent = "signalasi.consent.browser_session"
  static let localContentExtractConsent = "signalasi.consent.local_content_extract"

  static let maxFetchBytes: Int64 = 1_048_576
  static let maxDownloadBytes: Int64 = 12 * 1_048_576
  static let maxContentCharacters: Int64 = 240_000
  static let maxUrlCharacters: Int64 = 4_096
  static let maxBrowserHandleCharacters: Int64 = 240
  static let maxOcrSourceBytes: Int64 = 12 * 1_048_576
  static let maxToolTimeoutMillis: Int64 = 15_000

  static let orderedToolIds = [
    webSearch,
    webOpen,
    browserRender,
    browserSessionCreate,
    browserSessionNavigate,
    browserSessionClose,
    contentExtract,
    httpRequest,
    fileDownload,
    webHead,
    webFetch,
    webDownload,
    ocrRecognizeContent
  ]
  static let toolIds: Set<String> = Set(orderedToolIds)
  static let directToolIds: Set<String> = [
    webSearch,
    webOpen,
    browserRender,
    browserSessionCreate,
    browserSessionNavigate,
    browserSessionClose,
    contentExtract,
    httpRequest,
    webHead,
    webFetch
  ]
  static let confirmOnceToolIds: Set<String> = [
    fileDownload,
    webDownload,
    ocrRecognizeContent
  ]

  static func definitions(
    provider: AgentIOSWebMediaToolProviding = AgentIOSUnavailableWebMediaToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    AgentIOSWebMediaOperation.allCases.map { operation in
      definition(provider: provider, operation: operation)
    }
  }

  static func operation(for toolId: String) -> AgentIOSWebMediaOperation? {
    AgentIOSWebMediaOperation.allCases.first { $0.rawValue == toolId }
  }

  static func title(_ operation: AgentIOSWebMediaOperation) -> String {
    switch operation {
    case .webSearch:
      return "Search the public web"
    case .webOpen:
      return "Open and extract public web page"
    case .browserRender:
      return "Render isolated public page content"
    case .browserSessionCreate:
      return "Create isolated browser session"
    case .browserSessionNavigate:
      return "Navigate isolated browser session"
    case .browserSessionClose:
      return "Close isolated browser session"
    case .contentExtract:
      return "Extract readable content"
    case .httpRequest:
      return "Request public HTTPS resource"
    case .fileDownload:
      return "Download file"
    case .webHead:
      return "Inspect public HTTPS resource"
    case .webFetch:
      return "Fetch public HTTPS text"
    case .webDownload:
      return "Download public HTTPS resource"
    case .ocrRecognizeContent:
      return "Recognize selected or captured text"
    }
  }

  private static func definition(
    provider: AgentIOSWebMediaToolProviding,
    operation: AgentIOSWebMediaOperation
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: operation.rawValue,
      version: AgentPhoneNativeToolCatalog.version,
      title: title(operation),
      description: description(operation),
      location: .application,
      inputSchema: inputSchema(operation),
      outputSchema: outputSchema(operation),
      risk: risk(operation),
      capabilities: capabilities(operation),
      requiredPermissions: permissionRequirements(operation),
      requiredConsents: consentRequirements(operation),
      timeoutMillis: maxToolTimeoutMillis,
      idempotency: idempotency(operation),
      availability: availability(provider: provider, operation: operation)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: provenance(operation, provider: provider)
    )
  }

  private static func availability(
    provider: AgentIOSWebMediaToolProviding,
    operation: AgentIOSWebMediaOperation
  ) -> AgentNativeToolAvailability {
    operation == .contentExtract ? .available : provider.availability(operation: operation)
  }

  private static func description(_ operation: AgentIOSWebMediaOperation) -> String {
    switch operation {
    case .webSearch:
      return "Searches public web results through a bounded iOS HTTPS provider without browser cookies."
    case .webOpen, .browserRender:
      return "Fetches one bounded public HTTPS page and extracts readable text without sharing browser cookies or executing page scripts."
    case .browserSessionCreate:
      return "Creates an explicit browser_id scoped to the caller and conversation, with optional bounded public HTTPS content."
    case .browserSessionNavigate:
      return "Navigates an existing explicit browser_id and returns bounded readable public page content."
    case .browserSessionClose:
      return "Closes a caller-scoped explicit browser_id without retaining page content."
    case .contentExtract:
      return "Extracts bounded readable text from supplied HTML or plain text without executing code."
    case .httpRequest:
      return "Performs a bounded GET or HEAD request to a provider-validated public HTTPS endpoint."
    case .fileDownload:
      return "Compatibility alias for downloading a bounded public HTTPS resource to a user-authorized iOS content target."
    case .webHead:
      return "Performs a redirect-bounded HEAD request to a provider-validated public HTTPS resource."
    case .webFetch:
      return "Fetches bounded textual content from a provider-validated public HTTPS resource."
    case .webDownload:
      return "Downloads bounded non-executable bytes to a user-authorized iOS content target."
    case .ocrRecognizeContent:
      return "Runs a bounded OCR implementation on a selected or captured iOS content reference."
    }
  }

  private static func risk(_ operation: AgentIOSWebMediaOperation) -> AgentNativeToolRisk {
    switch operation {
    case .fileDownload, .webDownload:
      return .medium
    case .webSearch, .webOpen, .browserRender, .browserSessionCreate, .browserSessionNavigate,
         .browserSessionClose, .contentExtract, .httpRequest, .webHead, .webFetch, .ocrRecognizeContent:
      return .low
    }
  }

  private static func idempotency(_ operation: AgentIOSWebMediaOperation) -> AgentNativeToolIdempotency {
    switch operation {
    case .fileDownload, .webDownload:
      return .idempotencyKeyRequired
    case .browserSessionCreate, .browserSessionNavigate, .browserSessionClose:
      return .nonIdempotent
    case .webSearch, .webOpen, .browserRender, .contentExtract, .httpRequest, .webHead, .webFetch, .ocrRecognizeContent:
      return .idempotent
    }
  }

  private static func capabilities(_ operation: AgentIOSWebMediaOperation) -> Set<String> {
    switch operation {
    case .contentExtract:
      return ["content.extract", "html.no_script_execution", "result.bounded"]
    case .browserSessionCreate, .browserSessionNavigate:
      return ["network.public_https", "network.dns_pinned", "network.redirect_bounded", "browser.explicit_handle", "cookies.none"]
    case .browserSessionClose:
      return ["browser.explicit_handle", "tool_handle.scoped"]
    case .fileDownload, .webDownload:
      return ["network.public_https", "network.dns_pinned", "network.redirect_bounded", "content_uri.user_authorized", "auto_execute.disabled"]
    case .ocrRecognizeContent:
      return ["ocr.content_uri", "ocr.bounded", "content_uri.user_authorized"]
    case .webSearch, .webOpen, .browserRender, .httpRequest, .webHead, .webFetch:
      return ["network.public_https", "network.dns_pinned", "network.redirect_bounded", "cookies.none"]
    }
  }

  private static func permissionRequirements(_ operation: AgentIOSWebMediaOperation) -> [AgentNativePermissionRequirement] {
    switch operation {
    case .contentExtract:
      return [
        AgentNativePermissionRequirement(
          id: localContentPermission,
          title: "Local content transform",
          description: "Allows local-only text extraction from supplied content.",
          required: false
        )
      ]
    case .browserSessionClose:
      return [browserSessionRequirement()]
    case .fileDownload, .webDownload:
      return [publicHttpsRequirement(), contentUriRequirement()]
    case .ocrRecognizeContent:
      return [contentUriRequirement()]
    case .browserSessionCreate, .browserSessionNavigate:
      return [publicHttpsRequirement(), browserSessionRequirement()]
    case .webSearch, .webOpen, .browserRender, .httpRequest, .webHead, .webFetch:
      return [publicHttpsRequirement()]
    }
  }

  private static func consentRequirements(_ operation: AgentIOSWebMediaOperation) -> [AgentNativeConsentRequirement] {
    switch operation {
    case .contentExtract:
      return [
        consent(
          localContentExtractConsent,
          "Extract supplied content",
          "Allows this invocation to transform the supplied HTML or plain text locally."
        )
      ]
    case .browserSessionClose:
      return [browserSessionConsentRequirement()]
    case .browserSessionCreate, .browserSessionNavigate:
      return [
        publicWebConsentRequirement(),
        browserSessionConsentRequirement()
      ]
    case .fileDownload, .webDownload:
      return [
        publicWebConsentRequirement(),
        consent(webDownloadConsent, "Download public web resource", "Allows this invocation to save a bounded public HTTPS response."),
        consent(contentUriWriteConsent, "Write selected content target", "Allows writing the downloaded bytes to the selected iOS target.")
      ]
    case .ocrRecognizeContent:
      return [
        consent(contentUriReadConsent, "Read selected content", "Allows OCR to read one selected or captured iOS content reference.")
      ]
    case .webSearch, .webOpen, .browserRender, .httpRequest, .webHead, .webFetch:
      return [publicWebConsentRequirement()]
    }
  }

  private static func inputSchema(_ operation: AgentIOSWebMediaOperation) -> AgentMcpJSONObject {
    switch operation {
    case .webSearch:
      return objectSchema([
        "query": stringSchema(minLength: 1, maxLength: 1_024),
        "max_results": integerSchema(minimum: 1, maximum: 10),
        "timeout_ms": timeoutSchema()
      ], required: ["query"])
    case .webOpen, .browserRender, .webFetch:
      return webGetInputSchema(maxBytes: maxFetchBytes)
    case .browserSessionCreate:
      return objectSchema(webInputProperties(maxBytes: maxFetchBytes))
    case .browserSessionNavigate:
      return objectSchema(
        webInputProperties(maxBytes: maxFetchBytes).merging([
          "browser_id": stringSchema(minLength: 16, maxLength: maxBrowserHandleCharacters)
        ]) { current, _ in current },
        required: ["browser_id", "url"]
      )
    case .browserSessionClose:
      return objectSchema([
        "browser_id": stringSchema(minLength: 16, maxLength: maxBrowserHandleCharacters)
      ], required: ["browser_id"])
    case .contentExtract:
      return objectSchema([
        "content": stringSchema(minLength: 1, maxLength: maxFetchBytes)
      ], required: ["content"])
    case .httpRequest:
      return objectSchema(
        webInputProperties(maxBytes: maxFetchBytes).merging([
          "method": stringSchema(enumValues: ["GET", "HEAD"])
        ]) { current, _ in current },
        required: ["url", "method"]
      )
    case .fileDownload, .webDownload:
      return objectSchema(
        webInputProperties(maxBytes: maxDownloadBytes).merging([
          "destination_content_uri": contentUriSchema()
        ]) { current, _ in current },
        required: ["url", "destination_content_uri"]
      )
    case .webHead:
      return objectSchema([
        "url": urlSchema(),
        "timeout_ms": timeoutSchema()
      ], required: ["url"])
    case .ocrRecognizeContent:
      return objectSchema([
        "content_uri": contentUriSchema(),
        "source_kind": stringSchema(enumValues: ["image", "screenshot", "camera", "document"]),
        "script_hint": stringSchema(enumValues: ["auto", "latin", "chinese", "japanese", "korean", "devanagari"]),
        "max_source_bytes": integerSchema(minimum: 1, maximum: maxOcrSourceBytes),
        "timeout_ms": timeoutSchema()
      ], required: ["content_uri", "source_kind"])
    }
  }

  private static func outputSchema(_ operation: AgentIOSWebMediaOperation) -> AgentMcpJSONObject {
    switch operation {
    case .webSearch:
      return objectSchema(
        commonWebOutputProperties().merging([
          "query": stringSchema(minLength: 1, maxLength: 1_024),
          "results": arraySchema(
            itemSchema: objectSchema([
              "title": stringSchema(maxLength: 4_096),
              "url": urlSchema()
            ], required: ["title", "url"]),
            maxItems: 10
          ),
          "result_count": integerSchema(minimum: 0, maximum: 10)
        ]) { current, _ in current }
      )
    case .webOpen, .browserRender:
      return objectSchema(commonWebOutputProperties().merging([
        "text": stringSchema(maxLength: maxContentCharacters),
        "html_sha256": sha256Schema(),
        "render_mode": stringSchema(enumValues: ["bounded_http", "isolated_static_dom"])
      ]) { current, _ in current })
    case .browserSessionCreate:
      return objectSchema(commonWebOutputProperties().merging(browserSessionOutputProperties()) { current, _ in current })
    case .browserSessionNavigate:
      return objectSchema(commonWebOutputProperties().merging(browserSessionOutputProperties()) { current, _ in current })
    case .browserSessionClose:
      return objectSchema([
        "browser_id": stringSchema(minLength: 16, maxLength: maxBrowserHandleCharacters),
        "closed": boolSchema(),
        "expires_at_epoch_ms": integerSchema(minimum: 0)
      ])
    case .contentExtract:
      return objectSchema([
        "text": stringSchema(maxLength: maxContentCharacters),
        "source_chars": integerSchema(minimum: 1, maximum: maxFetchBytes)
      ], required: ["text", "source_chars"])
    case .httpRequest:
      return objectSchema(commonWebOutputProperties().merging([
        "text": stringSchema(maxLength: maxFetchBytes)
      ]) { current, _ in current })
    case .webHead:
      return objectSchema(commonWebOutputProperties())
    case .webFetch:
      return objectSchema(commonWebOutputProperties().merging([
        "text": stringSchema(maxLength: maxFetchBytes),
        "charset": stringSchema(maxLength: 64),
        "size_bytes": integerSchema(minimum: 0, maximum: maxFetchBytes),
        "sha256": sha256Schema()
      ]) { current, _ in current })
    case .fileDownload, .webDownload:
      return objectSchema(commonWebOutputProperties().merging([
        "destination_content_uri": contentUriSchema(),
        "size_bytes": integerSchema(minimum: 0, maximum: maxDownloadBytes),
        "sha256": sha256Schema()
      ]) { current, _ in current })
    case .ocrRecognizeContent:
      return ocrOutputSchema()
    }
  }

  private static func provenance(
    _ operation: AgentIOSWebMediaOperation,
    provider: AgentIOSWebMediaToolProviding
  ) -> [String: String] {
    var metadata = [
      "implementation": provider.implementationId,
      "platform": "ios_phone",
      "cookies": "none",
      "result_policy": "bounded-v1"
    ]
    switch operation {
    case .contentExtract:
      metadata["android_executor_compat"] = androidContentExtractExecutorId
      metadata["script_execution"] = "false"
      metadata["network"] = "not_required"
    case .browserSessionCreate, .browserSessionNavigate:
      metadata["android_executor_compat"] = androidWebExecutorId
      metadata["handle_executor_compat"] = androidHandleExecutorId
      metadata["state_model"] = "explicit_browser_id"
      metadata["javascript"] = "false"
    case .browserSessionClose:
      metadata["android_executor_compat"] = androidHandleExecutorId
      metadata["state_model"] = "explicit_browser_id"
      metadata["persistence"] = "process_lifetime"
      metadata["network"] = "not_required"
    case .fileDownload, .webDownload:
      metadata["android_executor_compat"] = androidContentExecutorId
      metadata["network_policy"] = "public_https_pinned_dns_v1"
      metadata["destination_scope"] = "user_authorized_content_uri"
      metadata["auto_execute"] = "false"
    case .ocrRecognizeContent:
      metadata["android_executor_compat"] = androidContentExecutorId
      metadata["content_scope"] = "user_authorized_content_uri"
      metadata["recognition"] = "provider_bounded_ocr"
    case .webSearch, .webOpen, .browserRender, .httpRequest, .webHead, .webFetch:
      metadata["android_executor_compat"] = androidWebExecutorId
      metadata["network_policy"] = "public_https_pinned_dns_v1"
      if operation == .webOpen || operation == .browserRender {
        metadata["javascript"] = "false"
      }
    }
    return metadata
  }

  private static func webGetInputSchema(maxBytes: Int64) -> AgentMcpJSONObject {
    objectSchema(webInputProperties(maxBytes: maxBytes), required: ["url"])
  }

  private static func webInputProperties(maxBytes: Int64) -> [String: AgentMcpJSONObject] {
    [
      "url": urlSchema(),
      "max_bytes": integerSchema(minimum: 1, maximum: maxBytes),
      "timeout_ms": timeoutSchema()
    ]
  }

  private static func commonWebOutputProperties() -> [String: AgentMcpJSONObject] {
    [
      "method": stringSchema(enumValues: ["head", "get"]),
      "status_code": integerSchema(minimum: 100, maximum: 599),
      "content_type": stringSchema(maxLength: 255),
      "content_length_bytes": integerSchema(minimum: -1),
      "requested_at_epoch_ms": integerSchema(minimum: 0),
      "retrieved_at_epoch_ms": integerSchema(minimum: 0),
      "response_headers": objectSchema([
        "content-type": stringSchema(maxLength: 2_048),
        "etag": stringSchema(maxLength: 2_048),
        "last-modified": stringSchema(maxLength: 2_048),
        "cache-control": stringSchema(maxLength: 2_048),
        "content-disposition": stringSchema(maxLength: 2_048)
      ]),
      "source": objectSchema([
        "requested_url": urlSchema(),
        "final_url": urlSchema(),
        "redirect_chain": arraySchema(
          itemSchema: objectSchema([
            "status_code": integerSchema(minimum: 300, maximum: 399),
            "from_url": urlSchema(),
            "to_url": urlSchema()
          ], required: ["status_code", "from_url", "to_url"]),
          maxItems: 4
        ),
        "dns_resolution": arraySchema(
          itemSchema: objectSchema([
            "host": stringSchema(maxLength: 253),
            "addresses": arraySchema(itemSchema: stringSchema(maxLength: 64), maxItems: 16)
          ], required: ["host", "addresses"]),
          maxItems: 5
        )
      ], required: ["requested_url", "final_url", "redirect_chain", "dns_resolution"])
    ]
  }

  private static func browserSessionOutputProperties() -> [String: AgentMcpJSONObject] {
    [
      "browser_id": stringSchema(minLength: 16, maxLength: maxBrowserHandleCharacters),
      "current_url": urlSchema(),
      "history_count": integerSchema(minimum: 0, maximum: 256),
      "expires_at_epoch_ms": integerSchema(minimum: 0),
      "text": stringSchema(maxLength: maxContentCharacters),
      "html_sha256": sha256Schema()
    ]
  }

  private static func ocrOutputSchema() -> AgentMcpJSONObject {
    objectSchema([
      "text": stringSchema(maxLength: maxContentCharacters),
      "lines": arraySchema(
        itemSchema: objectSchema([
          "text": stringSchema(maxLength: 4_096),
          "left": integerSchema(minimum: 0),
          "top": integerSchema(minimum: 0),
          "right": integerSchema(minimum: 0),
          "bottom": integerSchema(minimum: 0),
          "language_tag": stringSchema(maxLength: 64),
          "block_index": integerSchema(minimum: 0),
          "line_index": integerSchema(minimum: 0)
        ], required: ["text", "left", "top", "right", "bottom", "language_tag", "block_index", "line_index"]),
        maxItems: 500
      ),
      "blocks": arraySchema(
        itemSchema: objectSchema([
          "text": stringSchema(maxLength: 16_384),
          "left": integerSchema(minimum: 0),
          "top": integerSchema(minimum: 0),
          "right": integerSchema(minimum: 0),
          "bottom": integerSchema(minimum: 0),
          "line_count": integerSchema(minimum: 1)
        ], required: ["text", "left", "top", "right", "bottom", "line_count"]),
        maxItems: 200
      ),
      "content_uri": contentUriSchema(),
      "source_kind": stringSchema(enumValues: ["image", "screenshot", "camera", "document"]),
      "script_hint": stringSchema(enumValues: ["auto", "latin", "chinese", "japanese", "korean", "devanagari"]),
      "observed_at_epoch_ms": integerSchema(minimum: 0)
    ], required: ["text", "lines", "blocks"])
  }

  private static func publicHttpsRequirement() -> AgentNativePermissionRequirement {
    AgentNativePermissionRequirement(
      id: publicHttpsNetworkPermission,
      title: "Public HTTPS access",
      description: "Limits iOS WebMedia requests to bounded public HTTPS resources."
    )
  }

  private static func contentUriRequirement() -> AgentNativePermissionRequirement {
    AgentNativePermissionRequirement(
      id: contentUriPermission,
      title: "User-authorized content target",
      description: "Limits content access to selected content or security-scoped file references."
    )
  }

  private static func browserSessionRequirement() -> AgentNativePermissionRequirement {
    AgentNativePermissionRequirement(
      id: browserSessionPermission,
      title: "Explicit browser session",
      description: "Limits browser state to caller-scoped explicit browser_id handles."
    )
  }

  private static func publicWebConsentRequirement() -> AgentNativeConsentRequirement {
    consent(publicWebConsent, "Public web access", "Allows this invocation to retrieve untrusted public HTTPS content.")
  }

  private static func browserSessionConsentRequirement() -> AgentNativeConsentRequirement {
    consent(browserSessionConsent, "Browser session control", "Allows this invocation to create or update a scoped browser session.")
  }

  private static func consent(_ id: String, _ title: String, _ description: String) -> AgentNativeConsentRequirement {
    AgentNativeConsentRequirement(id: id, title: title, description: description)
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

  private static func urlSchema() -> AgentMcpJSONObject {
    stringSchema(minLength: 8, maxLength: maxUrlCharacters)
  }

  private static func contentUriSchema() -> AgentMcpJSONObject {
    stringSchema(minLength: 1, maxLength: 4_096)
  }

  private static func timeoutSchema() -> AgentMcpJSONObject {
    integerSchema(minimum: 1_000, maximum: maxToolTimeoutMillis)
  }

  private static func sha256Schema() -> AgentMcpJSONObject {
    stringSchema(minLength: 64, maxLength: 64, pattern: "^[a-f0-9]{64}$")
  }
}

struct AgentIOSWebMediaNativeToolExecutor {
  var provider: AgentIOSWebMediaToolProviding

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
    guard let operation = AgentIOSWebMediaNativeToolCatalog.operation(for: invocation.descriptor.id) else {
      return AgentNativeToolExecutionResult.failure(
        code: "web_media_unknown_tool",
        message: "Unknown WebMedia native tool."
      )
    }
    if operation == .contentExtract {
      return extractContent(invocation)
    }
    let requestedURL = string(invocation.input, "url", limit: Int(AgentIOSWebMediaNativeToolCatalog.maxUrlCharacters))
    if requiresHTTPS(operation), (!requestedURL.isEmpty || operation != .browserSessionCreate), !isHTTPSURL(requestedURL) {
      return failure("invalid_url", "WebMedia tools only accept public HTTPS URLs")
    }
    if requiresDestination(operation),
       !isAuthorizedContentReference(string(invocation.input, "destination_content_uri", limit: 4_096)) {
      return failure("invalid_destination_content_uri", "Downloads require a selected content:// or file:// destination")
    }
    if operation == .ocrRecognizeContent,
       !isAuthorizedContentReference(string(invocation.input, "content_uri", limit: 4_096)) {
      return failure("invalid_content_uri", "OCR requires a selected content:// or file:// source")
    }
    try invocation.reportProgress(
      stage: "web_media",
      message: AgentIOSWebMediaNativeToolCatalog.title(operation),
      percent: 10
    )
    let execution = provider.invoke(operation: operation, input: normalizedInput(invocation.input, operation: operation), invocation: invocation)
    guard execution.isSuccess else { return execution }
    var output = execution.output
    output["operation"] = output["operation"] ?? .string(operation.rawValue)
    var metadata = execution.metadata
    metadata["implementation"] = metadata["implementation"] ?? .string(provider.implementationId)
    metadata["platform"] = metadata["platform"] ?? .string("ios_phone")
    metadata["bounded"] = metadata["bounded"] ?? .bool(true)
    if usesPublicHTTPS(operation) {
      metadata["network_policy"] = metadata["network_policy"] ?? .string("public_https_pinned_dns_v1")
      metadata["cookies"] = metadata["cookies"] ?? .string("none")
    }
    if operation == .browserRender || operation == .webOpen {
      metadata["javascript"] = metadata["javascript"] ?? .bool(false)
    }
    if requiresDestination(operation) {
      metadata["auto_execute"] = metadata["auto_execute"] ?? .bool(false)
    }
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "\(AgentIOSWebMediaNativeToolCatalog.title(operation)) completed" : execution.message,
      metadata: metadata
    )
  }

  private func extractContent(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let source = string(invocation.input, "content", limit: Int(AgentIOSWebMediaNativeToolCatalog.maxFetchBytes))
    let text = readableText(source)
    return AgentNativeToolExecutionResult.success(
      output: [
        "text": .string(String(text.prefix(Int(AgentIOSWebMediaNativeToolCatalog.maxContentCharacters)))),
        "source_chars": .int(Int64(source.count))
      ],
      message: "Readable content extracted",
      metadata: [
        "implementation": .string("signalasi.ios.content_extractor"),
        "platform": .string("ios_phone"),
        "script_execution": .bool(false),
        "network": .string("not_required")
      ]
    )
  }

  private func normalizedInput(
    _ input: AgentMcpJSONObject,
    operation: AgentIOSWebMediaOperation
  ) -> AgentMcpJSONObject {
    var output = input
    if operation == .httpRequest,
       let method = input["method"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
      output["method"] = .string(method)
    }
    if operation == .ocrRecognizeContent,
       output["script_hint"] == nil {
      output["script_hint"] = .string("auto")
    }
    return output
  }

  private func requiresHTTPS(_ operation: AgentIOSWebMediaOperation) -> Bool {
    switch operation {
    case .contentExtract, .browserSessionClose, .ocrRecognizeContent:
      return false
    case .webSearch, .webOpen, .browserRender, .browserSessionCreate, .browserSessionNavigate,
         .httpRequest, .fileDownload, .webHead, .webFetch, .webDownload:
      return operation != .webSearch
    }
  }

  private func usesPublicHTTPS(_ operation: AgentIOSWebMediaOperation) -> Bool {
    switch operation {
    case .contentExtract, .browserSessionClose, .ocrRecognizeContent:
      return false
    case .webSearch, .webOpen, .browserRender, .browserSessionCreate, .browserSessionNavigate,
         .httpRequest, .fileDownload, .webHead, .webFetch, .webDownload:
      return true
    }
  }

  private func requiresDestination(_ operation: AgentIOSWebMediaOperation) -> Bool {
    operation == .fileDownload || operation == .webDownload
  }

  private func isHTTPSURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value),
          components.scheme?.lowercased() == "https",
          let host = components.host,
          !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    return true
  }

  private func isAuthorizedContentReference(_ value: String) -> Bool {
    value.hasPrefix("content://") || value.hasPrefix("file://")
  }

  private func readableText(_ source: String) -> String {
    source
      .replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>|<style[^>]*>.*?</style>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</li>|</h[1-6]>", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ", options: [.caseInsensitive])
      .replacingOccurrences(of: "&amp;", with: "&", options: [.caseInsensitive])
      .replacingOccurrences(of: "&lt;", with: "<", options: [.caseInsensitive])
      .replacingOccurrences(of: "&gt;", with: ">", options: [.caseInsensitive])
      .replacingOccurrences(of: "&quot;", with: "\"", options: [.caseInsensitive])
      .replacingOccurrences(of: "&#39;", with: "'", options: [.caseInsensitive])
      .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func string(_ input: AgentMcpJSONObject, _ key: String, limit: Int) -> String {
    String((input[key]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }

  private func failure(_ code: String, _ message: String) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(code: code, message: message, retryable: false)
  }
}

enum AgentIOSWebIntelligenceOperation: String, Codable, CaseIterable, Identifiable {
  case search
  case fetch
  case crawl
  case extract
  case cache
  case findSimilar = "find_similar"
  case research
  case agent
  case diff
  case watch

  var id: String { rawValue }
}

protocol AgentIOSWebIntelligenceToolProviding {
  var implementationId: String { get }
  var engineCatalogSize: Int { get }
  var rankerId: String { get }
  func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability
  func invoke(
    operation: AgentIOSWebIntelligenceOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult
}

struct AgentIOSUnavailableWebIntelligenceToolProvider: AgentIOSWebIntelligenceToolProviding {
  var implementationId: String = "signalasi.ios.web_intelligence_unconfigured"
  var engineCatalogSize: Int = 0
  var rankerId: String = "unavailable"

  func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "iOS web intelligence provider is not connected"
    )
  }

  func invoke(
    operation: AgentIOSWebIntelligenceOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "web_intelligence_provider_unavailable",
      message: "iOS web intelligence provider is not connected",
      retryable: true
    )
  }
}

enum AgentIOSWebIntelligenceNativeToolCatalog {
  static let search = "signalasi.web.intelligence.search"
  static let fetch = "signalasi.web.intelligence.fetch"
  static let crawl = "signalasi.web.intelligence.crawl"
  static let extract = "signalasi.web.intelligence.extract"
  static let cache = "signalasi.web.intelligence.cache"
  static let findSimilar = "signalasi.web.intelligence.find_similar"
  static let research = "signalasi.web.intelligence.research"
  static let agent = "signalasi.web.intelligence.agent"
  static let diff = "signalasi.web.intelligence.diff"
  static let watch = "signalasi.web.intelligence.watch"

  static let protocolId = "signalasi.web-intelligence.v1"
  static let executorId = "signalasi.ios_web_intelligence"
  static let networkPermission = "signalasi.scope.public_https_network"
  static let cachePermission = "signalasi.scope.encrypted_web_intelligence_cache"
  static let publicWebConsent = "signalasi.consent.public_web"
  static let cacheConsent = "signalasi.consent.web_intelligence_cache"

  static let maxFetchBytes: Int64 = 1_048_576
  static let maxContentCharacters: Int64 = 240_000
  static let maxCacheTtlMillis: Int64 = 30 * 24 * 60 * 60 * 1_000

  static let toolIds: Set<String> = [
    search,
    fetch,
    crawl,
    extract,
    cache,
    findSimilar,
    research,
    agent,
    diff,
    watch
  ]

  static func definitions(
    provider: AgentIOSWebIntelligenceToolProviding = AgentIOSUnavailableWebIntelligenceToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    AgentIOSWebIntelligenceOperation.allCases.map { operation in
      definition(
        provider: provider,
        operation: operation,
        id: toolId(operation),
        title: title(operation),
        description: description(operation),
        inputSchema: inputSchema(operation),
        timeoutMillis: timeoutMillis(operation),
        networkRequired: networkRequired(operation)
      )
    }
  }

  static func operation(for toolId: String) -> AgentIOSWebIntelligenceOperation? {
    AgentIOSWebIntelligenceOperation.allCases.first {
      AgentIOSWebIntelligenceNativeToolCatalog.toolId($0) == toolId
    }
  }

  static func toolId(_ operation: AgentIOSWebIntelligenceOperation) -> String {
    switch operation {
    case .search: return search
    case .fetch: return fetch
    case .crawl: return crawl
    case .extract: return extract
    case .cache: return cache
    case .findSimilar: return findSimilar
    case .research: return research
    case .agent: return agent
    case .diff: return diff
    case .watch: return watch
    }
  }

  static func title(_ operation: AgentIOSWebIntelligenceOperation) -> String {
    switch operation {
    case .search: return "Search across independent web sources"
    case .fetch: return "Fetch and cache readable public content"
    case .crawl: return "Crawl a bounded public site"
    case .extract: return "Extract structured readable content"
    case .cache: return "Manage encrypted web intelligence cache"
    case .findSimilar: return "Find semantically similar evidence"
    case .research: return "Build a cited research evidence pack"
    case .agent: return "Run autonomous multi-source web investigation"
    case .diff: return "Compare a public page with its prior state"
    case .watch: return "Create and check public page watches"
    }
  }

  private static func description(_ operation: AgentIOSWebIntelligenceOperation) -> String {
    switch operation {
    case .search:
      return "Queries public web sources through an iOS provider and returns locally reranked evidence with source receipts."
    case .fetch:
      return "Fetches one public HTTPS resource, extracts readable content, and stores an encrypted local copy with provenance."
    case .crawl:
      return "Traverses a bounded set of public HTTPS pages with depth, origin, pattern, cancellation, and deadline controls."
    case .extract:
      return "Extracts readable text, headings, links, language, and requested fields from a public URL or supplied content."
    case .cache:
      return "Inspects, searches, or clears SignalASI's encrypted local web document and search cache."
    case .findSimilar:
      return "Finds related cached documents and can optionally supplement them from public web evidence."
    case .research:
      return "Searches, retrieves, and organizes untrusted web evidence for final synthesis by the selected SignalASI model or Agent."
    case .agent:
      return "Expands a research objective across multiple evidence rounds and returns a cited evidence pack with source receipts."
    case .diff:
      return "Refetches a cached public page and reports content hashes plus a bounded human-readable change summary."
    case .watch:
      return "Creates, lists, removes, and checks encrypted page watches for material public-content changes."
    }
  }

  private static func definition(
    provider: AgentIOSWebIntelligenceToolProviding,
    operation: AgentIOSWebIntelligenceOperation,
    id: String,
    title: String,
    description: String,
    inputSchema: AgentMcpJSONObject,
    timeoutMillis: Int64,
    networkRequired: Bool
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: id,
      version: AgentPhoneNativeToolCatalog.version,
      title: title,
      description: description,
      location: .phone,
      inputSchema: inputSchema,
      outputSchema: outputSchema(),
      risk: .low,
      capabilities: capabilities(networkRequired: networkRequired),
      requiredPermissions: permissionRequirements(networkRequired: networkRequired),
      requiredConsents: consentRequirements(networkRequired: networkRequired),
      timeoutMillis: timeoutMillis,
      idempotency: .idempotent,
      availability: provider.availability(operation: operation)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "implementation": provider.implementationId,
        "platform": "ios_phone",
        "protocol": protocolId,
        "engine_catalog_size": "\(max(0, provider.engineCatalogSize))",
        "ranker": provider.rankerId,
        "cache": "ios_file_protected_encrypted",
        "cookies": "none"
      ]
    )
  }

  private static func capabilities(networkRequired: Bool) -> Set<String> {
    var result: Set<String> = [
      "web_intelligence.native",
      "cache.encrypted",
      "source.receipts"
    ]
    if networkRequired {
      result.formUnion([
        "network.public_https",
        "network.dns_pinned",
        "network.redirect_bounded"
      ])
    } else {
      result.insert("offline.available")
    }
    return result
  }

  private static func permissionRequirements(networkRequired: Bool) -> [AgentNativePermissionRequirement] {
    if networkRequired {
      return [
        AgentNativePermissionRequirement(
          id: networkPermission,
          title: "Public HTTPS access",
          description: "Limits iOS web intelligence to bounded public HTTPS network requests."
        )
      ]
    }
    return [
      AgentNativePermissionRequirement(
        id: cachePermission,
        title: "Encrypted web intelligence cache",
        description: "Limits access to SignalASI's encrypted local web evidence cache."
      )
    ]
  }

  private static func consentRequirements(networkRequired: Bool) -> [AgentNativeConsentRequirement] {
    if networkRequired {
      return [
        AgentNativeConsentRequirement(
          id: publicWebConsent,
          title: "Public web access",
          description: "Allows this invocation to retrieve untrusted public web evidence."
        )
      ]
    }
    return [
      AgentNativeConsentRequirement(
        id: cacheConsent,
        title: "Web intelligence cache access",
        description: "Allows this invocation to inspect or modify SignalASI's encrypted web evidence cache."
      )
    ]
  }

  private static func networkRequired(_ operation: AgentIOSWebIntelligenceOperation) -> Bool {
    switch operation {
    case .extract, .cache, .findSimilar, .watch:
      return false
    case .search, .fetch, .crawl, .research, .agent, .diff:
      return true
    }
  }

  private static func timeoutMillis(_ operation: AgentIOSWebIntelligenceOperation) -> Int64 {
    switch operation {
    case .search, .cache, .watch:
      return 60_000
    case .fetch, .extract, .findSimilar, .diff:
      return 120_000
    case .research:
      return 5 * 60_000
    case .crawl, .agent:
      return 10 * 60_000
    }
  }

  private static func inputSchema(_ operation: AgentIOSWebIntelligenceOperation) -> AgentMcpJSONObject {
    switch operation {
    case .search:
      return objectSchema([
        "query": stringSchema(minLength: 1, maxLength: 4_096),
        "limit": integerSchema(minimum: 1, maximum: 100),
        "profile": stringSchema(enumValues: ["fast", "balanced", "deep"]),
        "engine_fanout": integerSchema(minimum: 1, maximum: 32),
        "engines": stringArraySchema(maxItems: 32, maxLength: 64),
        "verticals": stringArraySchema(
          maxItems: 10,
          maxLength: 64,
          enumValues: webVerticals
        ),
        "timeout_ms": integerSchema(minimum: 1_000, maximum: 60_000),
        "use_cache": boolSchema()
      ], required: ["query"])
    case .fetch, .diff:
      return objectSchema([
        "url": stringSchema(minLength: 8, maxLength: 4_096),
        "force": boolSchema(),
        "max_bytes": integerSchema(minimum: 1_024, maximum: maxFetchBytes),
        "timeout_ms": integerSchema(minimum: 1_000, maximum: 120_000),
        "cache_ttl_ms": integerSchema(minimum: 60_000, maximum: maxCacheTtlMillis)
      ], required: ["url"])
    case .crawl:
      return objectSchema([
        "url": stringSchema(minLength: 8, maxLength: 4_096),
        "max_pages": integerSchema(minimum: 1, maximum: 100),
        "max_depth": integerSchema(minimum: 0, maximum: 5),
        "same_origin": boolSchema(),
        "include_pattern": stringSchema(minLength: 0, maxLength: 512),
        "exclude_pattern": stringSchema(minLength: 0, maxLength: 512),
        "timeout_ms": integerSchema(minimum: 1_000, maximum: 600_000)
      ], required: ["url"])
    case .extract:
      return objectSchema([
        "url": stringSchema(minLength: 0, maxLength: 4_096),
        "content": stringSchema(minLength: 0, maxLength: maxContentCharacters),
        "source_url": stringSchema(minLength: 0, maxLength: 4_096),
        "title": stringSchema(minLength: 0, maxLength: 2_048),
        "fields": stringArraySchema(maxItems: 100, maxLength: 128),
        "force": boolSchema(),
        "timeout_ms": integerSchema(minimum: 1_000, maximum: 120_000)
      ])
    case .cache:
      return objectSchema([
        "action": stringSchema(enumValues: ["status", "query", "get", "clear", "clear_expired", "source_health", "reset_source_health"]),
        "query": stringSchema(minLength: 0, maxLength: 4_096),
        "url": stringSchema(minLength: 0, maxLength: 4_096),
        "limit": integerSchema(minimum: 1, maximum: 100),
        "engines": stringArraySchema(maxItems: 32, maxLength: 64)
      ])
    case .findSimilar:
      return objectSchema([
        "query": stringSchema(minLength: 0, maxLength: 4_096),
        "url": stringSchema(minLength: 0, maxLength: 4_096),
        "limit": integerSchema(minimum: 1, maximum: 100),
        "search_web": boolSchema(),
        "timeout_ms": integerSchema(minimum: 1_000, maximum: 120_000)
      ])
    case .research:
      return researchSchema(autonomous: false)
    case .agent:
      return researchSchema(autonomous: true)
    case .watch:
      return objectSchema([
        "action": stringSchema(enumValues: ["create", "list", "remove", "check", "check_due"]),
        "watch_id": stringSchema(minLength: 0, maxLength: 96, pattern: "[A-Za-z0-9][A-Za-z0-9._-]{0,95}"),
        "url": stringSchema(minLength: 0, maxLength: 4_096),
        "interval_minutes": integerSchema(minimum: 15, maximum: 10_080),
        "enabled": boolSchema(),
        "limit": integerSchema(minimum: 1, maximum: 100),
        "timeout_ms": integerSchema(minimum: 1_000, maximum: 60_000)
      ])
    }
  }

  private static func researchSchema(autonomous: Bool) -> AgentMcpJSONObject {
    var properties: [String: AgentMcpJSONObject] = [
      "query": stringSchema(minLength: 1, maxLength: 4_096),
      "evidence_limit": integerSchema(minimum: 2, maximum: 24),
      "engine_fanout": integerSchema(minimum: 1, maximum: 32),
      "timeout_ms": integerSchema(minimum: 2_000, maximum: 60_000)
    ]
    if autonomous {
      properties["max_rounds"] = integerSchema(minimum: 1, maximum: 4)
    }
    return objectSchema(properties, required: ["query"])
  }

  private static func outputSchema() -> AgentMcpJSONObject {
    objectSchema([
      "protocol": stringSchema(enumValues: [protocolId]),
      "operation": stringSchema(enumValues: AgentIOSWebIntelligenceOperation.allCases.map(\.rawValue)),
      "status": stringSchema(enumValues: ["completed", "partial", "failed"]),
      "request_id": stringSchema(minLength: 0, maxLength: 128),
      "started_at_millis": integerSchema(minimum: 0),
      "completed_at_millis": integerSchema(minimum: 0)
    ], required: ["protocol", "operation", "status"])
  }

  private static let webVerticals = [
    "general",
    "regional",
    "news",
    "knowledge",
    "publishing",
    "code",
    "docs",
    "packages",
    "qa",
    "community",
    "social",
    "academic",
    "research_index",
    "medical",
    "healthcare",
    "biology",
    "technology",
    "agents",
    "hardware",
    "image",
    "video",
    "travel",
    "lifestyle",
    "games",
    "shopping",
    "finance",
    "business",
    "sports",
    "weather",
    "maps_local",
    "food",
    "education",
    "jobs",
    "government",
    "legal",
    "patents",
    "books",
    "audio",
    "entertainment",
    "cybersecurity",
    "ai_models",
    "datasets",
    "automotive",
    "real_estate",
    "events",
    "smart_home",
    "local"
  ]

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

  private static func stringArraySchema(
    maxItems: Int,
    maxLength: Int,
    enumValues: [String] = []
  ) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(stringSchema(minLength: 1, maxLength: Int64(maxLength), enumValues: enumValues)),
      "maxItems": .int(Int64(maxItems))
    ]
  }
}

struct AgentIOSWebIntelligenceNativeToolExecutor {
  var provider: AgentIOSWebIntelligenceToolProviding

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
    guard let operation = AgentIOSWebIntelligenceNativeToolCatalog.operation(for: invocation.descriptor.id) else {
      return AgentNativeToolExecutionResult.failure(
        code: "web_intelligence_unknown_tool",
        message: "Unknown web intelligence native tool."
      )
    }
    try invocation.reportProgress(
      stage: "web_intelligence",
      message: AgentIOSWebIntelligenceNativeToolCatalog.title(operation),
      percent: 10
    )
    let execution = provider.invoke(operation: operation, input: invocation.input, invocation: invocation)
    guard execution.isSuccess else { return execution }

    var output = execution.output
    output["protocol"] = output["protocol"] ?? .string(AgentIOSWebIntelligenceNativeToolCatalog.protocolId)
    output["operation"] = output["operation"] ?? .string(operation.rawValue)
    output["status"] = output["status"] ?? .string("completed")
    var metadata = execution.metadata
    metadata["protocol"] = metadata["protocol"] ?? .string(AgentIOSWebIntelligenceNativeToolCatalog.protocolId)
    metadata["implementation"] = metadata["implementation"] ?? .string("signalasi_native_ios")
    metadata["source_isolation"] = metadata["source_isolation"] ?? .bool(true)
    metadata["evidence_is_untrusted"] = metadata["evidence_is_untrusted"] ?? .bool(true)
    let message = execution.message.isEmpty
      ? "\(AgentIOSWebIntelligenceNativeToolCatalog.title(operation)) completed"
      : execution.message
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: message,
      metadata: metadata
    )
  }
}

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
  var implementationId: String = "signalasi.ios.media_unconfigured"

  func availability(kind: AgentIOSMediaNativeToolKind) -> AgentNativeToolAvailability {
    let reason: String
    switch kind {
    case .metadata, .playback:
      reason = "iOS media provider is not connected"
    case .transcode:
      reason = "iOS signed FFmpeg media runtime is not connected"
    }
    AgentNativeToolAvailability(
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
  static let mediaMetadata = "signalasi.media.metadata"
  static let mediaPlaybackHandoff = AgentPhoneCapabilityNativeCoverage.mediaPlaybackHandoff
  static let mediaFFmpegTranscode = AgentPhoneCapabilityNativeCoverage.mediaFFmpegTranscode

  static let contentUriPermission = "signalasi.scope.user_authorized_content_uri"
  static let workspaceMediaPermission = "signalasi.scope.app_private_workspace"
  static let mediaRuntimePermission = "signalasi.scope.signed_media_runtime"
  static let contentUriReadConsent = "signalasi.consent.content_uri_read"
  static let contentUriWriteConsent = "signalasi.consent.content_uri_write"
  static let mediaPlaybackConsent = "signalasi.consent.media_playback"
  static let mediaTranscodeConsent = "signalasi.consent.media_transcode"
  static let executorId = "signalasi.ios_media_tools"

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
            description: "Limits media conversion to the current SignalASI workspace."
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
    if let invalidPath = firstUnsafePath([request.sourcePath, request.destinationPath]) {
      return failure("unsafe_path", "Media workspace path is unsafe: \(invalidPath)")
    }
    if !request.destinationPath.isEmpty,
       let expected = AgentIOSMediaNativeToolCatalog.targetExtension(request.targetFormat),
       !request.destinationPath.lowercased().hasSuffix(".\(expected)") {
      return failure("extension_mismatch", "Destination extension must match \(request.targetFormat)")
    }
    let execution = provider.transcode(request: request, invocation: invocation)
    guard execution.isSuccess else { return execution }
    var output = execution.output
    output["target_format"] = output["target_format"] ?? .string(request.targetFormat)
    output["mime_type"] = output["mime_type"] ?? .string(AgentIOSMediaNativeToolCatalog.targetMimeType(request.targetFormat) ?? "")
    output["network_enabled"] = output["network_enabled"] ?? .bool(false)
    output["completed_at_epoch_ms"] = output["completed_at_epoch_ms"] ?? .int(max(0, nowMillis()))
    var metadata = execution.metadata
    metadata["media_implementation"] = metadata["media_implementation"] ?? .string(provider.implementationId)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "Media converted in the local iOS FFmpeg runtime" : execution.message,
      metadata: metadata
    )
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

  private func firstUnsafePath(_ paths: [String]) -> String? {
    paths.first { path in
      let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !clean.isEmpty else { return false }
      if clean.hasPrefix("/") || clean.hasPrefix("\\") || clean.contains(":") { return true }
      let parts = clean.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
      return parts.contains { $0 == ".." }
    }
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

enum AgentIOSSelfEvolutionOperation: String, Codable, CaseIterable, Identifiable {
  case status
  case tasksList = "tasks.list"
  case tasksCreate = "tasks.create"
  case candidatePrepare = "candidate.prepare"
  case candidatePatch = "candidate.patch"
  case candidateRollback = "candidate.rollback"

  var id: String { rawValue }
}

protocol AgentIOSSelfEvolutionToolProviding {
  var implementationId: String { get }
  func availability(operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolAvailability
  func invoke(
    operation: AgentIOSSelfEvolutionOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult
}

struct AgentIOSUnavailableSelfEvolutionToolProvider: AgentIOSSelfEvolutionToolProviding {
  var implementationId: String = "signalasi.ios.self_evolution_unconfigured"

  func availability(operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: AgentIOSSelfEvolutionNativeToolCatalog.requiresRuntime(operation)
        ? "iOS self-evolution runtime is not connected"
        : "iOS self-evolution task store is not connected"
    )
  }

  func invoke(
    operation: AgentIOSSelfEvolutionOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "self_evolution_provider_unavailable",
      message: "iOS self-evolution provider is not connected",
      retryable: true
    )
  }
}

enum AgentIOSSelfEvolutionNativeToolCatalog {
  static let status = "signalasi.evolution.status"
  static let tasksList = "signalasi.evolution.tasks.list"
  static let tasksCreate = "signalasi.evolution.tasks.create"
  static let candidatePrepare = "signalasi.evolution.candidate.prepare"
  static let candidatePatch = "signalasi.evolution.candidate.patch"
  static let candidateRollback = "signalasi.evolution.candidate.rollback"

  static let protocolId = "signalasi.evolution-task.v1"
  static let executorId = "signalasi.ios_self_evolution"
  static let storePermission = "signalasi.scope.self_evolution_store"
  static let workspacePermission = "signalasi.scope.self_evolution_workspace"
  static let runtimePermission = "signalasi.scope.signed_self_evolution_runtime"
  static let selfEvolutionConsent = "signalasi.consent.self_evolution"
  static let noAdditionalConsent = "signalasi.consent.none"

  static let maxPatchBytes: Int64 = 160 * 1_024
  static let orderedToolIds = [
    status,
    tasksList,
    tasksCreate,
    candidatePrepare,
    candidatePatch,
    candidateRollback
  ]
  static let toolIds: Set<String> = Set(orderedToolIds)

  static func definitions(
    provider: AgentIOSSelfEvolutionToolProviding = AgentIOSUnavailableSelfEvolutionToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    AgentIOSSelfEvolutionOperation.allCases.map { operation in
      definition(provider: provider, operation: operation)
    }
  }

  static func operation(for toolId: String) -> AgentIOSSelfEvolutionOperation? {
    switch toolId {
    case status:
      return .status
    case tasksList:
      return .tasksList
    case tasksCreate:
      return .tasksCreate
    case candidatePrepare:
      return .candidatePrepare
    case candidatePatch:
      return .candidatePatch
    case candidateRollback:
      return .candidateRollback
    default:
      return nil
    }
  }

  static func toolId(_ operation: AgentIOSSelfEvolutionOperation) -> String {
    switch operation {
    case .status:
      return status
    case .tasksList:
      return tasksList
    case .tasksCreate:
      return tasksCreate
    case .candidatePrepare:
      return candidatePrepare
    case .candidatePatch:
      return candidatePatch
    case .candidateRollback:
      return candidateRollback
    }
  }

  static func title(_ operation: AgentIOSSelfEvolutionOperation) -> String {
    switch operation {
    case .status:
      return "Inspect local self-evolution"
    case .tasksList:
      return "List local evolution tasks"
    case .tasksCreate:
      return "Create a local evolution task"
    case .candidatePrepare:
      return "Prepare an isolated local candidate"
    case .candidatePatch:
      return "Apply and validate a local evolution patch"
    case .candidateRollback:
      return "Discard a local evolution candidate"
    }
  }

  static func requiresRuntime(_ operation: AgentIOSSelfEvolutionOperation) -> Bool {
    switch operation {
    case .candidatePrepare, .candidatePatch:
      return true
    case .status, .tasksList, .tasksCreate, .candidateRollback:
      return false
    }
  }

  private static func definition(
    provider: AgentIOSSelfEvolutionToolProviding,
    operation: AgentIOSSelfEvolutionOperation
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: toolId(operation),
      version: AgentPhoneNativeToolCatalog.version,
      title: title(operation),
      description: description(operation),
      location: .application,
      inputSchema: inputSchema(operation),
      outputSchema: outputSchema(),
      risk: risk(operation),
      capabilities: capabilities(operation),
      requiredPermissions: permissionRequirements(operation),
      requiredConsents: consentRequirements(operation),
      timeoutMillis: timeoutMillis(operation),
      idempotency: operation == .candidatePatch ? .idempotencyKeyRequired : .nonIdempotent,
      availability: provider.availability(operation: operation)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "implementation": provider.implementationId,
        "platform": "ios_phone",
        "protocol": protocolId,
        "compatibility_source": "AgentSelfEvolutionNativeTools",
        "isolation": "ios_disposable_candidate_workspace",
        "production_mutation": "disabled",
        "patch_content_retained": "false"
      ]
    )
  }

  private static func description(_ operation: AgentIOSSelfEvolutionOperation) -> String {
    switch operation {
    case .status:
      return "Reports iOS-local evolution tasks, candidate state, and runtime readiness using Android-compatible output fields."
    case .tasksList:
      return "Lists bounded iOS-local evolution tasks and their immutable quality-gate receipts."
    case .tasksCreate:
      return "Creates a scoped self-improvement task without changing source or the running app."
    case .candidatePrepare:
      return "Prepares a disposable iOS-local candidate workspace and pins its base revision before any patch is applied."
    case .candidatePatch:
      return "Applies one unified diff in the disposable candidate, enforces scope, runs quality gates, and returns a review-only candidate receipt."
    case .candidateRollback:
      return "Deletes only the disposable iOS-local candidate and preserves the running app and stable source."
    }
  }

  private static func risk(_ operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolRisk {
    switch operation {
    case .status, .tasksList, .tasksCreate:
      return .low
    case .candidatePrepare, .candidateRollback:
      return .medium
    case .candidatePatch:
      return .high
    }
  }

  private static func capabilities(_ operation: AgentIOSSelfEvolutionOperation) -> Set<String> {
    var result: Set<String> = [
      "evolution.self",
      "evolution.worktree",
      "evolution.quality_gates",
      "runtime.ios_local",
      "source.review_only"
    ]
    if requiresRuntime(operation) {
      result.formUnion(["runtime.sandboxed", "runtime.signed"])
    }
    if operation == .candidatePatch {
      result.insert("patch.unified_diff")
    }
    return result
  }

  private static func permissionRequirements(_ operation: AgentIOSSelfEvolutionOperation) -> [AgentNativePermissionRequirement] {
    var requirements = [
      AgentNativePermissionRequirement(
        id: storePermission,
        title: "Self-evolution task store",
        description: "Limits self-evolution task state to SignalASI's local encrypted store."
      )
    ]
    if operation == .candidatePrepare || operation == .candidatePatch || operation == .candidateRollback {
      requirements.append(
        AgentNativePermissionRequirement(
          id: workspacePermission,
          title: "Disposable candidate workspace",
          description: "Allows source changes only inside a disposable candidate workspace."
        )
      )
    }
    if requiresRuntime(operation) {
      requirements.append(
        AgentNativePermissionRequirement(
          id: runtimePermission,
          title: "Signed self-evolution runtime",
          description: "Requires a signed local runtime for candidate preparation and quality gates."
        )
      )
    }
    return requirements.sorted { $0.id < $1.id }
  }

  private static func consentRequirements(_ operation: AgentIOSSelfEvolutionOperation) -> [AgentNativeConsentRequirement] {
    switch operation {
    case .candidatePrepare, .candidatePatch, .candidateRollback:
      return [
        AgentNativeConsentRequirement(
          id: selfEvolutionConsent,
          title: "Modify an isolated SignalASI candidate",
          description: "Allows source changes only inside a disposable candidate workspace."
        )
      ]
    case .status, .tasksList, .tasksCreate:
      return [
        AgentNativeConsentRequirement(
          id: noAdditionalConsent,
          title: "No additional consent",
          description: "This self-evolution task-store operation does not modify source code.",
          required: false
        )
      ]
    }
  }

  private static func timeoutMillis(_ operation: AgentIOSSelfEvolutionOperation) -> Int64 {
    switch operation {
    case .candidatePrepare:
      return 15 * 60_000
    case .candidatePatch:
      return 30 * 60_000
    case .status, .tasksList, .tasksCreate, .candidateRollback:
      return 30_000
    }
  }

  private static func inputSchema(_ operation: AgentIOSSelfEvolutionOperation) -> AgentMcpJSONObject {
    switch operation {
    case .status:
      return objectSchema([:])
    case .tasksList:
      return objectSchema([
        "limit": integerSchema(minimum: 1, maximum: 500)
      ])
    case .tasksCreate:
      return objectSchema([
        "problem": stringSchema(minLength: 4, maxLength: 4_000),
        "scope": stringArraySchema(minItems: 1, maxItems: 64, maxLength: 512),
        "acceptance": stringArraySchema(minItems: 1, maxItems: 40, maxLength: 1_000),
        "reproduction_steps": stringArraySchema(minItems: 0, maxItems: 20, maxLength: 1_000),
        "risk_level": stringSchema(enumValues: ["low", "medium", "high", "critical"]),
        "max_attempts": integerSchema(minimum: 1, maximum: 5)
      ], required: ["problem", "scope", "acceptance"])
    case .candidatePrepare, .candidateRollback:
      return taskIdSchema()
    case .candidatePatch:
      return objectSchema([
        "task_id": stringSchema(minLength: 1, maxLength: 96),
        "unified_diff": stringSchema(minLength: 1, maxLength: maxPatchBytes)
      ], required: ["task_id", "unified_diff"])
    }
  }

  private static func outputSchema() -> AgentMcpJSONObject {
    objectSchema([
      "protocol": stringSchema(enumValues: [protocolId]),
      "operation": stringSchema(enumValues: AgentIOSSelfEvolutionOperation.allCases.map(\.rawValue)),
      "execution_target": stringSchema(enumValues: ["ios"]),
      "runtime_ready": boolSchema(),
      "runtime_reason": stringSchema(maxLength: 2_048),
      "task_count": integerSchema(minimum: 0),
      "active_tasks": integerSchema(minimum: 0),
      "status": stringSchema(enumValues: [
        "completed",
        "proposed",
        "preparing",
        "running",
        "validating",
        "waiting_approval",
        "publishing",
        "published",
        "failed",
        "blocked",
        "cancelled",
        "rolled_back",
        "partial"
      ]),
      "task": objectSchema(additionalProperties: true),
      "tasks": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 500),
      "health": objectSchema(additionalProperties: true),
      "candidate_workspace_id": stringSchema(maxLength: 128),
      "candidate_source_root": stringSchema(maxLength: 64),
      "production_mutation": boolSchema(),
      "observed_at_epoch_ms": integerSchema(minimum: 0)
    ], additionalProperties: true)
  }

  private static func taskIdSchema() -> AgentMcpJSONObject {
    objectSchema([
      "task_id": stringSchema(minLength: 1, maxLength: 96)
    ], required: ["task_id"])
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

  private static func stringArraySchema(
    minItems: Int64,
    maxItems: Int64,
    maxLength: Int64
  ) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(stringSchema(minLength: 1, maxLength: maxLength)),
      "minItems": .int(minItems),
      "maxItems": .int(maxItems)
    ]
  }

  private static func arraySchema(itemSchema: AgentMcpJSONObject, maxItems: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(itemSchema),
      "maxItems": .int(maxItems)
    ]
  }
}

struct AgentIOSSelfEvolutionNativeToolExecutor {
  var provider: AgentIOSSelfEvolutionToolProviding
  var nowMillis: () -> Int64

  init(
    provider: AgentIOSSelfEvolutionToolProviding,
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
    guard let operation = AgentIOSSelfEvolutionNativeToolCatalog.operation(for: invocation.descriptor.id) else {
      return AgentNativeToolExecutionResult.failure(
        code: "self_evolution_unknown_tool",
        message: "Unknown self-evolution native tool."
      )
    }
    try invocation.reportProgress(
      stage: "evolution",
      message: AgentIOSSelfEvolutionNativeToolCatalog.title(operation),
      percent: 10
    )
    let execution = provider.invoke(operation: operation, input: invocation.input, invocation: invocation)
    guard execution.isSuccess else { return execution }
    var output = execution.output
    var metadata = execution.metadata
    output.removeValue(forKey: "unified_diff")
    metadata.removeValue(forKey: "unified_diff")
    output["protocol"] = output["protocol"] ?? .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId)
    output["operation"] = output["operation"] ?? .string(operation.rawValue)
    output["execution_target"] = output["execution_target"] ?? .string("ios")
    output["status"] = output["status"] ?? .string(defaultStatus(operation))
    output["production_mutation"] = output["production_mutation"] ?? .bool(false)
    output["observed_at_epoch_ms"] = output["observed_at_epoch_ms"] ?? .int(max(0, nowMillis()))
    metadata["protocol"] = metadata["protocol"] ?? .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId)
    metadata["implementation"] = metadata["implementation"] ?? .string(provider.implementationId)
    metadata["production_mutation"] = metadata["production_mutation"] ?? .bool(false)
    metadata["patch_content_retained"] = metadata["patch_content_retained"] ?? .bool(false)
    metadata["review_only_candidate"] = metadata["review_only_candidate"] ?? .bool(true)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "\(AgentIOSSelfEvolutionNativeToolCatalog.title(operation)) completed" : execution.message,
      metadata: metadata
    )
  }

  private func defaultStatus(_ operation: AgentIOSSelfEvolutionOperation) -> String {
    switch operation {
    case .status, .tasksList:
      return "completed"
    case .tasksCreate:
      return "proposed"
    case .candidatePrepare:
      return "running"
    case .candidatePatch:
      return "waiting_approval"
    case .candidateRollback:
      return "rolled_back"
    }
  }
}
