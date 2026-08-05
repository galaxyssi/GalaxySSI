import Foundation

struct AgentIOSURLSessionWebIntelligenceProvider: AgentIOSWebIntelligenceToolProviding {
  var implementationId: String = "signalasi.ios.urlsession_web_intelligence"
  var engineCatalogSize: Int = AgentIOSWebIntelligenceSourceCatalog.sourceCount
  var rankerId: String = "ios-urlsession-evidence-ranker-v1"
  var webMediaProvider: AgentIOSWebMediaToolProviding
  var nowMillis: () -> Int64

  init(
    webMediaProvider: AgentIOSWebMediaToolProviding = AgentIOSURLSessionWebMediaToolProvider(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.webMediaProvider = webMediaProvider
    self.nowMillis = nowMillis
  }

  func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability {
    switch operation {
    case .search:
      return webMediaProvider.availability(operation: .webSearch)
    case .fetch, .diff:
      return webMediaProvider.availability(operation: .webOpen)
    case .crawl:
      return combinedAvailability([.webFetch, .webOpen])
    case .extract:
      return .available
    case .research, .agent:
      return combinedAvailability([.webSearch])
    case .cache, .findSimilar, .watch:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "iOS encrypted web intelligence cache is not connected"
      )
    }
  }

  func invoke(
    operation: AgentIOSWebIntelligenceOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    switch operation {
    case .search:
      return search(input: input, invocation: invocation, operation: operation)
    case .fetch:
      return fetch(input: input, invocation: invocation, operation: operation)
    case .crawl:
      return crawl(input: input, invocation: invocation)
    case .extract:
      return extract(input: input, invocation: invocation)
    case .research, .agent:
      return research(input: input, invocation: invocation, operation: operation)
    case .diff:
      return diff(input: input, invocation: invocation)
    case .cache, .findSimilar, .watch:
      return failure(
        "web_intelligence_cache_unavailable",
        "iOS encrypted web intelligence cache is not connected",
        retryable: false
      )
    }
  }

