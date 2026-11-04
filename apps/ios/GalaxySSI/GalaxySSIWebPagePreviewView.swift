import SwiftUI
import UIKit
import WebKit

struct GalaxySSIWeChatArticleBrowser: View {
  let url: URL
  let t: (String, String) -> String
  @Environment(\.dismiss) private var dismiss
  @StateObject private var browser = GalaxySSIWeChatBrowserSession()

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        BrowserSurface(browser: browser)
        if browser.loading || browser.saving { ProgressView().padding(8) }
        if let filename = browser.savedName {
          Text(String(format: t("galaxyssi.screen_page.wechat_browser_saved",
            "Saved in Files: GalaxySSI / Downloads / GongZhongHao / %@"), filename))
            .font(.footnote).padding(8)
        } else if browser.failed {
          Text(t("galaxyssi.screen_page.wechat_browser_failed",
            "The article could not be saved. Complete any verification and try again."))
            .font(.footnote).padding(8)
        }
      }
      .navigationTitle(t("galaxyssi.screen_page.wechat_browser", "WeChat Article Browser"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.close", "Close")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            browser.save()
          } label: {
            Image(systemName: "arrow.down.doc")
              .accessibilityLabel(t("galaxyssi.screen_page.wechat_browser_save", "Save Loaded Article as PDF"))
          }
          .disabled(browser.loading || browser.saving)
        }
      }
    }
    .navigationViewStyle(.stack)
    .task { browser.load(url) }
    .onDisappear { browser.close() }
  }

  private struct BrowserSurface: UIViewRepresentable {
    let browser: GalaxySSIWeChatBrowserSession
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
  }
}

