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
  case invalidSearchQuery
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

private enum AgentIOSURLSessionWebContentPolicy {
  case fetchText
  case download
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
    urlRequest.setValue("GalaxySSI-iOS/1.0", forHTTPHeaderField: "User-Agent")
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
  var browserSessions: AgentIOSURLSessionBrowserSessionStore
  var downloadWriter: AgentIOSWebMediaDownloadWriting
  var ocrProcessor: AgentIOSWebMediaOCRProcessing
  var dynamicRenderer: AgentIOSDynamicWebRendering
  var nowMillis: () -> Int64

  init(
    transport: AgentIOSURLSessionWebTransporting = AgentIOSDefaultURLSessionWebTransport(),
    implementationId: String = "galaxyssi.ios.urlsession_web_media",
    browserSessions: AgentIOSURLSessionBrowserSessionStore? = nil,
    downloadWriter: AgentIOSWebMediaDownloadWriting = AgentIOSFileWebMediaDownloadWriter(),
    ocrProcessor: AgentIOSWebMediaOCRProcessing = AgentIOSWebMediaOCRPipeline(),
    dynamicRenderer: AgentIOSDynamicWebRendering = AgentIOSWKWebViewRenderer(),
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    self.transport = transport
    self.implementationId = implementationId
    self.browserSessions = browserSessions ?? AgentIOSURLSessionBrowserSessionStore()
    self.downloadWriter = downloadWriter
    self.ocrProcessor = ocrProcessor
    self.dynamicRenderer = dynamicRenderer
    self.nowMillis = nowMillis
  }

  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability {
    switch operation {
    case .contentExtract, .webSearch, .webOpen, .browserRender, .browserSessionCreate, .browserSessionNavigate,
         .browserSessionClose, .httpRequest, .fileDownload, .webHead, .webFetch, .webDownload:
      return .available
    case .ocrRecognizeContent:
      return ocrProcessor.availability
    }
  }

  func invoke(
    operation: AgentIOSWebMediaOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    switch operation {
    case .webSearch:
      return executeSearch(input: input, invocation: invocation)
    case .browserSessionCreate:
      return executeBrowserSessionCreate(input: input, invocation: invocation)
    case .browserSessionNavigate:
      return executeBrowserSessionNavigate(input: input, invocation: invocation)
    case .browserSessionClose:
      return executeBrowserSessionClose(input: input, invocation: invocation)
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
    case .fileDownload, .webDownload:
      return executeDownload(operation: operation, input: input, invocation: invocation)
    case .ocrRecognizeContent:
      return ocrProcessor.invoke(input: input, invocation: invocation)
    case .contentExtract:
      return AgentNativeToolExecutionResult.failure(
        code: "unexpected_provider_call",
        message: "content.extract is handled by the iOS WebMedia executor."
      )
    }
  }

