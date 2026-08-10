import WebKit

final class SignalASIRichHTMLPlaybackCoordinator {
  static let shared = SignalASIRichHTMLPlaybackCoordinator()

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
      let style = document.getElementById('signalasi-playback-pause');
      if (!style) {
        style = document.createElement('style');
        style.id = 'signalasi-playback-pause';
        style.textContent = '*,*::before,*::after{animation-play-state:paused!important}';
        document.documentElement.appendChild(style);
      }
      document.querySelectorAll('video,audio').forEach(media => {
        if (!media.paused) media.dataset.signalasiResume = '1';
        media.pause();
      });
    })()
    """

  private static let resumeScript = """
    (() => {
      document.getElementById('signalasi-playback-pause')?.remove();
      document.querySelectorAll('video,audio[data-signalasi-resume="1"]').forEach(media => {
        delete media.dataset.signalasiResume;
        media.play().catch(() => {});
      });
    })()
    """
}

final class SignalASIRichHTMLWebView: WKWebView {
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