@MainActor
final class GalaxySSIWeChatBrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
  @Published private(set) var loading = true
  @Published private(set) var saving = false
  @Published private(set) var failed = false
  @Published private(set) var savedName: String?
  private var generation = UUID()
  private var closed = false

  lazy var webView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = self
    view.uiDelegate = self
    return view
  }()

  static func articleURL(_ value: String) -> URL? {
    let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard input.utf8.count <= 4_096, !input.contains(where: \.isWhitespace),
          let parts = URLComponents(string: input),
          let url = parts.url, allows(url, mainFrame: true),
          parts.path == "/s" || (parts.path.hasPrefix("/s/") && parts.path.count > 3)
    else { return nil }
    return url
  }

  static func allows(_ url: URL?, mainFrame: Bool) -> Bool {
    guard let url, url.scheme?.lowercased() == "https", url.port == nil,
          url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
    return mainFrame ? host == "mp.weixin.qq.com"
      : ["qq.com", "gtimg.com", "qpic.cn"].contains { host == $0 || host.hasSuffix("." + $0) }
  }

  func load(_ url: URL) {
    guard !closed else { return }
    let token = generation
    let rules = #"""
    [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
     {"trigger":{"url-filter":"^https://([a-zA-Z0-9-]+\\.)*(qq\\.com|gtimg\\.com|qpic\\.cn)/"},
      "action":{"type":"ignore-previous-rules"}}]
    """#
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "galaxyssi-wechat-article-v1",
      encodedContentRuleList: rules) { [weak self] list, _ in
      Task { @MainActor in
        guard let self, self.generation == token, !self.closed else { return }
        guard let list else { self.fail(); return }
        self.webView.configuration.userContentController.add(list)
        self.webView.load(URLRequest(url: url))
      }
    }
  }

  func close() {
    closed = true
    generation = UUID()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
  }

  func save() {
    guard !closed, !loading, !saving,
          let url = webView.url, Self.articleURL(url.absoluteString) != nil else { fail(); return }
    saving = true
    failed = false
    savedName = nil
    let token = generation
    let probe = #"""
    (() => {
      const article = document.getElementById('js_content');
      if (!article || (!article.innerText.trim() && !article.querySelector('img'))) return false;
      return document.readyState === 'complete';
    })()
    """#
    webView.evaluateJavaScript(probe) { [weak self] value, _ in
      guard let self, self.generation == token else { return }
      guard self.webView.url == url else { self.fail(); return }
      let size = self.webView.scrollView.contentSize
      guard value as? Bool == true, size.width > 0, size.width <= 2_048,
            size.height > 0, size.height <= 14_000 else { self.fail(); return }
      let configuration = WKPDFConfiguration()
      configuration.rect = CGRect(origin: .zero, size: size)
      self.webView.createPDF(configuration: configuration) { [weak self] result in
        guard let self, self.generation == token else { return }
        guard self.webView.url == url else { self.fail(); return }
        self.saving = false
        do {
          let pdf = try result.get()
          guard !pdf.isEmpty, pdf.count <= 32 * 1_024 * 1_024 else { self.fail(); return }
          let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
          let directory = root.appendingPathComponent("Downloads/GongZhongHao", isDirectory: true)
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let name = "article-\(UUID().uuidString.lowercased()).pdf"
          try pdf.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
          self.savedName = name
        } catch { self.fail() }
      }
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let frame = action.targetFrame else { decisionHandler(.cancel); return }
    decisionHandler(Self.allows(action.request.url, mainFrame: frame.isMainFrame) ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
               initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
               decisionHandler: @escaping (WKPermissionDecision) -> Void) {
    decisionHandler(.deny)
  }

  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    let mime = response.response.mimeType?.lowercased()
    let allowed = response.canShowMIMEType &&
      Self.allows(response.response.url, mainFrame: response.isForMainFrame) &&
      (!response.isForMainFrame || mime == "text/html" || mime == "application/xhtml+xml")
    decisionHandler(allowed ? .allow : .cancel)
    if !allowed && response.isForMainFrame { fail() }
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    generation = UUID()
    loading = true
    saving = false
    failed = false
    savedName = nil
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail() }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    fail()
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail() }

  private func fail() {
    generation = UUID()
    loading = false
    saving = false
    failed = true
  }
}

struct GalaxySSIWebPagePreviewView: View {
  let url: URL
  let title: String
  let fallbackText: String

  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var isLoading = true
  @State private var hasFailed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        Image(systemName: "safari")
          .foregroundColor(.galaxySSIAccent)
        Text(title.ifBlank(url.host ?? url.absoluteString))
          .font(.subheadline.weight(.semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
        Spacer(minLength: 8)
        Link(destination: url) {
          Image(systemName: "arrow.up.right.square")
            .font(.subheadline.weight(.semibold))
            .frame(width: 36, height: 36)
        }
        .accessibilityLabel(t("rich_output_open", "Open"))
      }

      ZStack {
        GalaxySSIWebPageView(
          url: url,
          onStart: {
            isLoading = true
            hasFailed = false
          },
          onFinish: {
            isLoading = false
          },
          onFailure: {
            isLoading = false
            hasFailed = true
          }
        )
        .id(url.absoluteString)

        if isLoading && !hasFailed {
          ProgressView()
            .padding(12)
            .background(Color.galaxySSISurface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityLabel(t("rich_output_loading", "Loading preview"))
        }

        if hasFailed {
          VStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
              .font(.title3)
              .foregroundColor(.orange)
            Text(t("rich_output_load_failed", "Unable to display preview"))
              .font(.caption)
              .foregroundColor(.galaxySSITextSecondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.galaxySSISearchBackground)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 420)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .stroke(Color.galaxySSISeparator, lineWidth: 0.5)
      )

      Text(fallbackText.ifBlank(url.absoluteString))
        .font(.caption2)
        .foregroundColor(.galaxySSITextSecondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIWebPageView: UIViewRepresentable {
  let url: URL
  let onStart: () -> Void
  let onFinish: () -> Void
  let onFailure: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onStart: onStart,
      onFinish: onFinish,
      onFailure: onFailure
    )
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.preferences.javaScriptEnabled = true
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.load(URLRequest(url: url))
    context.coordinator.loadedURL = url
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    context.coordinator.onStart = onStart
    context.coordinator.onFinish = onFinish
    context.coordinator.onFailure = onFailure
    guard context.coordinator.loadedURL != url else { return }
    context.coordinator.loadedURL = url
    webView.load(URLRequest(url: url))
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    var onStart: () -> Void
    var onFinish: () -> Void
    var onFailure: () -> Void
    var loadedURL: URL?

    init(
      onStart: @escaping () -> Void,
      onFinish: @escaping () -> Void,
      onFailure: @escaping () -> Void
    ) {
      self.onStart = onStart
      self.onFinish = onFinish
      self.onFailure = onFailure
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard let targetURL = navigationAction.request.url, Self.isAllowed(targetURL) else {
        decisionHandler(.cancel)
        return
      }
      if navigationAction.targetFrame == nil {
        webView.load(navigationAction.request)
        decisionHandler(.cancel)
        return
      }
      decisionHandler(.allow)
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationResponse: WKNavigationResponse,
      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
      guard !navigationResponse.isForMainFrame ||
        Self.isAllowed(navigationResponse.response.url) else {
        decisionHandler(.cancel)
        onFailure()
        return
      }
      decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      onStart()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      onFinish()
    }

    func webView(
      _ webView: WKWebView,
      didFail navigation: WKNavigation!,
      withError error: Error
    ) {
      onFailure()
    }

    func webView(
      _ webView: WKWebView,
      didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      onFailure()
    }

    private static func isAllowed(_ url: URL?) -> Bool {
      guard let url,
            url.scheme?.lowercased() == "https",
            url.host?.isEmpty == false else {
        return false
      }
      return true
    }
  }
}