  private func executeSearch(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    do {
      let query = string(input, "query", limit: 1_024)
      guard !query.isEmpty else {
        throw AgentIOSURLSessionWebError.invalidSearchQuery
      }
      let requestedMaxResults = input["max_results"]?.intValue ?? 5
      let maxResults = Int(max(Int64(1), min(requestedMaxResults, Int64(24))))
      let profile = (input["profile"]?.stringValue ?? "balanced").lowercased()
      let explicitSources = !(input["engines"]?.arrayValue ?? []).isEmpty
      let timeoutMillis = try boundedTimeout(input, invocation: invocation)
      let deadline = min(invocation.startedAtEpochMillis + timeoutMillis, invocation.deadlineEpochMillis)
      let endpoints = try searchEndpoints(query: query, maxResults: maxResults)
      let accumulator = AgentIOSWebSearchAccumulator()
      let group = DispatchGroup()
      for (index, endpoint) in endpoints.enumerated() {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
          defer { group.leave() }
          if invocation.isCancellationRequested {
            accumulator.append(AgentIOSWebSearchAttempt(index: index, provider: endpoint.provider, error: .cancelled))
            return
          }
          let remaining = min(deadline - nowMillis(), invocation.remainingTimeMillis)
          guard remaining >= 250 else {
            accumulator.append(AgentIOSWebSearchAttempt(index: index, provider: endpoint.provider, error: .timeout))
            return
          }
          do {
            let resource = try requestResource(
              requestedURL: endpoint.url,
              method: .get,
              maxBodyBytes: AgentIOSWebMediaNativeToolCatalog.maxFetchBytes,
              timeoutMillis: min(4_000, remaining),
              invocation: invocation
            )
            let charset = charsetName(from: resource.selectedHeaders)
            let html = decode(resource.body, charset: charset)
            accumulator.append(
              AgentIOSWebSearchAttempt(
                index: index,
                provider: endpoint.provider,
                resource: resource,
                results: parseSearchResults(html, maxResults: maxResults)
              )
            )
          } catch let error as AgentIOSURLSessionWebError {
            accumulator.append(AgentIOSWebSearchAttempt(index: index, provider: endpoint.provider, error: error))
          } catch {
            accumulator.append(
              AgentIOSWebSearchAttempt(
                index: index,
                provider: endpoint.provider,
                error: .transportFailed(error.localizedDescription)
              )
            )
          }
        }
      }

      var completed = false
      var earlyCompleted = false
      while !completed && !earlyCompleted {
        let groups = accumulator.snapshot().map { attempt in
          attempt.results.map { $0.url }
        }
        if AgentIOSWebSearchCompletionPolicy.hasSufficientEvidence(
          profile: profile,
          explicitSources: explicitSources,
          groups: groups,
          limit: maxResults,
          providerCount: endpoints.count
        ) {
          earlyCompleted = true
          break
        }
        let remaining = max(0, min(timeoutMillis, invocation.remainingTimeMillis))
        guard remaining > 0 else { break }
        let slice = max(1, min(100, remaining))
        completed = group.wait(timeout: .now() + .milliseconds(Int(slice))) == .success
      }
      if invocation.isCancellationRequested {
        throw AgentIOSURLSessionWebError.cancelled
      }
      let attempts = accumulator.snapshot().sorted { $0.index < $1.index }
      guard let first = attempts.first(where: { !$0.results.isEmpty }),
            let resource = first.resource else {
        if !completed {
          return failure(.timeout)
        }
        if let lastError = attempts.compactMap(\.error).last {
          return failure(lastError)
        }
        return failure(
          "search_no_results",
          "Public search providers returned no readable results",
          retryable: true
        )
      }

      var merged: [AgentIOSWebSearchResult] = []
      var seenURLs: Set<String> = []
      for attempt in attempts where attempt.resource != nil {
        for result in attempt.results {
          let key = URL(string: result.url).map(canonicalURL) ?? result.url.lowercased()
          guard !key.isEmpty, seenURLs.insert(key).inserted else { continue }
          merged.append(result)
          if merged.count >= maxResults { break }
        }
        if merged.count >= maxResults { break }
      }
      var output = commonOutput(resource)
      output["query"] = .string(query)
      output["results"] = .array(merged.map { result in
        .object([
          "title": .string(result.title),
          "url": .string(result.url)
        ])
      })
      output["result_count"] = .int(Int64(merged.count))
      var resultMetadata = metadata(operation: .webSearch, method: .get)
      let successfulProviders = attempts.filter { !$0.results.isEmpty }.map(\.provider)
      let completedProviders = Set(attempts.map(\.provider))
      let cancelledProviders = earlyCompleted
        ? endpoints.map(\.provider).filter { !completedProviders.contains($0) }
        : []
      resultMetadata["provider"] = .string(first.provider)
      resultMetadata["profile"] = .string(profile)
      resultMetadata["providers"] = .array(successfulProviders.map(AgentMcpJSONValue.string))
      resultMetadata["engine_fanout"] = .int(Int64(endpoints.count))
      resultMetadata["parallel"] = .bool(true)
      resultMetadata["partial"] = .bool(!completed && !earlyCompleted)
      resultMetadata["early_completed"] = .bool(earlyCompleted)
      resultMetadata["completion_reason"] = .string(
        earlyCompleted ? "sufficient_diverse_evidence" : ""
      )
      resultMetadata["cancelled_providers"] = .array(cancelledProviders.map(AgentMcpJSONValue.string))
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: message(.webSearch, method: .get),
        metadata: resultMetadata
      )
    } catch let error as AgentIOSURLSessionWebError {
      return failure(error)
    } catch {
      return failure(.transportFailed(error.localizedDescription))
    }
  }

  private func executeBrowserSessionCreate(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    do {
      let requestedURL = urlString(input)
      let scope = AgentIOSURLSessionBrowserSessionScope(context: invocation.context)
      if requestedURL.isEmpty {
        let snapshot = browserSessions.create(
          scope: scope,
          resourceId: invocation.context.invocationId,
          currentURL: "",
          nowMillis: nowMillis()
        )
        return AgentNativeToolExecutionResult.success(
          output: browserSessionOutput(snapshot),
          message: "Isolated browser session created",
          metadata: browserSessionMetadata()
        )
      }

      let url = try validatedPublicHTTPSURL(requestedURL)
      let resource = try requestResource(
        requestedURL: url,
        method: .get,
        maxBodyBytes: try boundedMaxBytes(input),
        timeoutMillis: try boundedTimeout(input, invocation: invocation),
        invocation: invocation
      )
      let snapshot = browserSessions.create(
        scope: scope,
        resourceId: invocation.context.invocationId,
        currentURL: resource.finalURL,
        nowMillis: nowMillis()
      )
      var output = commonOutput(resource).merging(browserSessionOutput(snapshot)) { current, _ in current }
      let html = decode(resource.body, charset: charsetName(from: resource.selectedHeaders))
      output["text"] = .string(boundedText(readableText(html), maxCharacters: AgentIOSWebMediaNativeToolCatalog.maxContentCharacters))
      output["html_sha256"] = .string(sha256(resource.body))
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: "Isolated browser session created",
        metadata: browserSessionMetadata()
      )
    } catch let error as AgentIOSURLSessionBrowserSessionStoreError {
      return browserSessionFailure(error)
    } catch let error as AgentIOSURLSessionWebError {
      return failure(error)
    } catch {
      return failure(.transportFailed(error.localizedDescription))
    }
  }

  private func executeBrowserSessionNavigate(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    let browserId = string(input, "browser_id", limit: Int(AgentIOSWebMediaNativeToolCatalog.maxBrowserHandleCharacters))
    let scope = AgentIOSURLSessionBrowserSessionScope(context: invocation.context)
    do {
      try browserSessions.validate(browserId: browserId, scope: scope, nowMillis: nowMillis())
      let resource = try requestResource(
        requestedURL: try validatedPublicHTTPSURL(urlString(input)),
        method: .get,
        maxBodyBytes: try boundedMaxBytes(input),
        timeoutMillis: try boundedTimeout(input, invocation: invocation),
        invocation: invocation
      )
      let snapshot = try browserSessions.navigate(
        browserId: browserId,
        scope: scope,
        currentURL: resource.finalURL,
        nowMillis: nowMillis()
      )
      var output = commonOutput(resource).merging(browserSessionOutput(snapshot)) { current, _ in current }
      let html = decode(resource.body, charset: charsetName(from: resource.selectedHeaders))
      output["text"] = .string(boundedText(readableText(html), maxCharacters: AgentIOSWebMediaNativeToolCatalog.maxContentCharacters))
      output["html_sha256"] = .string(sha256(resource.body))
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: "Browser session navigated",
        metadata: browserSessionMetadata()
      )
    } catch let error as AgentIOSURLSessionBrowserSessionStoreError {
      return browserSessionFailure(error)
    } catch let error as AgentIOSURLSessionWebError {
      return failure(error)
    } catch {
      return failure(.transportFailed(error.localizedDescription))
    }
  }

  private func executeBrowserSessionClose(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    let browserId = string(input, "browser_id", limit: Int(AgentIOSWebMediaNativeToolCatalog.maxBrowserHandleCharacters))
    do {
      let snapshot = try browserSessions.close(
        browserId: browserId,
        scope: AgentIOSURLSessionBrowserSessionScope(context: invocation.context),
        nowMillis: nowMillis()
      )
      return AgentNativeToolExecutionResult.success(
        output: [
          "browser_id": .string(snapshot.browserId),
          "closed": .bool(true),
          "expires_at_epoch_ms": .int(snapshot.expiresAtEpochMillis)
        ],
        message: "Browser session closed",
        metadata: [
          "tool_handle_contract": .string(AgentIOSURLSessionBrowserSessionStore.toolHandleContract),
          "state_model": .string("explicit_browser_id"),
          "persistence": .string("process_lifetime")
        ]
      )
    } catch let error as AgentIOSURLSessionBrowserSessionStoreError {
      return browserSessionFailure(error)
    } catch {
      return failure(.transportFailed(error.localizedDescription))
    }
  }

  private func executeDownload(
    operation: AgentIOSWebMediaOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    let destination = string(input, "destination_content_uri", limit: 4_096)
    do {
      try downloadWriter.validate(destinationContentURI: destination)
      let resource = try requestResource(
        requestedURL: try validatedPublicHTTPSURL(urlString(input)),
        method: .get,
        maxBodyBytes: try boundedMaxBytes(input, maximum: AgentIOSWebMediaNativeToolCatalog.maxDownloadBytes),
        timeoutMillis: try boundedTimeout(input, invocation: invocation),
        invocation: invocation,
        contentPolicy: .download
      )
      let written = try downloadWriter.write(
        destinationContentURI: destination,
        contentType: resource.contentType,
        data: resource.body
      )
      var output = commonOutput(resource)
      output["destination_content_uri"] = .string(written.contentURI)
      output["size_bytes"] = .int(written.bytesWritten)
      output["sha256"] = .string(sha256(resource.body))
      var resultMetadata = metadata(operation: operation, method: .get)
      resultMetadata["writer_implementation"] = .string(downloadWriter.implementationId)
      resultMetadata["auto_execute"] = .bool(false)
      resultMetadata["destination_scope"] = .string("file_url_user_authorized")
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: "Public HTTPS resource downloaded to selected iOS file URL",
        metadata: resultMetadata
      )
    } catch let error as AgentIOSWebMediaDownloadWriteError {
      return downloadFailure(error)
    } catch let error as AgentIOSURLSessionWebError {
      return failure(error)
    } catch {
      return failure(.transportFailed(error.localizedDescription))
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
      let resolution = try resolvedResource(
        operation: operation,
        requestedURL: url,
        method: method,
        maxBodyBytes: maxBodyBytes,
        timeoutMillis: timeoutMillis,
        invocation: invocation
      )
      let resource = resolution.resource
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
        let article = AgentIOSPublicArticleParser.parse(url: URL(string: resource.finalURL) ?? url, source: html)
        output["text"] = .string(article?.content ?? boundedText(
          readableText(html),
          maxCharacters: AgentIOSWebMediaNativeToolCatalog.maxContentCharacters
        ))
        output["html_sha256"] = .string(sha256(resource.body))
        output["render_mode"] = .string(resolution.dynamicRendered ? "isolated_wkwebview" : "bounded_http")
        if let reason = resolution.fallbackReason {
          output["dynamic_fallback_reason"] = .string(reason)
        }
        if let error = resolution.fallbackError {
          output["dynamic_fallback_error"] = .string(error)
        }
        if let duration = resolution.dynamicDurationMillis {
          output["dynamic_render_duration_millis"] = .int(duration)
        }
        if let article = article {
          output["title"] = .string(article.title)
          output["article"] = .object([
            "source_type": .string(article.sourceType),
            "author": .string(article.author),
            "published_at": .string(article.publishedAt),
            "links": .array(article.links.map(AgentMcpJSONValue.string)),
            "image_count": .int(Int64(article.images.count)),
            "lead_image_url": .string(article.images.first?.url ?? ""),
            "images": .array(article.images.map { image in
              var value: AgentMcpJSONObject = [
                "index": .int(Int64(image.index)),
                "url": .string(image.url)
              ]
              if !image.alt.isEmpty {
                value["alt"] = .string(image.alt)
              }
              if let width = image.width {
                value["width"] = .int(Int64(width))
              }
              if let height = image.height {
                value["height"] = .int(Int64(height))
              }
              return .object(value)
            })
          ])
        }
      case .contentExtract, .webSearch, .browserSessionCreate, .browserSessionNavigate, .browserSessionClose,
           .fileDownload, .webDownload, .ocrRecognizeContent:
        break
      }
      var resultMetadata = metadata(operation: operation, method: method)
      if operation == .webOpen || operation == .browserRender {
        resultMetadata["javascript"] = .bool(resolution.dynamicRendered)
        resultMetadata["script_execution"] = .bool(resolution.dynamicRendered)
        resultMetadata["render_mode"] = .string(
          resolution.dynamicRendered ? "isolated_wkwebview" : "bounded_http"
        )
        resultMetadata["dynamic_fallback_attempted"] = .bool(resolution.fallbackAttempted)
        if let reason = resolution.fallbackReason {
          resultMetadata["dynamic_fallback_reason"] = .string(reason)
        }
        if let error = resolution.fallbackError {
          resultMetadata["dynamic_fallback_error"] = .string(error)
        }
        if let duration = resolution.dynamicDurationMillis {
          resultMetadata["dynamic_render_duration_millis"] = .int(duration)
        }
      }
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: message(operation, method: method),
        metadata: resultMetadata
      )
    } catch let error as AgentIOSURLSessionWebError {
      return failure(error)
    } catch {
      return failure(.transportFailed(error.localizedDescription))
    }
  }

  private func resolvedResource(
    operation: AgentIOSWebMediaOperation,
    requestedURL: URL,
    method: AgentIOSURLSessionWebRequest.Method,
    maxBodyBytes: Int64,
    timeoutMillis: Int64,
    invocation: AgentNativeToolInvocation
  ) throws -> AgentIOSWebOpenResourceResolution {
    guard operation == .webOpen || operation == .browserRender else {
      return AgentIOSWebOpenResourceResolution(
        resource: try requestResource(
          requestedURL: requestedURL,
          method: method,
          maxBodyBytes: maxBodyBytes,
          timeoutMillis: timeoutMillis,
          invocation: invocation
        )
      )
    }

    do {
      let staticResource = try requestResource(
        requestedURL: requestedURL,
        method: method,
        maxBodyBytes: maxBodyBytes,
        timeoutMillis: timeoutMillis,
        invocation: invocation
      )
      let reason = operation == .browserRender
        ? "explicit_browser_render"
        : AgentIOSDynamicWebFallbackPolicy.reason(
          contentType: staticResource.contentType,
          body: staticResource.body
        )
      guard let reason else { return AgentIOSWebOpenResourceResolution(resource: staticResource) }
      guard dynamicRenderer.isAvailable else {
        return AgentIOSWebOpenResourceResolution(
          resource: staticResource,
          fallbackReason: reason,
          fallbackError: "renderer_unavailable",
          fallbackAttempted: false,
          dynamicRendered: false
        )
      }
      do {
        let targetURL = URL(string: staticResource.finalURL) ?? requestedURL
        let rendered = try renderDynamicPage(
          url: targetURL,
          maxBodyBytes: maxBodyBytes,
          timeoutMillis: timeoutMillis,
          invocation: invocation
        )
        return AgentIOSWebOpenResourceResolution(
          resource: dynamicResource(rendered, preserving: staticResource),
          fallbackReason: reason,
          fallbackAttempted: true,
          dynamicRendered: true,
          dynamicDurationMillis: rendered.durationMillis
        )
      } catch {
        if let interruption = dynamicInterruption(error, invocation: invocation) {
          throw interruption
        }
        return AgentIOSWebOpenResourceResolution(
          resource: staticResource,
          fallbackReason: reason,
          fallbackError: String(String(describing: error).prefix(500)),
          fallbackAttempted: true,
          dynamicRendered: false
        )
      }
    } catch {
      let staticError = error
      guard dynamicRenderer.isAvailable else { throw staticError }
      do {
        let rendered = try renderDynamicPage(
          url: requestedURL,
          maxBodyBytes: maxBodyBytes,
          timeoutMillis: timeoutMillis,
          invocation: invocation
        )
        return AgentIOSWebOpenResourceResolution(
          resource: dynamicResource(
            rendered,
            requestedURL: requestedURL,
            requestedAtMillis: invocation.startedAtEpochMillis
          ),
          fallbackReason: "static_fetch_failed",
          fallbackAttempted: true,
          dynamicRendered: true,
          dynamicDurationMillis: rendered.durationMillis
        )
      } catch {
        if let interruption = dynamicInterruption(error, invocation: invocation) {
          throw interruption
        }
        throw staticError
      }
    }
  }

  private func dynamicInterruption(
    _ error: Error,
    invocation: AgentNativeToolInvocation
  ) -> AgentIOSURLSessionWebError? {
    if invocation.isCancellationRequested { return .cancelled }
    if invocation.isTimedOut { return .timeout }
    if let renderError = error as? AgentIOSDynamicWebRenderError {
      switch renderError {
      case .cancelled:
        return .cancelled
      case .timedOut:
        return .timeout
      default:
        return nil
      }
    }
    if let invocationError = error as? AgentNativeToolInvocationError {
      switch invocationError {
      case .cancelled:
        return .cancelled
      case .timedOut:
        return .timeout
      }
    }
    return nil
  }

  private func renderDynamicPage(
    url: URL,
    maxBodyBytes: Int64,
    timeoutMillis: Int64,
    invocation: AgentNativeToolInvocation
  ) throws -> AgentIOSDynamicWebRenderedPage {
    try dynamicRenderer.render(
      url: url,
      maxBytes: maxBodyBytes,
      timeoutMillis: min(timeoutMillis, invocation.remainingTimeMillis),
      isCancellationRequested: { invocation.isCancellationRequested },
      checkpoint: { try invocation.checkpoint() }
    )
  }

  private func dynamicResource(
    _ rendered: AgentIOSDynamicWebRenderedPage,
    preserving source: AgentIOSURLSessionWebResource
  ) -> AgentIOSURLSessionWebResource {
    var resource = source
    resource.finalURL = rendered.finalURL
    resource.contentType = rendered.contentType
    resource.contentLengthBytes = Int64(rendered.body.count)
    resource.body = rendered.body
    resource.retrievedAtEpochMillis = max(source.retrievedAtEpochMillis, nowMillis())
    return resource
  }

  private func dynamicResource(
    _ rendered: AgentIOSDynamicWebRenderedPage,
    requestedURL: URL,
    requestedAtMillis: Int64
  ) -> AgentIOSURLSessionWebResource {
    AgentIOSURLSessionWebResource(
      method: .get,
      requestedURL: requestedURL.absoluteString,
      finalURL: rendered.finalURL,
      statusCode: 200,
      contentType: rendered.contentType,
      contentLengthBytes: Int64(rendered.body.count),
      body: rendered.body,
      redirects: [],
      selectedHeaders: ["content-type": rendered.contentType],
      requestedAtEpochMillis: requestedAtMillis,
      retrievedAtEpochMillis: max(requestedAtMillis, nowMillis())
    )
  }

  private func searchEndpoints(query: String, maxResults: Int) throws -> [(provider: String, url: URL)] {
    let orderedProviders: [String] = query.unicodeScalars.contains { $0.value > 127 }
      ? ["baidu", "bing", "duckduckgo"]
      : ["bing", "baidu", "duckduckgo"]
    return try orderedProviders.map { provider in
      let components: URLComponents
      switch provider {
      case "baidu":
        components = searchComponents(
          scheme: "https",
          host: "www.baidu.com",
          path: "/s",
          queryItems: [
            URLQueryItem(name: "wd", value: query),
            URLQueryItem(name: "rn", value: String(maxResults))
          ]
        )
      case "duckduckgo":
        components = searchComponents(
          scheme: "https",
          host: "html.duckduckgo.com",
          path: "/html/",
          queryItems: [URLQueryItem(name: "q", value: query)]
        )
      default:
        components = searchComponents(
          scheme: "https",
          host: "cn.bing.com",
          path: "/search",
          queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(maxResults))
          ]
        )
      }
      guard let url = components.url else {
        throw AgentIOSURLSessionWebError.invalidURL
      }
      return (provider, try validatedPublicHTTPSURL(url.absoluteString))
    }
  }

  private func searchComponents(
    scheme: String,
    host: String,
    path: String,
    queryItems: [URLQueryItem]
  ) -> URLComponents {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = path
    components.queryItems = queryItems
    return components
  }

  private func parseSearchResults(_ html: String, maxResults: Int) -> [AgentIOSWebSearchResult] {
    let patterns = [
      #"<div[^>]+class=["'][^"']*b_algoheader[^"']*["'][^>]*>\s*<a[^>]+href=["']([^"']+)["'][^>]*>\s*<h2[^>]*>(.*?)</h2>"#,
      #"<a[^>]+class=["'][^"']*result__a[^"']*["'][^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>"#,
      #"<li[^>]+class=["'][^"']*b_algo[^"']*["'][^>]*>.*?<h2[^>]*>\s*<a[^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>"#,
      #"<h3[^>]+class=["'][^"']*(?:c-title|\bt\b)[^"']*["'][^>]*>.*?<a[^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>"#,
      #"<a[^>]+href=["']([^"']+)["'][^>]*>\s*<h3[^>]*>(.*?)</h3>"#
    ]
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
    var seenURLs: Set<String> = []
    var results: [AgentIOSWebSearchResult] = []
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(
        pattern: pattern,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
      ) else {
        continue
      }
      for match in regex.matches(in: html, options: [], range: nsRange) {
        guard results.count < maxResults,
              match.numberOfRanges >= 3,
              let urlRange = Range(match.range(at: 1), in: html),
              let titleRange = Range(match.range(at: 2), in: html),
              let url = normalizedSearchResultURL(String(html[urlRange])) else {
          continue
        }
        let title = String(readableText(String(html[titleRange])).prefix(4_096))
        guard !title.isEmpty, !seenURLs.contains(url) else {
          continue
        }
        seenURLs.insert(url)
        results.append(AgentIOSWebSearchResult(title: title, url: url))
      }
      if results.count >= maxResults {
        break
      }
    }
    return results
  }

  private func normalizedSearchResultURL(_ value: String) -> String? {
    let decoded = decodeHTMLEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate: String
    if decoded.hasPrefix("//") {
      candidate = "https:\(decoded)"
    } else if decoded.hasPrefix("/") {
      candidate = duckDuckGoRedirectTarget(decoded) ?? decoded
    } else {
      candidate = duckDuckGoRedirectTarget(decoded) ?? decoded
    }
    let lower = candidate.lowercased()
    guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
      return nil
    }
    return String(candidate.prefix(Int(AgentIOSWebMediaNativeToolCatalog.maxUrlCharacters)))
  }

  private func duckDuckGoRedirectTarget(_ value: String) -> String? {
    let urlString = value.hasPrefix("/")
      ? "https://duckduckgo.com\(value)"
      : value
    guard let components = URLComponents(string: urlString),
          let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
          !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return decodeHTMLEntities(target).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func requestResource(
    requestedURL: URL,
    method: AgentIOSURLSessionWebRequest.Method,
    maxBodyBytes: Int64,
    timeoutMillis: Int64,
    invocation: AgentNativeToolInvocation,
    contentPolicy: AgentIOSURLSessionWebContentPolicy = .fetchText
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
          headers: AgentIOSPublicArticleRequestPolicy.headers(for: currentURL)
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
        guard !contentType.isEmpty, isAllowedContentType(contentType, policy: contentPolicy) else {
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

  private func boundedMaxBytes(
    _ input: AgentMcpJSONObject,
    maximum: Int64 = AgentIOSWebMediaNativeToolCatalog.maxFetchBytes
  ) throws -> Int64 {
    let requested = input["max_bytes"]?.intValue ?? maximum
    guard requested >= 1, requested <= maximum else {
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

  private func browserSessionOutput(_ snapshot: AgentIOSURLSessionBrowserSessionSnapshot) -> AgentMcpJSONObject {
    var output: AgentMcpJSONObject = [
      "browser_id": .string(snapshot.browserId),
      "history_count": .int(Int64(snapshot.historyCount)),
      "expires_at_epoch_ms": .int(snapshot.expiresAtEpochMillis)
    ]
    if !snapshot.currentURL.isEmpty {
      output["current_url"] = .string(snapshot.currentURL)
    }
    return output
  }

  private func browserSessionMetadata() -> AgentMcpJSONObject {
    [
      "implementation": .string(implementationId),
      "platform": .string("ios_phone"),
      "bounded": .bool(true),
      "tool_handle_contract": .string(AgentIOSURLSessionBrowserSessionStore.toolHandleContract),
      "state_model": .string("explicit_browser_id"),
      "cookies": .string("none"),
      "network_policy": .string("public_https_urlsession_revalidated_v1"),
      "redirect_policy": .string("manual_revalidate_each_hop"),
      "dns_resolution": .string("urlsession_managed"),
      "javascript": .bool(false),
      "script_execution": .bool(false),
      "render_mode": .string("bounded_http")
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
    case .webSearch:
      return "Public web search completed"
    case .webHead:
      return "Public HTTPS resource inspected"
    case .webFetch:
      return "Public HTTPS text fetched"
    case .httpRequest:
      return method == .head ? "Public HTTPS HEAD request completed" : "Public HTTPS GET request completed"
    case .webOpen, .browserRender:
      return "Public HTTPS page extracted"
    case .contentExtract, .browserSessionCreate, .browserSessionNavigate, .browserSessionClose,
         .fileDownload, .webDownload, .ocrRecognizeContent:
      return "WebMedia operation completed"
    }
  }

  private func failure(_ error: AgentIOSURLSessionWebError) -> AgentNativeToolExecutionResult {
    switch error {
    case .invalidURL:
      return failure("invalid_url", "WebMedia tools only accept public HTTPS URLs")
    case .invalidSearchQuery:
      return failure("invalid_query", "Search query must not be blank")
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

  private func browserSessionFailure(_ error: AgentIOSURLSessionBrowserSessionStoreError) -> AgentNativeToolExecutionResult {
    switch error {
    case .toolHandleNotFound:
      return failure(
        "tool_handle_not_found",
        "Tool handle is missing, expired, or was released",
        retryable: true
      )
    case .toolHandleExpired:
      return failure(
        "tool_handle_expired",
        "Tool handle expired; create a new handle and retry",
        retryable: true
      )
    case .toolHandleOwnerMismatch:
      return failure("tool_handle_owner_mismatch", "Tool handle belongs to a different caller")
    case .toolHandleContextMismatch:
      return failure("tool_handle_context_mismatch", "Tool handle belongs to a different conversation context")
    }
  }

  private func downloadFailure(_ error: AgentIOSWebMediaDownloadWriteError) -> AgentNativeToolExecutionResult {
    switch error {
    case .destinationRequired:
      return failure("invalid_destination_content_uri", "Downloads require a selected file:// destination")
    case .unsupportedDestinationScheme:
      return failure("unsupported_destination_content_uri", "iOS WebMedia downloads currently require a file:// destination URI")
    case .invalidDestination:
      return failure("invalid_destination_content_uri", "Download destination is invalid")
    case .writeFailed(let message):
      return failure(
        "content_uri_unavailable",
        message.isEmpty ? "Selected destination cannot be opened for writing" : message,
        retryable: true
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

  private func isAllowedContentType(_ contentType: String, policy: AgentIOSURLSessionWebContentPolicy) -> Bool {
    switch policy {
    case .fetchText:
      return isFetchContentType(contentType)
    case .download:
      return isDownloadContentType(contentType)
    }
  }

  private func isDownloadContentType(_ contentType: String) -> Bool {
    if ["text/", "image/", "audio/", "video/"].contains(where: contentType.hasPrefix) {
      return true
    }
    if isFetchContentType(contentType) {
      return true
    }
    return [
      "application/pdf",
      "application/zip",
      "application/gzip",
      "application/octet-stream",
      "application/msword",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation"
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

  private func decodeHTMLEntities(_ source: String) -> String {
    source
      .replacingOccurrences(of: "&nbsp;", with: " ", options: [.caseInsensitive])
      .replacingOccurrences(of: "&amp;", with: "&", options: [.caseInsensitive])
      .replacingOccurrences(of: "&lt;", with: "<", options: [.caseInsensitive])
      .replacingOccurrences(of: "&gt;", with: ">", options: [.caseInsensitive])
      .replacingOccurrences(of: "&quot;", with: "\"", options: [.caseInsensitive])
      .replacingOccurrences(of: "&#39;", with: "'", options: [.caseInsensitive])
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

private struct AgentIOSWebSearchResult {
  var title: String
  var url: String
}

private struct AgentIOSWebSearchAttempt {
  var index: Int
  var provider: String
  var resource: AgentIOSURLSessionWebResource?
  var results: [AgentIOSWebSearchResult]
  var error: AgentIOSURLSessionWebError?

  init(
    index: Int,
    provider: String,
    resource: AgentIOSURLSessionWebResource? = nil,
    results: [AgentIOSWebSearchResult] = [],
    error: AgentIOSURLSessionWebError? = nil
  ) {
    self.index = index
    self.provider = provider
    self.resource = resource
    self.results = results
    self.error = error
  }
}

private final class AgentIOSWebSearchAccumulator {
  private let lock = NSLock()
  private var attempts: [AgentIOSWebSearchAttempt] = []

  func append(_ attempt: AgentIOSWebSearchAttempt) {
    lock.lock()
    attempts.append(attempt)
    lock.unlock()
  }

  func snapshot() -> [AgentIOSWebSearchAttempt] {
    lock.lock()
    defer { lock.unlock() }
    return attempts
  }
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

private struct AgentIOSWebOpenResourceResolution {
  var resource: AgentIOSURLSessionWebResource
  var fallbackReason: String? = nil
  var fallbackError: String? = nil
  var fallbackAttempted: Bool = false
  var dynamicRendered: Bool = false
  var dynamicDurationMillis: Int64? = nil
}
