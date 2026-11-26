import Foundation

#if canImport(Darwin)
import Darwin
#endif

#if canImport(WebKit) && canImport(UIKit)
import UIKit
import WebKit
#endif

struct AgentIOSDynamicWebRenderedPage: Equatable {
  var finalURL: String
  var contentType: String
  var body: Data
  var durationMillis: Int64
}

protocol AgentIOSDynamicWebRendering {
  var isAvailable: Bool { get }

  func render(
    url: URL,
    maxBytes: Int64,
    timeoutMillis: Int64,
    isCancellationRequested: @escaping () -> Bool,
    checkpoint: @escaping () throws -> Void
  ) throws -> AgentIOSDynamicWebRenderedPage
}

enum AgentIOSDynamicWebRenderError: Error, Equatable {
  case unavailable
  case mainThreadInvocation
  case invalidURL
  case privateAddress
  case capacityTimeout
  case cancelled
  case timedOut
  case navigationBlocked
  case navigationFailed(String)
  case contentProcessTerminated
  case temporarilyUnavailable
  case startupTimeout
  case emptyDocument
  case responseTooLarge(Int64, Int64)
}

final class AgentIOSWebRendererHealth {
  static let shared = AgentIOSWebRendererHealth()
  private let lock = NSLock()
  private let now: () -> UInt64
  private let cooldown: UInt64
  private var failedAt: UInt64?

  init(cooldownNanoseconds: UInt64 = 30_000_000_000,
       now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
    cooldown = cooldownNanoseconds
    self.now = now
  }

  func checkAvailable() throws {
    lock.lock()
    defer { lock.unlock() }
    if let failedAt {
      let current = now()
      if current >= failedAt, current - failedAt < cooldown {
        throw AgentIOSDynamicWebRenderError.temporarilyUnavailable
      }
      self.failedAt = nil
    }
  }

  func failed() {
    lock.lock()
    failedAt = now()
    lock.unlock()
  }

  func succeeded() {
    lock.lock()
    failedAt = nil
    lock.unlock()
  }

  static func isProcessFailure(_ error: Error) -> Bool {
    guard let failure = error as? AgentIOSDynamicWebRenderError else { return false }
    switch failure {
    case .contentProcessTerminated, .startupTimeout, .unavailable: return true
    default: return false
    }
  }
}

enum AgentIOSWebRenderPreflight {
  private final class State: @unchecked Sendable {
    let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var closed = false
    private var value: Bool?
    func complete(_ value: Bool) {
      lock.lock()
      defer { lock.unlock() }
      guard !closed else { return }
      self.value = value
      completion.signal()
    }
    func close() {
      lock.lock(); closed = true; lock.unlock()
    }
    func result() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return value == true
    }
  }

  private static let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "galaxyssi.web-renderer-preflight"
    queue.maxConcurrentOperationCount = 1
    return queue
  }()

  static func resolve(deadline: DispatchTime, isCancellationRequested: () -> Bool,
                      checkpoint: () throws -> Void, resolver: @escaping () -> Bool) throws -> Bool {
    func check() throws {
      if isCancellationRequested() { throw AgentIOSDynamicWebRenderError.cancelled }
      try checkpoint()
      if DispatchTime.now() >= deadline { throw AgentIOSDynamicWebRenderError.timedOut }
    }
    try check()
    let state = State()
    let operation = BlockOperation { state.complete(resolver()) }
    defer { state.close(); operation.cancel() }
    queue.addOperation(operation)
    while state.completion.wait(timeout: min(deadline, .now() + .milliseconds(50))) == .timedOut {
      try check()
    }
    try check()
    return state.result()
  }
}

enum AgentIOSDynamicWebFallbackPolicy {
  static func reason(contentType: String, body: Data) -> String? {
    let source = AgentIOSWebTextDecoder.decode(body.prefix(300_000), contentType: contentType).text
    guard AgentIOSWebTextDecoder.isHTML(contentType: contentType, textPrefix: String(source.prefix(256))) else { return nil }
    let lower = source.lowercased()
    if javascriptRequiredMarkers.contains(where: lower.contains) { return "javascript_required" }
    if managedChallengeMarkers.contains(where: lower.contains) { return "managed_challenge" }
    let visible = readableText(source, limit: 1_000)
    let hasScripts = lower.contains("<script")
    if hasScripts, visible.count < 180,
       source.range(of: emptyApplicationShellPattern, options: [.regularExpression, .caseInsensitive]) != nil {
      return "thin_javascript_shell"
    }
    if hasScripts, visible.isBlank { return "empty_javascript_shell" }
    return nil
  }

