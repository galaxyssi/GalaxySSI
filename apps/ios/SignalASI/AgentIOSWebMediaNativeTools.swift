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

  static let maxFetchBytes: Int64 = 10 * 1_048_576
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
    provider: AgentIOSWebMediaToolProviding = AgentIOSURLSessionWebMediaToolProvider()
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
      return ["network.public_https", "network.local_hosts_blocked", "network.redirect_bounded", "browser.explicit_handle", "cookies.none"]
    case .browserSessionClose:
      return ["browser.explicit_handle", "tool_handle.scoped"]
    case .fileDownload, .webDownload:
      return ["network.public_https", "network.local_hosts_blocked", "network.redirect_bounded", "content_uri.user_authorized", "auto_execute.disabled"]
    case .ocrRecognizeContent:
      return ["ocr.content_uri", "ocr.bounded", "content_uri.user_authorized"]
    case .webSearch, .webOpen, .browserRender, .httpRequest, .webHead, .webFetch:
      return ["network.public_https", "network.local_hosts_blocked", "network.redirect_bounded", "cookies.none"]
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
        "max_results": integerSchema(minimum: 1, maximum: 24),
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
            maxItems: 24
          ),
          "result_count": integerSchema(minimum: 0, maximum: 24)
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
      if let urlSessionProvider = provider as? AgentIOSURLSessionWebMediaToolProvider {
        metadata["network_policy"] = "public_https_urlsession_revalidated_v1"
        metadata["redirect_policy"] = "manual_revalidate_each_hop"
        metadata["dns_resolution"] = "urlsession_managed"
        metadata["destination_scope"] = "file_url_user_authorized"
        metadata["writer_implementation"] = urlSessionProvider.downloadWriter.implementationId
      } else {
        metadata["network_policy"] = "public_https_pinned_dns_v1"
        metadata["destination_scope"] = "user_authorized_content_uri"
      }
      metadata["auto_execute"] = "false"
    case .ocrRecognizeContent:
      metadata["android_executor_compat"] = androidContentExecutorId
      if let urlSessionProvider = provider as? AgentIOSURLSessionWebMediaToolProvider {
        metadata["implementation"] = urlSessionProvider.ocrProcessor.implementationId
        metadata["content_scope"] = "selected_or_captured_file_url"
        metadata["content_reader_implementation"] = urlSessionProvider.ocrProcessor.contentReaderImplementationId
        metadata["recognition"] = "vision_bounded_ocr"
      } else {
        metadata["content_scope"] = "user_authorized_content_uri"
        metadata["recognition"] = "provider_bounded_ocr"
      }
    case .webSearch, .webOpen, .browserRender, .httpRequest, .webHead, .webFetch:
      metadata["android_executor_compat"] = androidWebExecutorId
      if provider is AgentIOSURLSessionWebMediaToolProvider {
        metadata["network_policy"] = "public_https_urlsession_revalidated_v1"
        metadata["redirect_policy"] = "manual_revalidate_each_hop"
        metadata["dns_resolution"] = "urlsession_managed"
      } else {
        metadata["network_policy"] = "public_https_pinned_dns_v1"
      }
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
