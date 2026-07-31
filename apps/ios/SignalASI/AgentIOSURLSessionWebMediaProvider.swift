import CryptoKit
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct AgentIOSURLSessionWebRequest: Equatable {
  enum Method: String, Equatable {
    case get = "GET"
    case head = "HEAD"
  }

  var method: Method
  var url: URL
  var timeoutMillis: Int64
  var maxBodyBytes: Int64
  var headers: [String: String]
}

struct AgentIOSURLSessionWebResponse: Equatable {
  var statusCode: Int
  var finalURL: URL
  var headers: [String: String]
  var body: Data
  var retrievedAtEpochMillis: Int64
}

protocol AgentIOSURLSessionWebTransporting {
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse
}

enum AgentIOSURLSessionWebError: Error {
  case invalidURL
  case invalidMethod
  case invalidTimeout
  case invalidLimit
  case localHostBlocked
  case redirectMissingLocation
  case redirectURLTooLong
  case invalidRedirect
  case redirectLoop
  case tooManyRedirects
  case timeout
  case cancelled
  case transportFailed(String)
  case invalidResponse
  case httpStatus(Int)
  case headerTooLarge
  case unsupportedContentType(String)
  case responseTooLarge(Int64, Int64)
}

private final class AgentIOSURLSessionNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

final class AgentIOSDefaultURLSessionWebTransport: AgentIOSURLSessionWebTransporting {
  private let session: URLSession
  private let redirectDelegate: AgentIOSURLSessionNoRedirectDelegate?
  private let nowMillis: () -> Int64

  init(
    session: URLSession? = nil,
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    self.nowMillis = nowMillis
    if let session {
      self.session = session
      redirectDelegate = nil
    } else {
      let delegate = AgentIOSURLSessionNoRedirectDelegate()
      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpCookieAcceptPolicy = .never
      configuration.httpCookieStorage = nil
      configuration.urlCache = nil
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
      redirectDelegate = delegate
    }
  }

  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method.rawValue
    urlRequest.timeoutInterval = TimeInterval(Double(max(1, request.timeoutMillis)) / 1_000.0)
    urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
    urlRequest.setValue("SignalASI-iOS/1.0", forHTTPHeaderField: "User-Agent")
    urlRequest.setValue("text/*, application/json, application/xml, application/xhtml+xml, */*;q=0.1", forHTTPHeaderField: "Accept")
    urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    request.headers.forEach { name, value in
      urlRequest.setValue(value, forHTTPHeaderField: name)
    }

    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var responseData: Data?
    var urlResponse: URLResponse?
    var responseError: Error?
    let task = session.dataTask(with: urlRequest) { data, response, error in
      lock.lock()
      responseData = data
      urlResponse = response
      responseError = error
      lock.unlock()
      semaphore.signal()
    }
    task.resume()
    if semaphore.wait(timeout: .now() + TimeInterval(Double(max(1, request.timeoutMillis)) / 1_000.0)) == .timedOut {
      task.cancel()
      throw AgentIOSURLSessionWebError.timeout
    }

    lock.lock()
    let data = request.method == .head ? Data() : (responseData ?? Data())
    let response = urlResponse
    let error = responseError
    lock.unlock()

    if let urlError = error as? URLError, urlError.code == .cancelled {
      throw AgentIOSURLSessionWebError.cancelled
    }
    if let error {
      throw AgentIOSURLSessionWebError.transportFailed(error.localizedDescription)
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AgentIOSURLSessionWebError.invalidResponse
    }
    if request.method == .get && Int64(data.count) > request.maxBodyBytes {
      throw AgentIOSURLSessionWebError.responseTooLarge(Int64(data.count), request.maxBodyBytes)
    }
    return AgentIOSURLSessionWebResponse(
      statusCode: httpResponse.statusCode,
      finalURL: httpResponse.url ?? request.url,
      headers: Self.normalizedHeaders(httpResponse.allHeaderFields),
      body: data,
      retrievedAtEpochMillis: nowMillis()
    )
  }

  private static func normalizedHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
    var normalized: [String: String] = [:]
    headers.forEach { key, value in
      let name = String(describing: key).lowercased()
      normalized[name] = String(String(describing: value).prefix(2_048))
    }
    return normalized
  }
}

struct AgentIOSURLSessionWebMediaToolProvider: AgentIOSWebMediaToolProviding {
  var implementationId: String
  var transport: AgentIOSURLSessionWebTransporting
  var nowMillis: () -> Int64