  private static func readableText(_ source: String, limit: Int) -> String {
    String(
      source
        .replacingOccurrences(
          of: #"(?is)<(script|style|noscript)[^>]*>.*?</\1>"#,
          with: " ",
          options: .regularExpression
        )
        .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .prefix(limit)
    )
  }

  private static let javascriptRequiredMarkers = [
    "enable javascript",
    "javascript is required",
    "please enable javascript",
    "\u{8bf7}\u{542f}\u{7528}javascript",
    "\u{8bf7}\u{5f00}\u{542f}javascript"
  ]
  private static let managedChallengeMarkers = ["cf-chl-", "challenge-platform", "checking your browser"]
  private static let emptyApplicationShellPattern =
    #"<(?:div|main)[^>]+id=[\"'](?:root|app|__next|application)[\"'][^>]*>\s*</(?:div|main)>"#
}

enum AgentIOSWebRenderURLPolicy {
  static func allows(_ value: String) -> Bool {
    guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          components.scheme?.lowercased() == "https",
          components.user == nil,
          components.password == nil,
          let host = components.host?.lowercased(),
          !host.isBlank else {
      return false
    }
    return !isLocalOrPrivateHost(host)
  }

  static func resolvesToPublicAddress(_ value: String) -> Bool {
    guard allows(value), let host = URLComponents(string: value)?.host else { return false }
    if AgentIOSPublicAddressPolicy.isNumericHost(host) { return !isLocalOrPrivateHost(host) }
#if canImport(Darwin)
    var hints = addrinfo()
    hints.ai_flags = AI_ADDRCONFIG
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = Int32(IPPROTO_TCP)
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return false }
    defer { freeaddrinfo(first) }
    var cursor: UnsafeMutablePointer<addrinfo>? = first
    var addresses: [String] = []
    while let entry = cursor?.pointee {
      if let address = entry.ai_addr {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(
          address,
          entry.ai_addrlen,
          &buffer,
          socklen_t(buffer.count),
          nil,
          0,
          NI_NUMERICHOST
        ) == 0 {
          addresses.append(String(cString: buffer))
        }
      }
      cursor = entry.ai_next
    }
    return !addresses.isEmpty && addresses.allSatisfy { !isLocalOrPrivateHost($0) }
#else
    return false
#endif
  }

  static func allowsSubresource(_ value: String) -> Bool {
    guard let scheme = URLComponents(string: value)?.scheme?.lowercased() else { return false }
    if ["data", "blob", "about"].contains(scheme) { return true }
    return scheme == "https" && allows(value)
  }

  static func sameOrigin(initial: String, candidate: String) -> Bool {
    guard allows(candidate),
          let first = URLComponents(string: initial),
          let second = URLComponents(string: candidate) else {
      return false
    }
    return first.scheme?.lowercased() == second.scheme?.lowercased() &&
      first.host?.lowercased() == second.host?.lowercased() &&
      normalizedPort(first) == normalizedPort(second)
  }

  private static func normalizedPort(_ value: URLComponents) -> Int {
    value.port ?? 443
  }

  private static func isLocalOrPrivateHost(_ value: String) -> Bool {
    AgentIOSPublicAddressPolicy.blocksHost(value)
  }
}

#if canImport(WebKit) && canImport(UIKit)
final class AgentIOSWKWebViewRenderer: AgentIOSDynamicWebRendering {
  var isAvailable: Bool { true }
  private let health: AgentIOSWebRendererHealth

  init(health: AgentIOSWebRendererHealth = .shared) { self.health = health }

