import Foundation
import WebKit

@MainActor
final class GalaxySSIWeChatBrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
  @Published private(set) var loading = true
  @Published private(set) var saving = false
  @Published private(set) var needsVerification = false
  @Published private(set) var failure: AgentIOSWeChatArticleFailure?
  @Published private(set) var saved: AgentIOSWeChatArticlePDFResult?
  private var generation = UUID(), closed = false, httpError = false, exporting = false
  private var navigation: WKNavigation?
  private var autoSaveLanguage: String?
  private var lease: AgentIOSWeChatExportGate.Lease?
  private var clock = AgentIOSWeChatExportClock()
  private var saveTask: Task<Void, Never>?, lifetime: Task<Void, Never>?, probeTimeout: Task<Void, Never>?
  private var probeID: UUID?
  private var probeContinuation: CheckedContinuation<AgentIOSWeChatArticleDOM.State, Error>?

  lazy var webView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = self; view.uiDelegate = self
    return view
  }()
  static func articleURL(_ value: String) -> URL? { AgentIOSWeChatArticlePDF.articleURL(value) }
  static func allows(_ url: URL?, mainFrame: Bool) -> Bool {
    guard let url, url.scheme?.lowercased() == "https", url.port == nil,
      url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
    return mainFrame ? host == "mp.weixin.qq.com" :
      ["qq.com", "gtimg.com", "qpic.cn"].contains { host == $0 || host.hasSuffix("." + $0) }
  }
  func load(_ url: URL, autoSave: Bool = false, language: String = "en") {
    guard !closed, Self.articleURL(url.absoluteString) != nil else { return }
    let token = generation
    autoSaveLanguage = autoSave ? language : nil
    let rules = #"""
      [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
       {"trigger":{"url-filter":"^https://([a-zA-Z0-9-]+\\.)*(qq\\.com|gtimg\\.com|qpic\\.cn)/"},
        "action":{"type":"ignore-previous-rules"}}]
      """#
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "galaxyssi-wechat-article-v1",
      encodedContentRuleList: rules) { [weak self] list, _ in
      Task { @MainActor in
        guard let self, self.generation == token, !self.closed else { return }
        guard let list else { self.finish(.loadFailed); return }
        self.webView.configuration.userContentController.add(list)
        self.webView.load(URLRequest(url: url))
      }
    }
  }
  func save(language: String) {
    guard !closed else { return }
    guard !saving else { failure = .alreadySaving; return }
    if lease == nil {
      do { lease = try AgentIOSWeChatExportGate.shared.acquire() }
      catch { failure = .alreadySaving; return }
      clock = .init()
      let owner = lease?.id
      lifetime = Task { @MainActor [weak self] in
        do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
        guard let self, self.lease?.id == owner else { return }
        self.finish(self.needsVerification ? .verificationExpired : .bodyUnavailable)
      }
    }
    guard let lease else { return }
    saving = true; failure = nil; saved = nil; needsVerification = false
    let messages = AgentIOSWeChatArticleMessages(language: language)
    let deadline = min(clock.now() + 120_000, clock.origin + 300_000)
    saveTask = Task { @MainActor [weak self, lease] in
      defer { withExtendedLifetime(lease) {} }
      guard let self else { return }
      var signature = "", stable = 0
      do {
        while !Task.isCancelled, !self.closed {
          guard self.clock.now() < deadline else {
            throw self.httpError ? AgentIOSWeChatArticleFailure.loadFailed : .bodyUnavailable
          }
          if self.webView.url == nil { try await Task.sleep(nanoseconds: 750_000_000); continue }
          let token = self.generation
          let state = try await self.probe(expected: nil, deadline: deadline)
          if token != self.generation { signature = ""; stable = 0; try await Task.sleep(nanoseconds: 750_000_000); continue }
          if state.phase == "verify" {
            self.needsVerification = true; self.saving = false; self.loading = false; self.saveTask = nil
            return
          }
          if state.phase == "oversize" { throw AgentIOSWeChatArticleFailure.tooLarge }
          if state.phase == "ready", let current = state.signature {
            stable = signature == current ? stable + 1 : 0; signature = current
            if stable >= 2, !self.httpError {
              let snapshot = try await self.probe(expected: signature, deadline: deadline)
              if token != self.generation || snapshot.phase == "changed" {
                signature = ""; stable = 0; try await Task.sleep(nanoseconds: 750_000_000); continue
              }
              if snapshot.phase == "oversize" { throw AgentIOSWeChatArticleFailure.tooLarge }
              if snapshot.phase == "verify" {
                self.needsVerification = true; self.saving = false; self.loading = false; self.saveTask = nil
                return
              }
              guard !self.httpError, let url = self.webView.url, Self.articleURL(url.absoluteString) != nil,
                snapshot.address == url.absoluteString,
                let article = snapshot.article else { throw AgentIOSWeChatArticleFailure.bodyUnavailable }
              try article.validate()
              self.exporting = true
              let result = try await AgentIOSWeChatArticlePDF.exportLoaded(document: article, url: url, messages: messages,
                lease: lease, clock: self.clock)
              guard !Task.isCancelled, !self.closed, token == self.generation else {
                try? FileManager.default.removeItem(at: result.url); return
              }
              self.saved = result; self.finish(nil)
              return
            }
          } else { signature = ""; stable = 0 }
          try await Task.sleep(nanoseconds: 750_000_000)
        }
      } catch {
        guard !self.closed, !Task.isCancelled else { return }
        self.finish((error as? AgentIOSWeChatArticleFailure) ?? .loadFailed)
      }
    }
  }
  private func probe(expected: String?, deadline: Int64) async throws -> AgentIOSWeChatArticleDOM.State {
    guard let page = webView.url, Self.allows(page, mainFrame: true) else { throw AgentIOSWeChatArticleFailure.loadFailed }
    let id = UUID(), token = generation
    probeTimeout?.cancel()
    probeTimeout = Task { @MainActor [weak self] in
      do { try await Task.sleep(nanoseconds: UInt64(max(1, deadline - (self?.clock.now() ?? deadline))) * 1_000_000) } catch { return }
      guard let self, self.probeID == id else { return }
      self.resolveProbe(.failure(AgentIOSWeChatArticleFailure.bodyUnavailable))
    }
    defer { probeTimeout?.cancel() }
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        probeContinuation = continuation; probeID = id
        webView.callAsyncJavaScript(AgentIOSWeChatArticleDOM.script,
          arguments: ["html": "", "page": page.absoluteString, "live": true, "expected": expected.map { $0 as Any } ?? NSNull()],
          in: nil, contentWorld: .defaultClient) { [weak self] result in
          Task { @MainActor in
            guard let self, self.probeID == id else { return }
            if token != self.generation || self.webView.url != page {
              self.resolveProbe(.success(.init(phase: "changed", signature: nil, article: nil))); return
            }
            do {
              guard let json = try result.get() as? String else { throw AgentIOSWeChatArticleFailure.bodyUnavailable }
              guard json.utf8.count <= AgentIOSWeChatArticleLimits.htmlBytes else { throw AgentIOSWeChatArticleFailure.tooLarge }
              self.resolveProbe(.success(try JSONDecoder().decode(AgentIOSWeChatArticleDOM.State.self, from: Data(json.utf8))))
            } catch { self.resolveProbe(.failure((error as? AgentIOSWeChatArticleFailure) ?? .bodyUnavailable)) }
          }
        }
      }
    }, onCancel: { [weak self] in Task { @MainActor in self?.resolveProbe(.failure(CancellationError())) } })
  }
  private func resolveProbe(_ result: Result<AgentIOSWeChatArticleDOM.State, Error>) {
    let continuation = probeContinuation
    probeContinuation = nil; probeID = nil; probeTimeout?.cancel()
    continuation?.resume(with: result)
  }
  private func finish(_ error: AgentIOSWeChatArticleFailure?) {
    saveTask?.cancel(); saveTask = nil; lifetime?.cancel(); lifetime = nil
    resolveProbe(.failure(CancellationError()))
    loading = false; saving = false; needsVerification = false; exporting = false; failure = error; lease = nil
  }
  func close() {
    closed = true; generation = UUID(); finish(nil)
    webView.stopLoading(); webView.navigationDelegate = nil; webView.uiDelegate = nil
  }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let frame = action.targetFrame else { decisionHandler(.cancel); return }
    decisionHandler(Self.allows(action.request.url, mainFrame: frame.isMainFrame) ? .allow : .cancel)
  }
  func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
               initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
               decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    let mime = response.response.mimeType?.lowercased()
    let allowed = response.canShowMIMEType && Self.allows(response.response.url, mainFrame: response.isForMainFrame) &&
      (!response.isForMainFrame || mime == "text/html" || mime == "application/xhtml+xml")
    if response.isForMainFrame { httpError = (response.response as? HTTPURLResponse).map { !(200...299).contains($0.statusCode) } ?? true }
    decisionHandler(allowed ? .allow : .cancel)
    if !allowed && response.isForMainFrame { finish(.loadFailed) }
  }
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    self.navigation = navigation
    generation = UUID(); loading = true; httpError = false; saved = nil
    if exporting { finish(.bodyUnavailable) }
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    if let language = autoSaveLanguage { autoSaveLanguage = nil; save(language: language) }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if navigation === self.navigation { loading = false; finish(.loadFailed) }
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if navigation === self.navigation { loading = false; finish(.loadFailed) }
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loading = false; finish(.loadFailed) }
}
