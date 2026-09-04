import WebKit

final class GalaxySSIRichHTMLPlaybackCoordinator {
  static let shared = GalaxySSIRichHTMLPlaybackCoordinator()

  private weak var activeWebView: WKWebView?

  private init() {}

  func activate(_ webView: WKWebView) {
    if let activeWebView, activeWebView !== webView {
      pause(activeWebView)
    }
    activeWebView = webView
    resume(webView)
  }

  func sync(_ webView: WKWebView) {
    guard activeWebView === webView else {
      pause(webView)
      return
    }
    resume(webView)
  }

  func deactivate(_ webView: WKWebView) {
    pause(webView)
    if activeWebView === webView {
      activeWebView = nil
    }
  }

  private func pause(_ webView: WKWebView) {
    webView.evaluateJavaScript(Self.pauseScript, completionHandler: nil)
  }

  private func resume(_ webView: WKWebView) {
    webView.evaluateJavaScript(Self.resumeScript, completionHandler: nil)
  }

  private static let pauseScript = """
    (() => {
      let style = document.getElementById('galaxyssi-playback-pause');
      if (!style) {
        style = document.createElement('style');
        style.id = 'galaxyssi-playback-pause';
        style.textContent = '*,*::before,*::after{animation-play-state:paused!important}';
        document.documentElement.appendChild(style);
      }
      document.querySelectorAll('video,audio').forEach(media => {
        if (!media.paused) media.dataset.galaxyssiResume = '1';
        media.pause();
      });
    })()
    """

  private static let resumeScript = """
    (() => {
      document.getElementById('galaxyssi-playback-pause')?.remove();
      document.querySelectorAll('video,audio[data-galaxyssi-resume="1"]').forEach(media => {
        delete media.dataset.galaxyssiResume;
        media.play().catch(() => {});
      });
    })()
    """
}

final class GalaxySSIRichHTMLWebView: WKWebView {
  var onFocus: (() -> Void)?
  var onDetach: (() -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      onDetach?()
    } else {
      onFocus?()
    }
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    onFocus?()
    super.touchesBegan(touches, with: event)
  }
}
