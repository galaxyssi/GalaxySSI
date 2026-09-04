import Foundation

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
  var implementationId: String = "galaxyssi.ios.web_intelligence_unconfigured"
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
  static let search = "galaxyssi.web.intelligence.search"
  static let fetch = "galaxyssi.web.intelligence.fetch"
  static let crawl = "galaxyssi.web.intelligence.crawl"
  static let extract = "galaxyssi.web.intelligence.extract"
  static let cache = "galaxyssi.web.intelligence.cache"
  static let findSimilar = "galaxyssi.web.intelligence.find_similar"
  static let research = "galaxyssi.web.intelligence.research"
  static let agent = "galaxyssi.web.intelligence.agent"
  static let diff = "galaxyssi.web.intelligence.diff"
  static let watch = "galaxyssi.web.intelligence.watch"

  static let protocolId = "galaxyssi.web-intelligence.v1"
  static let executorId = "galaxyssi.ios_web_intelligence"
  static let networkPermission = "galaxyssi.scope.public_https_network"
  static let cachePermission = "galaxyssi.scope.encrypted_web_intelligence_cache"
  static let publicWebConsent = "galaxyssi.consent.public_web"
  static let cacheConsent = "galaxyssi.consent.web_intelligence_cache"

  static let maxFetchBytes = AgentIOSWebMediaNativeToolCatalog.maxFetchBytes
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
    case .research: return "Execute a model-authored research plan"
    case .agent: return "Investigate model-authored research queries"
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
      return "Inspects, searches, or clears GalaxySSI's encrypted local web document and search cache."
    case .findSimilar:
      return "Finds related cached documents and can optionally supplement them from public web evidence."
    case .research:
      return "Executes a model-authored multi-query plan and returns cited evidence with per-query coverage."
    case .agent:
      return "Executes a model-authored multi-source investigation and reports unresolved coverage gaps for the next model decision."
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
      timeoutPolicy: progressAwareOperations.contains(operation) ? .progressAware : .fixed,
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

  private static let progressAwareOperations: Set<AgentIOSWebIntelligenceOperation> = [
    .crawl,
    .research,
    .agent,
    .watch
  ]

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
        description: "Limits access to GalaxySSI's encrypted local web evidence cache."
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
        description: "Allows this invocation to inspect or modify GalaxySSI's encrypted web evidence cache."
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
          maxItems: webVerticals.count,
          maxLength: 64,
          enumValues: webVerticals
        ),
        "categories": stringArraySchema(maxItems: 32, maxLength: 64),
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
      return researchSchema()
    case .agent:
      return researchSchema()
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

  private static func researchSchema() -> AgentMcpJSONObject {
    let properties: [String: AgentMcpJSONObject] = [
      "query": stringSchema(minLength: 1, maxLength: 4_096),
      "query_plan": researchQueryPlanSchema(),
      "evidence_limit": integerSchema(minimum: 2, maximum: 24),
      "profile": stringSchema(enumValues: ["fast", "balanced", "deep"]),
      "engine_fanout": integerSchema(minimum: 1, maximum: 32),
      "engines": stringArraySchema(maxItems: 32, maxLength: 64),
      "verticals": stringArraySchema(
        maxItems: webVerticals.count,
        maxLength: 64,
        enumValues: webVerticals
      ),
      "categories": stringArraySchema(maxItems: 32, maxLength: 64),
      "use_cache": boolSchema(),
      "timeout_ms": integerSchema(minimum: 2_000, maximum: 60_000),
      "page_read_parallelism": integerSchema(minimum: 1, maximum: 6),
      "per_host_parallelism": integerSchema(minimum: 1, maximum: 2),
      "page_read_timeout_ms": integerSchema(minimum: 2_000, maximum: 60_000),
      "early_complete": boolSchema()
    ]
    return objectSchema(properties, required: ["query"])
  }

  private static func researchQueryPlanSchema() -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(objectSchema([
        "query": stringSchema(
          minLength: 1,
          maxLength: Int64(AgentIOSWebResearchPlanCodec.maximumQueryCharacters)
        ),
        "purpose": stringSchema(
          minLength: 0,
          maxLength: Int64(AgentIOSWebResearchPlanCodec.maximumPurposeCharacters)
        ),
        "verticals": stringArraySchema(
          maxItems: webVerticals.count,
          maxLength: 64,
          enumValues: webVerticals
        ),
        "categories": stringArraySchema(
          maxItems: AgentIOSWebResearchPlanCodec.maximumCategories,
          maxLength: 64
        ),
        "engines": stringArraySchema(
          maxItems: AgentIOSWebResearchPlanCodec.maximumEngines,
          maxLength: 64
        )
      ], required: ["query"])),
      "maxItems": .int(Int64(AgentIOSWebResearchPlanCodec.maximumItems))
    ]
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

  static let webVerticals = [
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
    output = AgentIOSWebEvidencePack.attach(
      to: output,
      generatedAtMillis: output["completed_at_millis"]?.intValue ?? invocation.startedAtEpochMillis
    )
    var metadata = execution.metadata
    metadata["protocol"] = metadata["protocol"] ?? .string(AgentIOSWebIntelligenceNativeToolCatalog.protocolId)
    metadata["implementation"] = metadata["implementation"] ?? .string("galaxyssi_native_ios")
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