  init(
    transport: AgentIOSURLSessionWebTransporting = AgentIOSDefaultURLSessionWebTransport(),
    implementationId: String = "signalasi.ios.urlsession_web_media",
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    self.transport = transport
    self.implementationId = implementationId
    self.nowMillis = nowMillis
  }

  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability {
    switch operation {
    case .contentExtract, .webOpen, .browserRender, .httpRequest, .webHead, .webFetch:
      return .available
    case .webSearch:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "iOS Web search requires a configured search provider."
      )
    case .browserSessionCreate, .browserSessionNavigate, .browserSessionClose:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "iOS isolated browser sessions require a WebKit session provider."
      )
    case .fileDownload, .webDownload:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "iOS Web downloads require a user-authorized content destination provider."
      )
    case .ocrRecognizeContent:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "iOS OCR requires a Vision-backed content provider."
      )
    }
  }

  func invoke(
    operation: AgentIOSWebMediaOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    switch operation {
    case .webHead:
      return executeWeb(operation: operation, input: input, invocation: invocation, method: .head)
    case .webFetch:
      return executeWeb(operation: operation, input: input, invocation: invocation, method: .get)
    case .httpRequest:
      guard let method = requestMethod(input) else {
        return failure(.invalidMethod)
      }
      return executeWeb(operation: operation, input: input, invocation: invocation, method: method)
    case .webOpen, .browserRender:
      return executeWeb(operation: operation, input: input, invocation: invocation, method: .get)
    case .contentExtract:
      return AgentNativeToolExecutionResult.failure(
        code: "unexpected_provider_call",
        message: "content.extract is handled by the iOS WebMedia executor."
      )
    case .webSearch, .browserSessionCreate, .browserSessionNavigate, .browserSessionClose,
         .fileDownload, .webDownload, .ocrRecognizeContent:
      return AgentNativeToolExecutionResult.failure(
        code: "web_media_provider_unavailable",
        message: "The iOS URLSession WebMedia provider does not implement \(operation.rawValue).",
        retryable: false
      )
    }
  }

  private func executeWeb(
    operation: AgentIOSWebMediaOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation,
    method: AgentIOSURLSessionWebRequest.Method
  ) -> AgentNativeToolExecutionResult {
    do {
      let url = try validatedPublicHTTPSURL(urlString(input))
      let timeoutMillis = try boundedTimeout(input, invocation: invocation)
      let maxBodyBytes = method == .head ? 0 : try boundedMaxBytes(input)
      let resource = try requestResource(
        requestedURL: url,
        method: method,
        maxBodyBytes: maxBodyBytes,
        timeoutMillis: timeoutMillis,
        invocation: invocation
      )
      let charset = charsetName(from: resource.selectedHeaders)
      var output = commonOutput(resource)
      switch operation {
      case .webHead:
        break
      case .webFetch:
        output["text"] = .string(boundedText(decode(resource.body, charset: charset), maxCharacters: AgentIOSWebMediaNativeToolCatalog.maxFetchBytes))
        output["charset"] = .string(charset)
        output["size_bytes"] = .int(Int64(resource.body.count))
        output["sha256"] = .string(sha256(resource.body))
      case .httpRequest:
        if method == .get {
          output["text"] = .string(boundedText(decode(resource.body, charset: charset), maxCharacters: AgentIOSWebMediaNativeToolCatalog.maxFetchBytes))
        }
      case .webOpen, .browserRender:
        let html = decode(resource.body, charset: charset)
        output["text"] = .string(boundedText(readableText(html), maxCharacters: AgentIOSWebMediaNativeToolCatalog.maxContentCharacters))
        output["html_sha256"] = .string(sha256(resource.body))
        output["render_mode"] = .string("bounded_http")
      case .contentExtract, .webSearch, .browserSessionCreate, .browserSessionNavigate, .browserSessionClose,
           .fileDownload, .webDownload, .ocrRecognizeContent:
        break
      }
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: message(operation, method: method),
        metadata: metadata(operation: operation, method: method)
      )
    } catch let error as AgentIOSURLSessionWebError {
      return failure(error)
    } catch {
      return failure(.transportFailed(error.localizedDescription))
    }
  }

  private func requestResource(
    requestedURL: URL,
    method: AgentIOSURLSessionWebRequest.Method,
    maxBodyBytes: Int64,
    timeoutMillis: Int64,
    invocation: AgentNativeToolInvocation
  ) throws -> AgentIOSURLSessionWebResource {
    let requestedAt = invocation.startedAtEpochMillis
    let deadline = min(requestedAt + timeoutMillis, invocation.deadlineEpochMillis)
    var currentURL = requestedURL
    var redirects: [AgentIOSURLSessionWebRedirect] = []
    var visited: Set<String> = [canonicalURL(requestedURL)]

    while true {
      if invocation.isCancellationRequested {
        throw AgentIOSURLSessionWebError.cancelled
      }
      let remainingMillis = min(deadline - nowMillis(), invocation.remainingTimeMillis)
      guard remainingMillis > 0 else {
        throw AgentIOSURLSessionWebError.timeout
      }
      let response = try transport.execute(
        AgentIOSURLSessionWebRequest(
          method: method,
          url: currentURL,
          timeoutMillis: remainingMillis,
          maxBodyBytes: maxBodyBytes,
          headers: [:]
        )
      )
      if invocation.isCancellationRequested {
        throw AgentIOSURLSessionWebError.cancelled
      }
      let headers = normalizedHeaders(response.headers)
      if isRedirectStatus(response.statusCode) {
        currentURL = try redirectURL(from: currentURL, headers: headers, statusCode: response.statusCode, redirects: &redirects, visited: &visited)
        continue
      }
      guard (200...299).contains(response.statusCode) else {
        throw AgentIOSURLSessionWebError.httpStatus(response.statusCode)
      }
      let rawContentType = header(headers, "content-type") ?? ""
      guard rawContentType.count <= 2_048 else {
        throw AgentIOSURLSessionWebError.headerTooLarge
      }
      let contentType = mediaType(rawContentType)
      if method == .get {
        guard !contentType.isEmpty, isFetchContentType(contentType) else {
          throw AgentIOSURLSessionWebError.unsupportedContentType(contentType.isEmpty ? "missing" : contentType)
        }
      }
      let declaredLength = contentLength(headers)
      if method == .get, let declaredLength, declaredLength > maxBodyBytes {
        throw AgentIOSURLSessionWebError.responseTooLarge(declaredLength, maxBodyBytes)
      }
      if method == .get, Int64(response.body.count) > maxBodyBytes {
        throw AgentIOSURLSessionWebError.responseTooLarge(Int64(response.body.count), maxBodyBytes)
      }
      return AgentIOSURLSessionWebResource(
        method: method,
        requestedURL: requestedURL.absoluteString,
        finalURL: currentURL.absoluteString,
        statusCode: response.statusCode,
        contentType: contentType,
        contentLengthBytes: declaredLength ?? (method == .get ? Int64(response.body.count) : -1),
        body: method == .get ? response.body : Data(),
        redirects: redirects,
        selectedHeaders: selectedHeaders(headers),
        requestedAtEpochMillis: requestedAt,
        retrievedAtEpochMillis: response.retrievedAtEpochMillis
      )
    }
  }

  private func redirectURL(
    from currentURL: URL,
    headers: [String: String],
    statusCode: Int,
    redirects: inout [AgentIOSURLSessionWebRedirect],
    visited: inout Set<String>
  ) throws -> URL {
    guard redirects.count < 4 else {
      throw AgentIOSURLSessionWebError.tooManyRedirects
    }
    guard let location = header(headers, "location"), !location.isEmpty else {
      throw AgentIOSURLSessionWebError.redirectMissingLocation
    }
    guard location.count <= Int(AgentIOSWebMediaNativeToolCatalog.maxUrlCharacters) else {
      throw AgentIOSURLSessionWebError.redirectURLTooLong
    }
    guard let nextCandidate = URL(string: location, relativeTo: currentURL)?.absoluteURL else {
      throw AgentIOSURLSessionWebError.invalidRedirect
    }
    let nextURL = try validatedPublicHTTPSURL(nextCandidate.absoluteString)
    let canonical = canonicalURL(nextURL)
    guard !visited.contains(canonical) else {
      throw AgentIOSURLSessionWebError.redirectLoop
    }
    visited.insert(canonical)
    redirects.append(
      AgentIOSURLSessionWebRedirect(
        statusCode: statusCode,
        fromURL: currentURL.absoluteString,
        toURL: nextURL.absoluteString
      )
    )
    return nextURL
  }

  private func requestMethod(_ input: AgentMcpJSONObject) -> AgentIOSURLSessionWebRequest.Method? {
    switch string(input, "method", limit: 16).uppercased() {
    case "GET":
      return .get
    case "HEAD":
      return .head
    default:
      return nil
    }
  }

  private func urlString(_ input: AgentMcpJSONObject) -> String {
    string(input, "url", limit: Int(AgentIOSWebMediaNativeToolCatalog.maxUrlCharacters))
  }

  private func boundedTimeout(_ input: AgentMcpJSONObject, invocation: AgentNativeToolInvocation) throws -> Int64 {
    let requested = input["timeout_ms"]?.intValue ?? AgentIOSWebMediaNativeToolCatalog.maxToolTimeoutMillis
    guard requested >= 1, requested <= AgentIOSWebMediaNativeToolCatalog.maxToolTimeoutMillis else {
      throw AgentIOSURLSessionWebError.invalidTimeout
    }
    let remaining = invocation.remainingTimeMillis
    guard remaining > 0 else {
      throw AgentIOSURLSessionWebError.timeout
    }
    return max(1, min(requested, remaining))
  }

  private func boundedMaxBytes(_ input: AgentMcpJSONObject) throws -> Int64 {
    let requested = input["max_bytes"]?.intValue ?? AgentIOSWebMediaNativeToolCatalog.maxFetchBytes
    guard requested >= 1, requested <= AgentIOSWebMediaNativeToolCatalog.maxFetchBytes else {
      throw AgentIOSURLSessionWebError.invalidLimit
    }
    return requested
  }

  private func validatedPublicHTTPSURL(_ value: String) throws -> URL {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          trimmed.count <= Int(AgentIOSWebMediaNativeToolCatalog.maxUrlCharacters),
          var components = URLComponents(string: trimmed),
          components.scheme?.lowercased() == "https",
          let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
          !host.isEmpty,
          components.user == nil,
          components.password == nil else {
      throw AgentIOSURLSessionWebError.invalidURL
    }
    if let port = components.port, !(1...65_535).contains(port) {
      throw AgentIOSURLSessionWebError.invalidURL
    }
    if isLocalOrPrivateHost(host) {
      throw AgentIOSURLSessionWebError.localHostBlocked
    }
    components.scheme = "https"
    guard let url = components.url else {
      throw AgentIOSURLSessionWebError.invalidURL
    }
    return url
  }

  private func isLocalOrPrivateHost(_ host: String) -> Bool {
    let clean = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
    if clean == "localhost" || clean.hasSuffix(".localhost") || clean.hasSuffix(".local") {
      return true
    }
    if isPrivateIPv4(clean) || isPrivateIPv6(clean) {
      return true
    }
    return false
  }

  private func isPrivateIPv4(_ host: String) -> Bool {
    let parts = host.split(separator: ".")
    guard parts.count == 4,
          let first = Int(parts[0]),
          let second = Int(parts[1]),
          parts.dropFirst(2).allSatisfy({ Int($0) != nil }) else {
      return false
    }
    if first == 0 || first == 10 || first == 127 {
      return true
    }
    if first == 100 && (64...127).contains(second) {
      return true
    }
    if first == 169 && second == 254 {
      return true
    }
    if first == 172 && (16...31).contains(second) {
      return true
    }
    if first == 192 && second == 168 {
      return true
    }
    if first == 198 && (18...19).contains(second) {
      return true
    }
    if first >= 224 {
      return true
    }
    return false
  }

  private func isPrivateIPv6(_ host: String) -> Bool {
    guard host.contains(":") else {
      return false
    }
    if host == "::" || host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") {
      return true
    }
    if host.hasPrefix("::ffff:") {
      return isPrivateIPv4(String(host.dropFirst("::ffff:".count)))
    }
    return false
  }

  private func commonOutput(_ resource: AgentIOSURLSessionWebResource) -> AgentMcpJSONObject {
    [
      "method": .string(resource.method == .head ? "head" : "get"),
      "status_code": .int(Int64(resource.statusCode)),
      "content_type": .string(resource.contentType),
      "content_length_bytes": .int(resource.contentLengthBytes),
      "requested_at_epoch_ms": .int(resource.requestedAtEpochMillis),
      "retrieved_at_epoch_ms": .int(resource.retrievedAtEpochMillis),
      "response_headers": .object(resource.selectedHeaders.mapValues { .string($0) }),
      "source": .object([
        "requested_url": .string(resource.requestedURL),
        "final_url": .string(resource.finalURL),
        "redirect_chain": .array(resource.redirects.map { redirect in
          .object([
            "status_code": .int(Int64(redirect.statusCode)),
            "from_url": .string(redirect.fromURL),
            "to_url": .string(redirect.toURL)
          ])
        }),
        "dns_resolution": .array([])
      ])
    ]
  }

  private func metadata(
    operation: AgentIOSWebMediaOperation,
    method: AgentIOSURLSessionWebRequest.Method
  ) -> AgentMcpJSONObject {
    var metadata: AgentMcpJSONObject = [
      "implementation": .string(implementationId),
      "platform": .string("ios_phone"),
      "bounded": .bool(true),
      "cookies": .string("none"),
      "network_policy": .string("public_https_urlsession_revalidated_v1"),
      "redirect_policy": .string("manual_revalidate_each_hop"),
      "dns_resolution": .string("urlsession_managed"),
      "method": .string(method.rawValue)
    ]
    if operation == .webOpen || operation == .browserRender {
      metadata["javascript"] = .bool(false)
      metadata["script_execution"] = .bool(false)
    }
    return metadata
  }

  private func message(
    _ operation: AgentIOSWebMediaOperation,
    method: AgentIOSURLSessionWebRequest.Method
  ) -> String {
    switch operation {
    case .webHead:
      return "Public HTTPS resource inspected"
    case .webFetch:
      return "Public HTTPS text fetched"
    case .httpRequest:
      return method == .head ? "Public HTTPS HEAD request completed" : "Public HTTPS GET request completed"
    case .webOpen, .browserRender:
      return "Public HTTPS page extracted"
    case .contentExtract, .webSearch, .browserSessionCreate, .browserSessionNavigate, .browserSessionClose,
         .fileDownload, .webDownload, .ocrRecognizeContent:
      return "WebMedia operation completed"
    }
  }

  private func failure(_ error: AgentIOSURLSessionWebError) -> AgentNativeToolExecutionResult {
    switch error {
    case .invalidURL:
      return failure("invalid_url", "WebMedia tools only accept public HTTPS URLs")
    case .invalidMethod:
      return failure("invalid_method", "HTTP method must be GET or HEAD")
    case .invalidTimeout:
      return failure("invalid_timeout", "Timeout must be between 1 and \(AgentIOSWebMediaNativeToolCatalog.maxToolTimeoutMillis) milliseconds")
    case .invalidLimit:
      return failure("invalid_limit", "Fetch limit must be between 1 and \(AgentIOSWebMediaNativeToolCatalog.maxFetchBytes) bytes")
    case .localHostBlocked:
      return failure("local_host_blocked", "Localhost and local-network HTTPS hosts are blocked")
    case .redirectMissingLocation:
      return failure("redirect_missing_location", "HTTPS redirect did not include Location")
    case .redirectURLTooLong:
      return failure("redirect_url_too_long", "HTTPS redirect URL is too long")
    case .invalidRedirect:
      return failure("invalid_redirect", "HTTPS redirect target is invalid")
    case .redirectLoop:
      return failure("redirect_loop", "HTTPS redirect loop detected")
    case .tooManyRedirects:
      return failure("too_many_redirects", "HTTPS response exceeded the redirect limit")
    case .timeout:
      return failure("web_media_timeout", "Timed out waiting for the HTTPS response", retryable: true)
    case .cancelled:
      return failure("web_media_cancelled", "The HTTPS request was cancelled")
    case .transportFailed(let message):
      return failure("transport_failed", message.isEmpty ? "HTTPS transport failed" : message, retryable: true)
    case .invalidResponse:
      return failure("invalid_response", "HTTPS transport did not return an HTTP response", retryable: true)
    case .httpStatus(let statusCode):
      return failure(
        "http_status",
        "HTTPS resource returned HTTP \(statusCode)",
        retryable: statusCode == 408 || statusCode == 429 || statusCode >= 500,
        details: ["status_code": .int(Int64(statusCode))]
      )
    case .headerTooLarge:
      return failure("header_too_large", "Content-Type header is too large")
    case .unsupportedContentType(let contentType):
      return failure(
        "unsupported_content_type",
        "HTTPS content type is not allowed: \(contentType)",
        details: ["content_type": .string(contentType)]
      )
    case .responseTooLarge(let actualBytes, let maxBytes):
      return failure(
        "response_too_large",
        "HTTPS response exceeds the \(maxBytes) byte limit",
        details: [
          "content_length_bytes": .int(actualBytes),
          "max_bytes": .int(maxBytes)
        ]
      )
    }
  }

  private func failure(
    _ code: String,
    _ message: String,
    retryable: Bool = false,
    details: AgentMcpJSONObject = [:]
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(code: code, message: message, retryable: retryable, details: details)
  }

  private func normalizedHeaders(_ headers: [String: String]) -> [String: String] {
    var normalized: [String: String] = [:]
    headers.forEach { name, value in
      normalized[name.lowercased()] = String(value.prefix(2_048))
    }
    return normalized
  }

  private func selectedHeaders(_ headers: [String: String]) -> [String: String] {
    ["content-type", "etag", "last-modified", "cache-control", "content-disposition"].reduce(into: [:]) { result, name in
      if let value = header(headers, name) {
        result[name] = String(value.prefix(2_048))
      }
    }
  }

  private func header(_ headers: [String: String], _ name: String) -> String? {
    headers[name.lowercased()]
  }

  private func mediaType(_ contentType: String) -> String {
    contentType.split(separator: ";", maxSplits: 1).first.map {
      String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    } ?? ""
  }

  private func contentLength(_ headers: [String: String]) -> Int64? {
    guard let raw = header(headers, "content-length")?.trimmingCharacters(in: .whitespacesAndNewlines),
          let length = Int64(raw),
          length >= 0 else {
      return nil
    }
    return length
  }

  private func isRedirectStatus(_ statusCode: Int) -> Bool {
    [301, 302, 303, 307, 308].contains(statusCode)
  }

  private func isFetchContentType(_ contentType: String) -> Bool {
    if contentType.hasPrefix("text/") {
      return true
    }
    if contentType.hasSuffix("+json") || contentType.hasSuffix("+xml") {
      return true
    }
    return [
      "application/json",
      "application/xml",
      "application/xhtml+xml",
      "application/javascript",
      "application/x-javascript",
      "application/ecmascript",
      "application/rss+xml",
      "application/atom+xml"
    ].contains(contentType)
  }

  private func charsetName(from headers: [String: String]) -> String {
    let raw = header(headers, "content-type") ?? ""
    for segment in raw.split(separator: ";") {
      let parts = segment.split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else { continue }
      let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard key == "charset" else { continue }
      let value = String(parts[1]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
      return canonicalCharset(value)
    }
    return "UTF-8"
  }

  private func canonicalCharset(_ value: String) -> String {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "utf-8", "utf8":
      return "UTF-8"
    case "us-ascii", "ascii":
      return "US-ASCII"
    case "iso-8859-1", "latin1", "latin-1":
      return "ISO-8859-1"
    case "utf-16":
      return "UTF-16"
    case "utf-16le":
      return "UTF-16LE"
    case "utf-16be":
      return "UTF-16BE"
    default:
      return "UTF-8"
    }
  }

  private func decode(_ data: Data, charset: String) -> String {
    let encoding: String.Encoding
    switch charset {
    case "US-ASCII":
      encoding = .ascii
    case "ISO-8859-1":
      encoding = .isoLatin1
    case "UTF-16":
      encoding = .utf16
    case "UTF-16LE":
      encoding = .utf16LittleEndian
    case "UTF-16BE":
      encoding = .utf16BigEndian
    default:
      encoding = .utf8
    }
    return String(data: data, encoding: encoding)
      ?? String(data: data, encoding: .utf8)
      ?? String(decoding: data, as: UTF8.self)
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

  private func boundedText(_ value: String, maxCharacters: Int64) -> String {
    String(value.prefix(Int(max(0, maxCharacters))))
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func canonicalURL(_ url: URL) -> String {
    url.absoluteString.lowercased()
  }

  private func string(_ input: AgentMcpJSONObject, _ key: String, limit: Int) -> String {
    String((input[key]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}

private struct AgentIOSURLSessionWebRedirect {
  var statusCode: Int
  var fromURL: String
  var toURL: String
}

private struct AgentIOSURLSessionWebResource {
  var method: AgentIOSURLSessionWebRequest.Method
  var requestedURL: String
  var finalURL: String
  var statusCode: Int
  var contentType: String
  var contentLengthBytes: Int64
  var body: Data
  var redirects: [AgentIOSURLSessionWebRedirect]
  var selectedHeaders: [String: String]
  var requestedAtEpochMillis: Int64
  var retrievedAtEpochMillis: Int64
}
