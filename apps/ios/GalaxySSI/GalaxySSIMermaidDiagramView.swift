import SwiftUI
import UIKit
import WebKit

struct GalaxySSIMermaidDiagramView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  let source: String
  let title: String

  @State private var renderState = MermaidRenderState.loading
  @State private var snapshotRequest = 0
  @State private var sharedFile: MermaidSharedFile?
  @State private var showsFullscreen = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "rectangle.3.group")
          .font(.caption.weight(.semibold))
          .foregroundColor(.galaxySSIAccent)
          .accessibilityHidden(true)
        Text(title.ifBlank(t("rich_output_diagram", "Diagram")))
          .font(.caption.weight(.semibold))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(1)
        Spacer(minLength: 8)
        diagramButton(
          systemName: "square.and.arrow.down",
          label: t("rich_output_diagram_save", "Save diagram")
        ) {
          snapshotRequest += 1
        }
        .disabled(renderState != .ready)
        diagramButton(
          systemName: "arrow.up.left.and.arrow.down.right",
          label: t("rich_output_diagram_open", "Open diagram full screen")
        ) {
          showsFullscreen = true
        }
      }
      .padding(.horizontal, 10)
      .frame(height: 42)

      ZStack {
        GalaxySSIMermaidWebView(
          source: source,
          darkMode: colorScheme == .dark,
          snapshotRequest: snapshotRequest,
          onRenderState: { renderState = $0 },
          onSnapshot: receiveSnapshot
        )
        if renderState == .loading {
          ProgressView()
        } else if renderState == .failed {
          MermaidFailureView()
        }
      }
      .aspectRatio(1.0 / 1.2, contentMode: .fit)
      .frame(maxWidth: .infinity)
      .background(Color.galaxySSISurface)
    }
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.galaxySSISeparator, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .sheet(item: $sharedFile) { item in
      MermaidActivitySheet(items: [item.url])
    }
    .fullScreenCover(isPresented: $showsFullscreen) {
      GalaxySSIMermaidFullscreenView(source: source, title: title)
    }
  }

  private func diagramButton(
    systemName: String,
    label: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 14, weight: .semibold))
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundColor(.galaxySSITextSecondary)
    .accessibilityLabel(label)
  }

  private func receiveSnapshot(_ result: Result<URL, Error>) {
    if case .success(let url) = result {
      sharedFile = MermaidSharedFile(url: url)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIMermaidFullscreenView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  let source: String
  let title: String

  @State private var renderState = MermaidRenderState.loading
  @State private var snapshotRequest = 0
  @State private var sharedFile: MermaidSharedFile?

  var body: some View {
    NavigationView {
      ZStack {
        Color.galaxySSISurface.ignoresSafeArea()
        GalaxySSIMermaidWebView(
          source: source,
          darkMode: colorScheme == .dark,
          snapshotRequest: snapshotRequest,
          onRenderState: { renderState = $0 },
          onSnapshot: { result in
            if case .success(let url) = result {
              sharedFile = MermaidSharedFile(url: url)
            }
          }
        )
        if renderState == .loading {
          ProgressView()
        } else if renderState == .failed {
          MermaidFailureView()
        }
      }
      .navigationTitle(title.ifBlank(t("rich_output_diagram", "Diagram")))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button { dismiss() } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel(t("common_close", "Close"))
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button { snapshotRequest += 1 } label: {
            Image(systemName: "square.and.arrow.down")
          }
          .disabled(renderState != .ready)
          .accessibilityLabel(t("rich_output_diagram_save", "Save diagram"))
        }
      }
    }
    .navigationViewStyle(.stack)
    .sheet(item: $sharedFile) { item in
      MermaidActivitySheet(items: [item.url])
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct MermaidFailureView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle")
        .font(.title2)
      Text(GalaxySSILocalization.string(
        "rich_output_diagram_failed",
        fallback: "Could not render this diagram",
        language: interfaceLanguage
      ))
      .font(.caption)
      .multilineTextAlignment(.center)
    }
    .foregroundColor(.galaxySSITextSecondary)
    .padding(16)
  }
}

private enum MermaidRenderState: Equatable {
  case loading
  case ready
  case failed
}

private struct MermaidSharedFile: Identifiable {
  let id = UUID()
  let url: URL
}