  func render(
    url: URL,
    maxBytes: Int64,
    timeoutMillis: Int64,
    isCancellationRequested: @escaping () -> Bool,
    checkpoint: @escaping () throws -> Void
  ) throws -> AgentIOSDynamicWebRenderedPage {
    guard !Thread.isMainThread else { throw AgentIOSDynamicWebRenderError.mainThreadInvocation }
    let boundedTimeout = min(max(timeoutMillis, 1_000), 60_000)
    let deadline = DispatchTime.now() + .milliseconds(Int(boundedTimeout))
    if isCancellationRequested() { throw AgentIOSDynamicWebRenderError.cancelled }
    try checkpoint()
    try health.checkAvailable()
    guard AgentIOSWebRenderURLPolicy.allows(url.absoluteString) else {
      throw AgentIOSDynamicWebRenderError.invalidURL
    }
    guard try AgentIOSWebRenderPreflight.resolve(deadline: deadline,
      isCancellationRequested: isCancellationRequested, checkpoint: checkpoint,
      resolver: { AgentIOSWebRenderURLPolicy.resolvesToPublicAddress(url.absoluteString) }) else {
      throw AgentIOSDynamicWebRenderError.privateAddress
    }
    try acquireCapacity(
      deadline: deadline,
      isCancellationRequested: isCancellationRequested,
      checkpoint: checkpoint
    )
    defer { Self.renderCapacity.signal() }
    if isCancellationRequested() { throw AgentIOSDynamicWebRenderError.cancelled }
    try checkpoint()
    if DispatchTime.now() >= deadline { throw AgentIOSDynamicWebRenderError.timedOut }
    try health.checkAvailable()
    let coordinator = AgentIOSWKWebViewRenderCoordinator(url: url, maxBytes: maxBytes)
    defer { coordinator.cancel() }
    let startupDeadline = min(deadline, DispatchTime.now() + .seconds(5))
    DispatchQueue.main.async { coordinator.start() }
    do {
      while coordinator.completion.wait(timeout: min(deadline, .now() + .milliseconds(50))) == .timedOut {
        if isCancellationRequested() { throw AgentIOSDynamicWebRenderError.cancelled }
        try checkpoint()
        if !coordinator.hasStarted, DispatchTime.now() >= startupDeadline {
          throw AgentIOSDynamicWebRenderError.startupTimeout
        }
        if DispatchTime.now() >= deadline { throw AgentIOSDynamicWebRenderError.timedOut }
      }
      if isCancellationRequested() { throw AgentIOSDynamicWebRenderError.cancelled }
      try checkpoint()
      if DispatchTime.now() >= deadline { throw AgentIOSDynamicWebRenderError.timedOut }
      let page = try coordinator.result().get()
      health.succeeded()
      return page
    } catch {
      if AgentIOSWebRendererHealth.isProcessFailure(error) { health.failed() }
      throw error
    }
  }

  private func acquireCapacity(
    deadline: DispatchTime,
    isCancellationRequested: () -> Bool,
    checkpoint: () throws -> Void
  ) throws {
    while Self.renderCapacity.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
      if isCancellationRequested() { throw AgentIOSDynamicWebRenderError.cancelled }
      try checkpoint()
      if DispatchTime.now() >= deadline { throw AgentIOSDynamicWebRenderError.capacityTimeout }
    }
  }

  private static let renderCapacity = DispatchSemaphore(value: 1)
}

private final class AgentIOSWKWebViewRenderCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
  let completion = DispatchSemaphore(value: 0)

  private let initialURL: URL
  private let maxBytes: Int64
  private let startedAt = Date()
  private let lock = NSLock()
  private var webView: WKWebView?
  private var outcome: Result<AgentIOSDynamicWebRenderedPage, Error>?
  private var started = false

  var hasStarted: Bool {
    lock.lock()
    defer { lock.unlock() }
    return started
  }

  private var isFinished: Bool {
    lock.lock()
    defer { lock.unlock() }
    return outcome != nil
  }

  init(url: URL, maxBytes: Int64) {
    initialURL = url
    self.maxBytes = max(1, maxBytes)
  }

  func start() {
    guard !isFinished else { return }
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.processPool = WKProcessPool()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.defaultWebpagePreferences.preferredContentMode = .mobile
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = self
    view.uiDelegate = self
    view.customUserAgent = AgentIOSPublicArticleRequestPolicy.headers(for: initialURL)["User-Agent"]
      ?? "GalaxySSI-iOS/1.0 Mobile Web Evidence Renderer"
    webView = view
    guard !isFinished else { view.stopLoading(); return }
    lock.lock()
    started = true
    lock.unlock()
    var request = URLRequest(url: initialURL)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.httpShouldHandleCookies = false
    AgentIOSPublicArticleRequestPolicy.headers(for: initialURL).forEach { request.setValue($1, forHTTPHeaderField: $0) }
    view.load(request)
  }

  func cancel() {
    finish(.failure(AgentIOSDynamicWebRenderError.cancelled))
  }

  func result() -> Result<AgentIOSDynamicWebRenderedPage, Error> {
    lock.lock()
    defer { lock.unlock() }
    return outcome ?? .failure(AgentIOSDynamicWebRenderError.emptyDocument)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard !isFinished else { decisionHandler(.cancel); return }
    guard let candidate = navigationAction.request.url?.absoluteString else {
      decisionHandler(.cancel)
      finish(.failure(AgentIOSDynamicWebRenderError.navigationBlocked))
      return
    }
    guard navigationAction.targetFrame != nil else {
      decisionHandler(.cancel)
      return
    }
    let allowed: Bool
    if navigationAction.targetFrame?.isMainFrame == true {
      allowed = AgentIOSWebRenderURLPolicy.sameOrigin(initial: initialURL.absoluteString, candidate: candidate)
    } else {
      allowed = AgentIOSWebRenderURLPolicy.allowsSubresource(candidate)
    }
    decisionHandler(allowed ? .allow : .cancel)
    if !allowed, navigationAction.targetFrame?.isMainFrame == true {
      finish(.failure(AgentIOSDynamicWebRenderError.navigationBlocked))
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self, weak webView] in
      guard let self, let webView, !self.isFinished else { return }
      let maximumCharacters = max(1, min(Int(self.maxBytes), 4_000_000))
      let script = "document.documentElement ? document.documentElement.outerHTML.slice(0, \(maximumCharacters)) : ''"
      webView.evaluateJavaScript(script) { value, error in
        if let error {
          self.finish(.failure(AgentIOSDynamicWebRenderError.navigationFailed(error.localizedDescription)))
          return
        }
        let html = value as? String ?? ""
        let body = Data(html.utf8)
        guard !body.isEmpty else {
          self.finish(.failure(AgentIOSDynamicWebRenderError.emptyDocument))
          return
        }
        guard Int64(body.count) <= self.maxBytes else {
          self.finish(.failure(AgentIOSDynamicWebRenderError.responseTooLarge(Int64(body.count), self.maxBytes)))
          return
        }
        let elapsed = Int64(Date().timeIntervalSince(self.startedAt) * 1_000)
        self.finish(.success(AgentIOSDynamicWebRenderedPage(
          finalURL: webView.url?.absoluteString ?? self.initialURL.absoluteString,
          contentType: "text/html; charset=utf-8",
          body: body,
          durationMillis: max(0, elapsed)
        )))
      }
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish(.failure(AgentIOSDynamicWebRenderError.navigationFailed(error.localizedDescription)))
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    finish(.failure(AgentIOSDynamicWebRenderError.navigationFailed(error.localizedDescription)))
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    finish(.failure(AgentIOSDynamicWebRenderError.contentProcessTerminated))
  }

  func webView(
    _ webView: WKWebView,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
      completionHandler(.performDefaultHandling, nil)
    } else {
      completionHandler(.cancelAuthenticationChallenge, nil)
    }
  }

  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    nil
  }

  @available(iOS 15.0, *)
  func webView(
    _ webView: WKWebView,
    requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    decisionHandler(.deny)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(false)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (String?) -> Void
  ) {
    completionHandler(nil)
  }

  private func finish(_ result: Result<AgentIOSDynamicWebRenderedPage, Error>) {
    lock.lock()
    guard outcome == nil else {
      lock.unlock()
      return
    }
    outcome = result
    lock.unlock()
    DispatchQueue.main.async {
      self.webView?.stopLoading()
      self.webView?.navigationDelegate = nil
      self.webView?.uiDelegate = nil
      self.webView = nil
    }
    completion.signal()
  }
}
#else
struct AgentIOSWKWebViewRenderer: AgentIOSDynamicWebRendering {
  var isAvailable: Bool { false }

  func render(
    url: URL,
    maxBytes: Int64,
    timeoutMillis: Int64,
    isCancellationRequested: @escaping () -> Bool,
    checkpoint: @escaping () throws -> Void
  ) throws -> AgentIOSDynamicWebRenderedPage {
    throw AgentIOSDynamicWebRenderError.unavailable
  }
}
#endif
