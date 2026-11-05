import SwiftUI
import UIKit

enum GalaxySSIScreenAssistantCapture: Equatable {
  case noWindow
  case clear
  case captured
}

enum GalaxySSIScreenAssistantAvailability: Equatable {
  case disabled
  case inactive
  case waitingForWindow
  case screenCaptured
  case available

  static func resolve(
    enabled: Bool, foreground: Bool, capture: GalaxySSIScreenAssistantCapture
  ) -> Self {
    guard enabled else { return .disabled }
    guard foreground else { return .inactive }
    switch capture {
    case .noWindow: return .waitingForWindow
    case .captured: return .screenCaptured
    case .clear: return .available
    }
  }

  func showsLauncher(onAgentHome: Bool, sourcePickerPresented: Bool) -> Bool {
    self == .available && onAgentHome && !sourcePickerPresented
  }
}

struct GalaxySSIScreenCaptureProbe: UIViewRepresentable {
  @Binding var capture: GalaxySSIScreenAssistantCapture

  func makeUIView(context: Context) -> CaptureView { CaptureView(frame: .zero) }

  func updateUIView(_ view: CaptureView, context: Context) {
    view.changed = { state in
      if capture != state { capture = state }
    }
    view.report()
  }

  static func dismantleUIView(_ view: CaptureView, coordinator: ()) {
    view.changed = nil
    view.stopObserving()
  }

  final class CaptureView: UIView {
    var changed: ((GalaxySSIScreenAssistantCapture) -> Void)?
    private var observer: NSObjectProtocol?
    private var reportQueued = false

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      stopObserving()
      if window != nil {
        observer = NotificationCenter.default.addObserver(
          forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.report() }
      }
      report()
    }

    func stopObserving() {
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
    }

    func report() {
      guard !reportQueued else { return }
      reportQueued = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.reportQueued = false
        let screen = self.window?.windowScene?.screen
        self.changed?(screen.map { $0.isCaptured ? .captured : .clear } ?? .noWindow)
      }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
  }
}
