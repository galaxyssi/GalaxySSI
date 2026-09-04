import SwiftUI
import UIKit
import WebKit

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