  private func search(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation,
    operation: AgentIOSWebIntelligenceOperation
  ) -> AgentNativeToolExecutionResult {
    let query = string(input, "query", limit: 4_096)
    guard !query.isEmpty else {
      return failure("invalid_query", "Web intelligence search requires a non-empty query")
    }
    let limit = int(input, "limit", defaultValue: int(input, "evidence_limit", defaultValue: 5, minimum: 1, maximum: 10), minimum: 1, maximum: 10)
    let webResult = webMediaProvider.invoke(
      operation: .webSearch,
      input: [
        "query": .string(query),
        "max_results": .int(Int64(limit)),
        "timeout_ms": .int(webMediaTimeout(input, invocation: invocation))
      ],
      invocation: invocation
    )
    guard webResult.isSuccess else { return webResult }

    let resultObjects = searchResults(webResult.output["results"]?.arrayValue ?? [], limit: limit)
    let receipts = resultObjects.map { sourceReceipt(forSearchResult: $0) }
    var output = baseOutput(operation: operation, invocation: invocation, status: "completed")
    output["request_id"] = .string(requestId(invocation, operation: operation))
    output["query"] = .string(query)
    output["result_count"] = .int(Int64(resultObjects.count))
    output["results"] = .array(resultObjects.map { .object($0.result) })
    output["evidence"] = .array(resultObjects.map { .object($0.evidence) })
    output["source_receipts"] = .array(receipts.map { .object($0) })
    output["engine"] = webResult.metadata["provider"] ?? .string("urlsession")
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: "Web intelligence search evidence collected",
      metadata: metadata(operation: operation, webResult: webResult)
    )
  }

  private func fetch(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation,
    operation: AgentIOSWebIntelligenceOperation
  ) -> AgentNativeToolExecutionResult {
    let url = string(input, "url", limit: 4_096)
    guard !url.isEmpty else {
      return failure("invalid_url", "Web intelligence fetch requires a URL")
    }
    let webResult = webMediaProvider.invoke(
      operation: .webOpen,
      input: webFetchInput(input, url: url, invocation: invocation),
      invocation: invocation
    )
    guard webResult.isSuccess else { return webResult }
    return readableFetchResult(
      operation: operation,
      requestedURL: url,
      webResult: webResult,
      invocation: invocation,
      status: "completed",
      message: "Web intelligence public content fetched"
    )
  }

  private func diff(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    let url = string(input, "url", limit: 4_096)
    guard !url.isEmpty else {
      return failure("invalid_url", "Web intelligence diff requires a URL")
    }
    let webResult = webMediaProvider.invoke(
      operation: .webOpen,
      input: webFetchInput(input, url: url, invocation: invocation),
      invocation: invocation
    )
    guard webResult.isSuccess else { return webResult }
    var result = readableFetchOutput(
      operation: .diff,
      requestedURL: url,
      webResult: webResult,
      invocation: invocation,
      status: "partial"
    )
    result["comparison"] = .string("no_prior_snapshot")
    result["changed"] = .null
    result["current_sha256"] = webResult.output["html_sha256"] ?? .string(AgentMcpJSONCodec.sha256([
      "url": .string(url),
      "text": webResult.output["text"] ?? .string("")
    ]))
    return AgentNativeToolExecutionResult.success(
      output: result,
      message: "Fetched current public page state; no prior iOS cache snapshot is connected",
      metadata: metadata(operation: .diff, webResult: webResult)
    )
  }

  private func extract(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    let content = string(input, "content", limit: Int(AgentIOSWebIntelligenceNativeToolCatalog.maxContentCharacters))
    guard !content.isEmpty else {
      return failure("extract_content_required", "Offline iOS web intelligence extract requires supplied content")
    }
    let sourceURL = string(input, "source_url", limit: 4_096).ifBlank(string(input, "url", limit: 4_096))
    let title = string(input, "title", limit: 2_048).ifBlank(titleFromHTML(content))
    let text = boundedText(readableText(content), maxCharacters: Int(AgentIOSWebIntelligenceNativeToolCatalog.maxContentCharacters))
    guard !text.isEmpty else {
      return failure("extract_empty", "Supplied content did not contain readable text")
    }
    var output = baseOutput(operation: .extract, invocation: invocation, status: "completed")
    output["request_id"] = .string(requestId(invocation, operation: .extract))
    output["source_url"] = .string(sourceURL)
    output["title"] = .string(title)
    output["text"] = .string(text)
    output["text_length"] = .int(Int64(text.count))
    output["content_sha256"] = .string(AgentMcpJSONCodec.sha256(["content": .string(content)]))
    output["source_receipts"] = .array([
      .object([
        "source_url": .string(sourceURL),
        "mode": .string("supplied_content"),
        "network": .bool(false),
        "retrieved_at_epoch_ms": .null
      ])
    ])
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: "Supplied content extracted locally",
      metadata: metadata(operation: .extract)
    )
  }

  private func crawl(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    let rootURL = string(input, "url", limit: 4_096)
    guard !rootURL.isEmpty else {
      return failure("invalid_url", "Web intelligence crawl requires a root URL")
    }
    let maxPages = int(input, "max_pages", defaultValue: 3, minimum: 1, maximum: 10)
    let sameOrigin = input["same_origin"]?.boolValue ?? true
    let includePattern = string(input, "include_pattern", limit: 512)
    let excludePattern = string(input, "exclude_pattern", limit: 512)
    var queue = [rootURL]
    var seen: Set<String> = []
    var pages: [AgentMcpJSONObject] = []
    var receipts: [AgentMcpJSONObject] = []
    var failures: [AgentMcpJSONObject] = []

    while !queue.isEmpty && pages.count < maxPages && !invocation.isCancellationRequested {
      let url = queue.removeFirst()
      let canonical = canonicalURL(url)
      guard !seen.contains(canonical), urlAllowed(url, rootURL: rootURL, sameOrigin: sameOrigin, includePattern: includePattern, excludePattern: excludePattern) else {
        continue
      }
      seen.insert(canonical)
      let webResult = webMediaProvider.invoke(
        operation: .webFetch,
        input: webFetchInput(input, url: url, invocation: invocation),
        invocation: invocation
      )
      guard webResult.isSuccess else {
        failures.append([
          "url": .string(url),
          "code": .string(webResult.error?.code ?? "fetch_failed"),
          "message": .string(webResult.error?.message ?? webResult.message)
        ])
        continue
      }
      let raw = webResult.output["text"]?.stringValue ?? ""
      let finalURL = finalURL(from: webResult.output, fallback: url)
      let text = boundedText(readableText(raw), maxCharacters: 12_000)
      pages.append([
        "url": .string(finalURL),
        "requested_url": .string(url),
        "title": .string(titleFromHTML(raw)),
        "text": .string(text),
        "text_length": .int(Int64(text.count)),
        "content_sha256": webResult.output["sha256"] ?? .string(AgentMcpJSONCodec.sha256(["text": .string(raw)]))
      ])
      receipts.append(sourceReceipt(from: webResult.output, fallbackURL: url))
      links(fromHTML: raw, baseURL: finalURL).forEach { link in
        if queue.count + pages.count < maxPages * 4 {
          queue.append(link)
        }
      }
    }

    guard !pages.isEmpty else {
      return failure("crawl_no_pages", "No readable public pages were fetched during crawl", retryable: true)
    }
    var output = baseOutput(operation: .crawl, invocation: invocation, status: failures.isEmpty ? "completed" : "partial")
    output["request_id"] = .string(requestId(invocation, operation: .crawl))
    output["root_url"] = .string(rootURL)
    output["page_count"] = .int(Int64(pages.count))
    output["pages"] = .array(pages.map { .object($0) })
    output["source_receipts"] = .array(receipts.map { .object($0) })
    output["failures"] = .array(failures.map { .object($0) })
    output["crawl_policy"] = .object([
      "same_origin": .bool(sameOrigin),
      "max_pages": .int(Int64(maxPages))
    ])
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: "Bounded public crawl completed",
      metadata: metadata(operation: .crawl)
    )
  }

  private func research(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation,
    operation: AgentIOSWebIntelligenceOperation
  ) -> AgentNativeToolExecutionResult {
    let query = string(input, "query", limit: 4_096)
    guard !query.isEmpty else {
      return failure("invalid_query", "Web intelligence research requires a non-empty query")
    }
    var searchInput = input
    searchInput["limit"] = .int(Int64(int(input, "evidence_limit", defaultValue: 6, minimum: 2, maximum: 10)))
    let searchResult = search(input: searchInput, invocation: invocation, operation: operation)
    guard searchResult.isSuccess else { return searchResult }
    var output = searchResult.output
    output["research_query"] = .string(query)
    output["rounds_completed"] = .int(1)
    output["autonomous"] = .bool(operation == .agent)
    output["status"] = .string("partial")
    output["synthesis_required"] = .bool(true)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: "Search evidence pack prepared for model synthesis",
      metadata: metadata(operation: operation, webResult: searchResult)
    )
  }

  private func readableFetchResult(
    operation: AgentIOSWebIntelligenceOperation,
    requestedURL: String,
    webResult: AgentNativeToolExecutionResult,
    invocation: AgentNativeToolInvocation,
    status: String,
    message: String
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: readableFetchOutput(
        operation: operation,
        requestedURL: requestedURL,
        webResult: webResult,
        invocation: invocation,
        status: status
      ),
      message: message,
      metadata: metadata(operation: operation, webResult: webResult)
    )
  }

  private func readableFetchOutput(
    operation: AgentIOSWebIntelligenceOperation,
    requestedURL: String,
    webResult: AgentNativeToolExecutionResult,
    invocation: AgentNativeToolInvocation,
    status: String
  ) -> AgentMcpJSONObject {
    let text = boundedText(webResult.output["text"]?.stringValue ?? "", maxCharacters: Int(AgentIOSWebIntelligenceNativeToolCatalog.maxContentCharacters))
    let receipt = sourceReceipt(from: webResult.output, fallbackURL: requestedURL)
    var output = baseOutput(operation: operation, invocation: invocation, status: status)
    output["request_id"] = .string(requestId(invocation, operation: operation))
    output["url"] = .string(finalURL(from: webResult.output, fallback: requestedURL))
    output["requested_url"] = .string(requestedURL)
    output["content_type"] = webResult.output["content_type"] ?? .string("")
    output["content_length_bytes"] = webResult.output["content_length_bytes"] ?? .int(-1)
    output["text"] = .string(text)
    output["text_length"] = .int(Int64(text.count))
    output["content_sha256"] = webResult.output["html_sha256"] ?? webResult.output["sha256"] ?? .string(AgentMcpJSONCodec.sha256(["text": .string(text)]))
    output["source_receipts"] = .array([.object(receipt)])
    output["source"] = .object(receipt)
    return output
  }

  private func searchResults(_ values: [AgentMcpJSONValue], limit: Int) -> [(result: AgentMcpJSONObject, evidence: AgentMcpJSONObject)] {
    values.prefix(limit).enumerated().compactMap { index, value in
      guard let object = value.objectValue else { return nil }
      let title = String((object["title"]?.stringValue ?? "").prefix(512))
      let url = String((object["url"]?.stringValue ?? "").prefix(4_096))
      guard !url.isEmpty else { return nil }
      let rank = index + 1
      let receipt = sourceReceipt(forURL: url, rank: rank)
      let result: AgentMcpJSONObject = [
        "rank": .int(Int64(rank)),
        "title": .string(title),
        "url": .string(url)
      ]
      let evidence: AgentMcpJSONObject = [
        "id": .string(evidenceId(url: url, rank: rank)),
        "rank": .int(Int64(rank)),
        "title": .string(title),
        "url": .string(url),
        "snippet": .string(String((object["snippet"]?.stringValue ?? "").prefix(1_024))),
        "trust": .string("untrusted_public_web"),
        "source_receipt": .object(receipt)
      ]
      return (result, evidence)
    }
  }

  private func baseOutput(
    operation: AgentIOSWebIntelligenceOperation,
    invocation: AgentNativeToolInvocation,
    status: String
  ) -> AgentMcpJSONObject {
    [
      "protocol": .string(AgentIOSWebIntelligenceNativeToolCatalog.protocolId),
      "operation": .string(operation.rawValue),
      "status": .string(status),
      "started_at_millis": .int(max(0, invocation.startedAtEpochMillis)),
      "completed_at_millis": .int(max(0, nowMillis()))
    ]
  }

  private func metadata(
    operation: AgentIOSWebIntelligenceOperation,
    webResult: AgentNativeToolExecutionResult? = nil
  ) -> AgentMcpJSONObject {
    var result: AgentMcpJSONObject = [
      "protocol": .string(AgentIOSWebIntelligenceNativeToolCatalog.protocolId),
      "implementation": .string(implementationId),
      "operation": .string(operation.rawValue),
      "web_media_implementation": .string(webMediaProvider.implementationId),
      "source_isolation": .bool(true),
      "evidence_is_untrusted": .bool(true),
      "cookies": .string("none"),
      "cache": .string("not_connected"),
      "network_policy": .string("public_https_urlsession_revalidated_v1")
    ]
    if let webResult {
      result["web_media_status"] = .string(webResult.isSuccess ? "succeeded" : "failed")
      if let provider = webResult.metadata["provider"] {
        result["search_provider"] = provider
      }
    }
    return result
  }

  private func sourceReceipt(from output: AgentMcpJSONObject, fallbackURL: String) -> AgentMcpJSONObject {
    let source = output["source"]?.objectValue ?? [:]
    return [
      "requested_url": source["requested_url"] ?? .string(fallbackURL),
      "final_url": source["final_url"] ?? .string(fallbackURL),
      "status_code": output["status_code"] ?? .int(0),
      "content_type": output["content_type"] ?? .string(""),
      "content_length_bytes": output["content_length_bytes"] ?? .int(-1),
      "retrieved_at_epoch_ms": output["retrieved_at_epoch_ms"] ?? .int(max(0, nowMillis())),
      "redirect_chain": source["redirect_chain"] ?? .array([]),
      "dns_resolution": source["dns_resolution"] ?? .array([]),
      "network_policy": .string("public_https_urlsession_revalidated_v1")
    ]
  }

  private func sourceReceipt(forSearchResult result: (result: AgentMcpJSONObject, evidence: AgentMcpJSONObject)) -> AgentMcpJSONObject {
    sourceReceipt(forURL: result.result["url"]?.stringValue ?? "", rank: Int(result.result["rank"]?.intValue ?? 0))
  }

  private func sourceReceipt(forURL url: String, rank: Int) -> AgentMcpJSONObject {
    [
      "url": .string(url),
      "rank": .int(Int64(max(0, rank))),
      "retrieved_at_epoch_ms": .null,
      "network_policy": .string("search_result_only"),
      "trust": .string("untrusted_public_web")
    ]
  }

  private func webFetchInput(
    _ input: AgentMcpJSONObject,
    url: String,
    invocation: AgentNativeToolInvocation
  ) -> AgentMcpJSONObject {
    [
      "url": .string(url),
      "max_bytes": .int(maxBytes(input)),
      "timeout_ms": .int(webMediaTimeout(input, invocation: invocation))
    ]
  }

  private func webMediaTimeout(_ input: AgentMcpJSONObject, invocation: AgentNativeToolInvocation) -> Int64 {
    let requested = input["timeout_ms"]?.intValue ?? AgentIOSWebMediaNativeToolCatalog.maxToolTimeoutMillis
    return max(1, min(requested, AgentIOSWebMediaNativeToolCatalog.maxToolTimeoutMillis, invocation.remainingTimeMillis))
  }

  private func maxBytes(_ input: AgentMcpJSONObject) -> Int64 {
    let requested = input["max_bytes"]?.intValue ?? AgentIOSWebIntelligenceNativeToolCatalog.maxFetchBytes
    return max(1_024, min(requested, AgentIOSWebIntelligenceNativeToolCatalog.maxFetchBytes))
  }

  private func combinedAvailability(_ operations: [AgentIOSWebMediaOperation]) -> AgentNativeToolAvailability {
    for operation in operations {
      let status = webMediaProvider.availability(operation: operation)
      if status.status != .available {
        return status
      }
    }
    return .available
  }

  private func requestId(_ invocation: AgentNativeToolInvocation, operation: AgentIOSWebIntelligenceOperation) -> String {
    invocation.context.invocationId.ifBlank("\(operation.rawValue)-\(max(0, invocation.startedAtEpochMillis))")
  }

  private func evidenceId(url: String, rank: Int) -> String {
    "web-evidence-\(AgentMcpJSONCodec.sha256(["url": .string(url), "rank": .int(Int64(rank))]).prefix(16))"
  }

  private func finalURL(from output: AgentMcpJSONObject, fallback: String) -> String {
    output["source"]?.objectValue?["final_url"]?.stringValue?.nonEmpty ?? fallback
  }

  private func canonicalURL(_ value: String) -> String {
    guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      return value.lowercased()
    }
    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    if components.path.isEmpty { components.path = "/" }
    components.fragment = nil
    return components.string ?? value.lowercased()
  }

  private func urlAllowed(
    _ value: String,
    rootURL: String,
    sameOrigin: Bool,
    includePattern: String,
    excludePattern: String
  ) -> Bool {
    guard let url = URL(string: value),
          url.scheme?.lowercased() == "https" else {
      return false
    }
    if sameOrigin,
       let rootHost = URL(string: rootURL)?.host?.lowercased(),
       url.host?.lowercased() != rootHost {
      return false
    }
    if !includePattern.isEmpty, value.range(of: includePattern, options: .regularExpression) == nil {
      return false
    }
    if !excludePattern.isEmpty, value.range(of: excludePattern, options: .regularExpression) != nil {
      return false
    }
    return true
  }

  private func links(fromHTML html: String, baseURL: String) -> [String] {
    guard let regex = try? NSRegularExpression(
      pattern: #"<a[^>]+href=["']([^"']+)["'][^>]*>"#,
      options: [.caseInsensitive]
    ) else {
      return []
    }
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
    var seen: Set<String> = []
    var links: [String] = []
    regex.matches(in: html, options: [], range: nsRange).forEach { match in
      guard match.numberOfRanges >= 2,
            let range = Range(match.range(at: 1), in: html),
            let url = URL(string: decodeHTMLEntities(String(html[range])), relativeTo: URL(string: baseURL))?.absoluteURL,
            url.scheme?.lowercased() == "https" else {
        return
      }
      let value = String(url.absoluteString.prefix(4_096))
      let canonical = canonicalURL(value)
      if !seen.contains(canonical) {
        seen.insert(canonical)
        links.append(value)
      }
    }
    return links
  }

  private func titleFromHTML(_ html: String) -> String {
    guard let regex = try? NSRegularExpression(
      pattern: #"<title[^>]*>(.*?)</title>"#,
      options: [.caseInsensitive, .dotMatchesLineSeparators]
    ) else {
      return ""
    }
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
    guard let match = regex.firstMatch(in: html, options: [], range: nsRange),
          match.numberOfRanges >= 2,
          let range = Range(match.range(at: 1), in: html) else {
      return ""
    }
    return String(readableText(String(html[range])).prefix(512))
  }

  private func readableText(_ source: String) -> String {
    source
      .replacingOccurrences(
        of: #"(?is)<(script|style|noscript)[^>]*>.*?</\1>"#,
        with: " ",
        options: .regularExpression
      )
      .replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
      .replacingOccurrences(of: #"(?is)</(p|div|li|tr|h[1-6])>"#, with: "\n", options: .regularExpression)
      .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
      .components(separatedBy: .newlines)
      .map { decodeHTMLEntities($0).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  private func decodeHTMLEntities(_ source: String) -> String {
    source
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&nbsp;", with: " ")
  }

  private func boundedText(_ text: String, maxCharacters: Int) -> String {
    String(text.prefix(max(0, maxCharacters)))
  }

  private func string(_ input: AgentMcpJSONObject, _ key: String, limit: Int) -> String {
    String((input[key]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }

  private func int(
    _ input: AgentMcpJSONObject,
    _ key: String,
    defaultValue: Int,
    minimum: Int,
    maximum: Int
  ) -> Int {
    let value = Int(input[key]?.intValue ?? Int64(defaultValue))
    return max(minimum, min(value, maximum))
  }

  private func failure(
    _ code: String,
    _ message: String,
    retryable: Bool = false
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(code: code, message: message, retryable: retryable)
  }
}
