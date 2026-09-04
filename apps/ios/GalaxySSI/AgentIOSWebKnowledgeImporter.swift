import Foundation

struct AgentIOSWebKnowledgeImportResult {
  var success: Bool
  var message: String
  var metadata: [String: String]

  static func failure(message: String, code: String) -> AgentIOSWebKnowledgeImportResult {
    AgentIOSWebKnowledgeImportResult(
      success: false,
      message: message,
      metadata: [
        "error_code": code,
        "completion_verified": "false"
      ]
    )
  }
}

struct AgentIOSURLSessionWebKnowledgeImporter {
  var provider: AgentIOSWebIntelligenceToolProviding
  var nowMillis: () -> Int64
  var store: (String, String, String, [String]) -> [AgentKnowledgeItem]

  init(
    provider: AgentIOSWebIntelligenceToolProviding = AgentIOSURLSessionWebIntelligenceProvider(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) },
    store: @escaping (String, String, String, [String]) -> [AgentKnowledgeItem]
  ) {
    self.provider = provider
    self.nowMillis = nowMillis
    self.store = store
  }

  func importPage(_ rawURL: String, actionId: String) -> AgentIOSWebKnowledgeImportResult {
    guard let url = normalizedURL(rawURL) else {
      return .failure(message: "Only public HTTPS web pages can be imported on iOS.", code: "invalid_web_url")
    }
    guard let definition = AgentIOSWebIntelligenceNativeToolCatalog
      .definitions(provider: provider)
      .first(where: { $0.descriptor.id == AgentIOSWebIntelligenceNativeToolCatalog.fetch }) else {
      return .failure(message: "The iOS web knowledge provider is unavailable.", code: "web_provider_unavailable")
    }

    let startedAt = max(0, nowMillis())
    let deadline = startedAt + 120_000
    let input: AgentMcpJSONObject = [
      "url": .string(url),
      "max_bytes": .int(AgentIOSWebIntelligenceNativeToolCatalog.maxFetchBytes),
      "timeout_ms": .int(120_000),
      "cache_ttl_ms": .int(AgentIOSWebIntelligenceNativeToolCatalog.maxCacheTtlMillis)
    ]
    let invocation = AgentNativeToolInvocation(
      descriptor: definition.descriptor,
      input: input,
      context: AgentNativeToolInvocationContext(
        invocationId: actionId,
        callerId: "galaxyssi.mobile_agent.plan",
        requestedAtEpochMillis: startedAt,
        deadlineEpochMillis: deadline,
        idempotencyKey: actionId,
        grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent],
        attributes: ["legacy_action_id": actionId]
      ),
      startedAtEpochMillis: startedAt,
      deadlineEpochMillis: deadline,
      nowMillis: nowMillis,
      cancellationRequested: { false },
      progressReporter: { _, _ in }
    )
    let fetched = provider.invoke(operation: .fetch, input: input, invocation: invocation)
    guard fetched.isSuccess else {
      return .failure(
        message: fetched.error?.message ?? fetched.message.ifBlank("Web page import failed."),
        code: fetched.error?.code ?? "web_fetch_failed"
      )
    }

    let content = fetched.output["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !content.isEmpty else {
      return .failure(message: "No readable text was found on the web page.", code: "empty_web_content")
    }
    let sensitiveFlags = AgentKnowledgeImportPolicy.sensitiveFlags(in: content)
    guard sensitiveFlags.isEmpty else {
      return .failure(
        message: "Import blocked because the web page appears to contain secrets.",
        code: "sensitive_web_content"
      )
    }

    let source = fetched.output["url"]?.stringValue?.ifBlank(url) ?? url
    let host = URL(string: source)?.host?.lowercased().ifBlank("web") ?? "web"
    let title = fetched.output["title"]?.stringValue?.ifBlank(host) ?? host
    let items = store(title, content, source, ["import", "web", host])
    guard !items.isEmpty else {
      return .failure(message: "The web page was read but could not be stored in Agent knowledge.", code: "knowledge_store_failed")
    }

    return AgentIOSWebKnowledgeImportResult(
      success: true,
      message: "Imported \(title) as \(items.count) knowledge chunks.",
      metadata: [
        "source": source,
        "title": title,
        "character_count": String(content.count),
        "chunk_count": String(items.count),
        "content_type": fetched.output["content_type"]?.stringValue ?? "",
        "completion_verified": "true"
      ]
    )
  }

  private func normalizedURL(_ value: String) -> String? {
    let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }
    let candidate = raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://")
      ? raw
      : "https://\(raw)"
    guard let components = URLComponents(string: candidate),
          components.scheme?.lowercased() == "https",
          let host = components.host,
          !host.isEmpty,
          components.user == nil,
          components.password == nil else {
      return nil
    }
    return components.string
  }

}
