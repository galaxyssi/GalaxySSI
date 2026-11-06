import SwiftUI
import WebKit

@MainActor
struct GalaxySSIManagedBrowserHandoffView: View {
  @Environment(\.presentationMode) private var presentation
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var coordinator: MessageCoordinator
  @StateObject private var browser = ManagedBrowserViewSession()
  @State private var failed = false
  let request: AgentManagedBrowserPresentation

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Button { presentation.wrappedValue.dismiss() } label: {
          Image(systemName: "xmark").frame(width: 44, height: 44)
        }
        .accessibilityLabel(t("galaxyssi.common.close", "Close"))
        Spacer(minLength: 0)
        Text(browser.currentAddress?.host ?? t("galaxyssi.managed_browser.title", "Browser control"))
          .font(.headline).lineLimit(1)
        Spacer(minLength: 0)
        Button { returnControl() } label: {
          Label(t("galaxyssi.managed_browser.return", "Return control"), systemImage: "arrow.uturn.backward")
            .lineLimit(2)
        }
        .disabled(!browser.canReturn)
        .padding(.trailing, 12)
      }
      if failed {
        Text(t("galaxyssi.managed_browser.failed", "Browser control could not be returned."))
          .font(.footnote).foregroundColor(.secondary).padding(8)
      }
      ManagedBrowserWebView(session: browser)
    }
    .onAppear {
      browser.authorize = { [weak coordinator] in
        coordinator?.managedBrowserPresentationIsCurrent(request) == true
      }
      browser.persistCookies = { [weak coordinator] cookies in
        guard let coordinator else { throw AgentManagedBrowserContinuationStore.Failure.staleTicket }
        try coordinator.saveManagedBrowserCookies(cookies, for: request)
      }
      Task { @MainActor in
        do {
          let cookies = try coordinator.managedBrowserCookies(request)
          await browser.load(request.handoff.address, restoring: cookies)
        } catch { failed = true }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: AgentManagedBrowserContinuationStore.changed)) { _ in
      if !coordinator.managedBrowserPresentationIsCurrent(request) { browser.close(); presentation.wrappedValue.dismiss() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIAgentTeamExecutionHistoryDidUpdate)) { _ in
      if !coordinator.managedBrowserPresentationIsCurrent(request) { browser.close(); presentation.wrappedValue.dismiss() }
    }
    .onReceive(coordinator.store.$profile) { _ in
      if !coordinator.managedBrowserPresentationIsCurrent(request) { browser.close(); presentation.wrappedValue.dismiss() }
    }
    .onDisappear { browser.close() }
  }

  private func returnControl() {
    Task { @MainActor in
      do {
        let observation = try await browser.observation()
        try await browser.flushCookies()
        try coordinator.returnManagedBrowserControl(request, observation: observation)
        presentation.wrappedValue.dismiss()
      } catch { failed = true }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

@MainActor
private struct ManagedBrowserWebView: UIViewRepresentable {
  let session: ManagedBrowserViewSession

  func makeUIView(context: Context) -> WKWebView { session.view }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
private final class ManagedBrowserViewSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate,
  WKHTTPCookieStoreObserver {
  @Published private(set) var currentAddress: URL?
  @Published private(set) var canReturn = false
  var authorize: () -> Bool = { false }
  var persistCookies: ([HTTPCookie]) throws -> Void = { _ in }
  private var loaded = false
  private var cookieObserverInstalled = false
  private lazy var webView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.processPool = WKProcessPool()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = self
    view.uiDelegate = self
    return view
  }()

  var view: WKWebView { webView }

  func load(_ address: String, restoring cookies: [HTTPCookie]) async {
    guard !loaded, authorize(), let url = AgentManagedBrowserHandoff.url(address) else { return }
    loaded = true
    let jar = webView.configuration.websiteDataStore.httpCookieStore
    for cookie in cookies {
      guard authorize() else { return }
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        jar.setCookie(cookie) { continuation.resume() }
      }
    }
    guard authorize() else { return }
    jar.add(self)
    cookieObserverInstalled = true
    webView.load(URLRequest(url: url))
  }

  func close() {
    authorize = { false }
    canReturn = false
    if cookieObserverInstalled {
      webView.configuration.websiteDataStore.httpCookieStore.remove(self)
      cookieObserverInstalled = false
    }
    if loaded { webView.stopLoading() }
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard authorize(), let url = action.request.url, action.targetFrame?.isMainFrame == true,
          AgentIOSWebRenderURLPolicy.allows(url.absoluteString) else { decisionHandler(.cancel); return }
    canReturn = false
    Task { @MainActor [weak self] in
      let allowed = await Task.detached(priority: .utility) {
        AgentIOSWebRenderURLPolicy.resolvesToPublicAddress(url.absoluteString)
      }.value
      decisionHandler(allowed && self?.authorize() == true ? .allow : .cancel)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard authorize(), let url = webView.url, AgentIOSWebRenderURLPolicy.allows(url.absoluteString) else { return }
    currentAddress = url
    canReturn = true
  }

  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    guard authorize(), let url = response.response.url, response.canShowMIMEType,
          AgentIOSWebRenderURLPolicy.allows(url.absoluteString) else { decisionHandler(.cancel); return }
    decisionHandler(.allow)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { canReturn = false }

  func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    Task { @MainActor [weak self] in try? await self?.flushCookies() }
  }

  func flushCookies() async throws {
    guard authorize(), cookieObserverInstalled else { throw AgentManagedBrowserContinuationStore.Failure.staleTicket }
    let jar = webView.configuration.websiteDataStore.httpCookieStore
    let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
      jar.getAllCookies { continuation.resume(returning: $0) }
    }
    guard authorize() else { throw AgentManagedBrowserContinuationStore.Failure.staleTicket }
    try persistCookies(cookies)
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

  func observation() async throws -> AgentManagedBrowserHandoff.Observation {
    guard canReturn, authorize(), let url = currentAddress, webView.url == url else {
      throw AgentManagedBrowserContinuationStore.Failure.notReady
    }
    let page = try await webView.evaluateJavaScript(
      "({ title: (document.title || '').slice(0, 256), text: (document.body?.innerText || '').slice(0, 4000) })")
    guard authorize(), canReturn, webView.url == url, let fields = page as? [String: String] else {
      throw AgentManagedBrowserContinuationStore.Failure.scopeChanged
    }
    return .init(address: url.absoluteString, title: fields["title"] ?? "", text: fields["text"] ?? "")
  }
}