private struct MermaidActivitySheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct GalaxySSIMermaidWebView: UIViewRepresentable {
  let source: String
  let darkMode: Bool
  let snapshotRequest: Int
  let onRenderState: (MermaidRenderState) -> Void
  let onSnapshot: (Result<URL, Error>) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.userContentController.add(context.coordinator, name: Coordinator.messageName)

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.scrollView.bouncesZoom = true
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.scrollView.alwaysBounceHorizontal = false
    webView.scrollView.alwaysBounceVertical = false
    context.coordinator.webView = webView
    context.coordinator.load(source: source, darkMode: darkMode)
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    context.coordinator.parent = self
    if context.coordinator.loadedSource != source || context.coordinator.loadedDarkMode != darkMode {
      context.coordinator.load(source: source, darkMode: darkMode)
    }
    if context.coordinator.snapshotRequest != snapshotRequest {
      context.coordinator.snapshotRequest = snapshotRequest
      context.coordinator.snapshot()
    }
  }

  static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
    webView.stopLoading()
    webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageName)
  }

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let messageName = "galaxyssiMermaid"

    var parent: GalaxySSIMermaidWebView
    weak var webView: WKWebView?
    var loadedSource = ""
    var loadedDarkMode = false
    var snapshotRequest = 0

    init(parent: GalaxySSIMermaidWebView) {
      self.parent = parent
    }

    func load(source: String, darkMode: Bool) {
      loadedSource = source
      loadedDarkMode = darkMode
      parent.onRenderState(.loading)
      guard let libraryURL = Bundle.main.url(
        forResource: "mermaid.min",
        withExtension: "js",
        subdirectory: "mermaid"
      ) else {
        parent.onRenderState(.failed)
        return
      }
      webView?.loadHTMLString(
        Self.document(source: String(source.prefix(32_000)), darkMode: darkMode),
        baseURL: libraryURL.deletingLastPathComponent()
      )
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      guard message.name == Self.messageName, let value = message.body as? String else { return }
      parent.onRenderState(value == "ready" ? .ready : .failed)
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
      let allowed = navigationAction.navigationType == .other && ["", "about", "file"].contains(scheme)
      decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(
      _ webView: WKWebView,
      createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction,
      windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      parent.onRenderState(.failed)
    }

    func snapshot() {
      guard let webView, webView.bounds.width > 0, webView.bounds.height > 0 else {
        parent.onSnapshot(.failure(GalaxySSIError.invalidPayload("Diagram preview is unavailable.")))
        return
      }
      let configuration = WKSnapshotConfiguration()
      configuration.afterScreenUpdates = true
      webView.takeSnapshot(with: configuration) { [weak self] image, error in
        guard let self else { return }
        do {
          if let error { throw error }
          guard let data = image?.pngData() else {
            throw GalaxySSIError.invalidPayload("Diagram snapshot could not be encoded.")
          }
          let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("galaxyssi-mermaid", isDirectory: true)
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let url = directory.appendingPathComponent("GalaxySSI-diagram-\(UUID().uuidString).png")
          try data.write(to: url, options: .atomic)
          self.parent.onSnapshot(.success(url))
        } catch {
          self.parent.onSnapshot(.failure(error))
        }
      }
    }

    private static func document(source: String, darkMode: Bool) -> String {
      let theme = darkMode ? "dark" : "default"
      let foreground = darkMode ? "#F3F5F7" : "#14202B"
      let background = darkMode ? "#101418" : "#FFFFFF"
      return """
      <!doctype html>
      <html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=8,user-scalable=yes">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self' 'unsafe-inline' file:; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; media-src 'none'; font-src data:; form-action 'none'; base-uri 'none'">
          <style>
            html,body{margin:0;width:100%;height:100%;overflow:auto;background:\(background);color:\(foreground);font-family:-apple-system,BlinkMacSystemFont,sans-serif;touch-action:pan-x pan-y pinch-zoom}
            body{display:flex;align-items:center;justify-content:center;padding:16px}
            #diagram{min-width:100%;min-height:100%;display:flex;align-items:center;justify-content:center}
            #diagram svg{display:block;max-width:100%;height:auto}
            #source{display:none}
          </style>
          <script src="mermaid.min.js"></script>
        </head>
        <body>
          <pre id="source">\(escapeHTML(source))</pre>
          <div id="diagram"></div>
          <script>
            (() => {
              const notify = value => window.webkit.messageHandlers.galaxyssiMermaid.postMessage(value);
              try {
                mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme:'\(theme)',suppressErrorRendering:true});
                mermaid.render('galaxyssi-diagram', document.getElementById('source').textContent)
                  .then(result => {
                    const host = document.getElementById('diagram');
                    host.innerHTML = result.svg;
                    const svg = host.querySelector('svg');
                    if (svg) { svg.removeAttribute('width'); svg.removeAttribute('height'); }
                    notify('ready');
                  })
                  .catch(() => notify('failed'));
              } catch (_) { notify('failed'); }
            })();
          </script>
        </body>
      </html>
      """
    }

    private static func escapeHTML(_ value: String) -> String {
      value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
    }
  }
}
