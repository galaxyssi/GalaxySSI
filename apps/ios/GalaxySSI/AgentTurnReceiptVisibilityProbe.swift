import SwiftUI
import UIKit

struct AgentTurnReceiptVisibilityProbe: UIViewRepresentable {
  let observe: () -> Bool
  let painted: () -> Void
  func makeUIView(context: Context) -> Probe { Probe() }
  func updateUIView(_ view: Probe, context: Context) {
    view.observe = observe; view.painted = painted; view.start()
  }
  static func dismantleUIView(_ view: Probe, coordinator: ()) { view.stop(); view.observe = nil; view.painted = nil }

  final class Probe: UIView {
    var observe: (() -> Bool)?
    var painted: (() -> Void)?
    private var link: CADisplayLink?
    private var drawnAt: CFTimeInterval?
    private var visibleAt: CFTimeInterval?
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; isUserInteractionEnabled = false; accessibilityElementsHidden = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func draw(_ rect: CGRect) { super.draw(rect); if drawnAt == nil { drawnAt = CACurrentMediaTime() } }
    override func didMoveToWindow() {
      super.didMoveToWindow(); drawnAt = nil; visibleAt = nil
      if window == nil { stop() } else { start() }
    }
    func start() {
      guard link == nil, window != nil, observe?() == true else { return }
      setNeedsDisplay()
      let value = CADisplayLink(target: self, selector: #selector(framePresented(_:)))
      value.preferredFramesPerSecond = 30
      value.add(to: .main, forMode: .common); link = value
    }
    func stop() { link?.invalidate(); link = nil }
    @objc private func framePresented(_ frame: CADisplayLink) {
      guard observe?() == true else { stop(); return }
      guard let window, window.isKeyWindow, window.windowScene?.activationState == .foregroundActive,
            let drawnAt, frame.timestamp > drawnAt else { visibleAt = nil; return }
      var visible = convert(bounds, to: window).intersection(window.bounds)
      var parent: UIView? = self
      while let current = parent {
        guard !current.isHidden, current.alpha > 0.01 else { visibleAt = nil; return }
        if current.clipsToBounds { visible = visible.intersection(current.convert(current.bounds, to: window)) }
        parent = current.superview
      }
      guard !visible.isNull, visible.width > 1, visible.height > 1 else { visibleAt = nil; return }
      guard let visibleAt, frame.timestamp > visibleAt else { self.visibleAt = frame.timestamp; return }
      painted?(); stop()
    }
  }
}

enum AgentTurnReceiptBodyPolicy {
  static func eligible(_ message: ChatMessage) -> Bool {
    !message.isMine && !message.isSystem && !message.content.isBlank && message.deliveryStatus != .failed &&
      !CloudSupervisedResearch.isTranscriptControlReply(message) &&
      !message.remoteMessageId.hasPrefix("agent-stream-preview-") &&
      !message.deliveryTrace.contains { $0.stage.hasPrefix("delivery-failed:") }
  }
}
