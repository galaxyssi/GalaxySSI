import SwiftUI
import UIKit

enum AgentDesktopDirectGesture {
  case click(CGPoint, width: Int, height: Int, right: Bool, count: Int)
  case scroll(Int)

  static func coordinate(_ point: CGPoint, in size: CGSize, width: Int, height: Int) -> CGPoint? {
    guard size.width > 0, size.height > 0, (1...32_768).contains(width), (1...32_768).contains(height),
          point.x.isFinite, point.y.isFinite else { return nil }
    let scale = min(size.width / CGFloat(width), size.height / CGFloat(height))
    guard scale.isFinite, scale > 0 else { return nil }
    let rect = CGRect(x: (size.width - CGFloat(width) * scale) / 2,
      y: (size.height - CGFloat(height) * scale) / 2,
      width: CGFloat(width) * scale, height: CGFloat(height) * scale)
    guard rect.contains(point) else { return nil }
    return CGPoint(x: min(CGFloat(width - 1), floor((point.x - rect.minX) / scale)),
      y: min(CGFloat(height - 1), floor((point.y - rect.minY) / scale)))
  }
}

struct AgentDesktopDraft: Equatable {
  private(set) var text = ""
  private(set) var revision: UInt64 = 0

  mutating func edit(_ value: String) {
    guard value != text else { return }
    text = value
    revision &+= 1
  }

  mutating func confirm(_ submittedRevision: UInt64) {
    if revision == submittedRevision { edit("") }
  }
}

struct GalaxySSIDesktopDirectInputView: View {
  private struct PendingInput {
    let id: String
    let revision: UInt64?
    let opensKeyboard: Bool
  }

  let link: ServerLink
  let startWithKeyboard: Bool
  let t: (String, String) -> String
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.scenePhase) private var phase
  @Environment(\.dismiss) private var dismiss
  @FocusState private var keyboardFocused: Bool
  @StateObject private var voice = GalaxySSIAgentHoldToTalkController()
  @State private var frame: AgentDesktopControlScreenshot?
  @State private var pendingFrame: (id: String, deadline: Int64)?
  @State private var frameMessage = ""
  @State private var draft = AgentDesktopDraft()
  @State private var keyboardOpen = false
  @State private var voiceMode = false
  @State private var inputTarget: String?
  @State private var targetSelected = false
  @State private var inputMessage = ""
  @State private var pending: PendingInput?
  @State private var queued: [AgentDesktopDirectGesture] = []
  @State private var inputTask: Task<Void, Never>?
  @State private var captureGeneration = UUID()
  @State private var authorizationRequestedAt: Int64 = 0

  private var now: Int64 { AgentControlPlaneClock.nowMillis() }
  private var activeLink: ServerLink? {
    store.serverLinks.first { $0.paired && $0.fullDesktopExecutor && $0.desktopId == link.desktopId &&
      $0.desktopFingerprint == link.desktopFingerprint && $0.routes.clientRouteId == link.routes.clientRouteId }
  }
  private var snapshot: AgentDesktopRemoteControlSnapshot { coordinator.desktopControlSnapshot(for: link) }
  private var sessionId: String { snapshot.currentAuthorization?.desktopSessionId ?? "" }
  private var inputAllowed: Bool {
    phase == .active && activeLink != nil && coordinator.mqttClient.isConnected && snapshot.authorized &&
      !sessionId.isBlank && (snapshot.currentAuthorization?.desktopSessionExpiresAt ?? 0) > now
  }
  private var routing: AgentDesktopControlRequestRoutingContext {
    .init(clientRouteId: link.routes.clientRouteId, controllerFingerprint: store.profile.identityFingerprint,
      controllerSignalName: store.profile.galaxySSIId)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      ZStack {
        Color.black
        if let frame {
          GalaxySSIDesktopTouchSurface(frame: frame, enabled: inputAllowed && frameMessage.isEmpty,
            onGesture: receiveGesture)
            .accessibilityLabel(t("desktop_control_screen_content_description", "Encrypted desktop screenshot"))
        } else {
          Text(frameMessage.ifBlank(t("desktop_control_direct_waiting", "Waiting for the remote screen")))
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .padding(16)
        }
      }
      .privacySensitive()
      if frame != nil, !frameMessage.isEmpty {
        Text(frameMessage).font(.footnote).foregroundColor(.secondary).padding(6)
      }
      if !inputMessage.isEmpty {
        Text(inputMessage).font(.footnote).foregroundColor(.secondary).padding(6)
      }
      if keyboardOpen { composer }
    }
    .background(Color.galaxySSIPageBackground)
    .onAppear { if startWithKeyboard { openKeyboard(target: nil) } }
    .onDisappear(perform: reset)
    .onChange(of: phase) { if $0 != .active { reset() } }
    .onChange(of: sessionId) { previousSessionChanged(to: $0) }
    .onChange(of: snapshot.authorized) { if !$0 { reset() } }
    .onChange(of: snapshot.surfaceCatalog?.selection) { _ in previousSessionChanged(to: sessionId) }
    .onChange(of: activeLink == nil) { if $0 { reset(); dismiss() } }
    .onChange(of: coordinator.mqttClient.isConnected) { if !$0 { reset() } }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in reset() }
    .onReceive(coordinator.desktopInteractiveReceipts, perform: receiveReceipt)
    .onReceive(coordinator.desktopDirectFrameReceipts, perform: receiveFrame)
    .task(id: phase) {
      guard phase == .active else { return }
      await runPreview()
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Button(action: { reset(); dismiss() }) {
        Image(systemName: "chevron.left").frame(width: 44, height: 44)
      }
      .accessibilityLabel(t("galaxyssi.common.back", "Back"))
      Text(link.desktopName.ifBlank(t("desktop_control_title", "Control Computer")))
        .font(.headline).lineLimit(1)
      Spacer(minLength: 4)
      Menu {
        Button { openKeyboard(target: nil) } label: {
          Label(t("desktop_control_type_text", "Type text"), systemImage: "keyboard")
        }
        Button { sendHotkey(["Escape"]) } label: {
          Label(t("desktop_control_direct_escape", "Escape"), systemImage: "escape")
        }
      } label: {
        Image(systemName: "ellipsis").frame(width: 44, height: 44)
      }
      .accessibilityLabel(t("galaxyssi.common.more", "More"))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 8)
  }

  private var composer: some View {
    VStack(spacing: 6) {
      HStack(alignment: .bottom, spacing: 8) {
        Button {
          if voiceMode { voice.clearRuntimePlaintext() }
          voiceMode.toggle()
          keyboardFocused = !voiceMode
        } label: {
          Image(systemName: voiceMode ? "keyboard" : "waveform").frame(width: 44, height: 44)
        }
        .accessibilityLabel(voiceMode ? t("desktop_control_type_text", "Type text") :
          t("desktop_control_direct_voice", "Voice input"))
        if voiceMode {
          voiceButton
        } else {
          TextEditor(text: Binding(get: { draft.text }, set: { draft.edit($0) }))
            .focused($keyboardFocused)
            .onAppear { keyboardFocused = true }
            .frame(height: min(164, max(44, CGFloat(draft.text.split(separator: "\n",
              omittingEmptySubsequences: false).count) * 20 + 16)))
            .accessibilityLabel(t("desktop_control_type_text_placeholder", "Text to type"))
        }
        Button(action: submitDraft) {
          Image(systemName: "arrow.up.circle.fill").font(.title2).frame(width: 44, height: 44)
        }
        .accessibilityLabel(t("galaxyssi.common.send", "Send"))
        .disabled(!inputAllowed || !targetSelected || pending != nil || draft.text.isBlank || draft.text.utf16.count > 4_096)
        Button(action: closeKeyboard) {
          Image(systemName: "xmark").frame(width: 44, height: 44)
        }
        .accessibilityLabel(t("galaxyssi.common.close", "Close"))
      }
      if voiceMode, !voice.statusMessage.isEmpty {
        Text(voice.statusMessage).font(.footnote).foregroundColor(.secondary)
      }
    }
    .buttonStyle(.plain)
    .padding(8)
    .background(Color.galaxySSIBarBackground)
    .privacySensitive()
  }

  private var voiceButton: some View {
    let generation = captureGeneration
    return Text(voice.isRecording ? voice.elapsedLabel : t("desktop_control_direct_hold", "Hold to speak"))
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(Color.galaxySSISurface, in: RoundedRectangle(cornerRadius: 8))
      .gesture(DragGesture(minimumDistance: 0)
        .onChanged { value in
          guard inputAllowed else { return }
          voice.dragChanged(translation: value.translation, settings: localVoiceSettings, messages: .default,
            onStart: {}, onFinish: { result in
              guard generation == captureGeneration, keyboardOpen, inputAllowed, !result.text.isBlank else { return }
              let combined = draft.text.isEmpty ? result.text : draft.text + " " + result.text
              guard combined.utf16.count <= 4_096 else { return }
              draft.edit(combined)
              voiceMode = false
              keyboardFocused = true
            }, onCancel: {})
        }
        .onEnded { voice.dragEnded(translation: $0.translation) })
  }

  private var localVoiceSettings: VoiceSettings {
    var value = store.voiceSettings
    value.asrProvider = .localWhisperCpp
    value.asrRecognitionPreference = .localPrivate
    value.onlineAsrAllowed = false
    value.onlineAsrAudioUploadAllowed = false
    value.remoteWhisperAllowed = false
    value.autoSendTranscripts = false
    return value
  }

  private func openKeyboard(target: String?) {
    inputTarget = target
    targetSelected = true
    keyboardOpen = true
    voiceMode = false
    keyboardFocused = true
  }

  private func closeKeyboard() {
    captureGeneration = UUID()
    voice.clearRuntimePlaintext()
    keyboardFocused = false
    keyboardOpen = false
    voiceMode = false
    draft.edit("")
    inputTarget = nil
    targetSelected = false
  }

  private func receiveGesture(_ gesture: AgentDesktopDirectGesture) {
    guard inputAllowed, frame != nil, frameMessage.isEmpty, !voice.isRecording, !voice.isPending else { return }
    if pending != nil {
      if queued.count < 8 { queued.append(gesture) }
      return
    }
    dispatchGesture(gesture)
  }

  private func dispatchGesture(_ gesture: AgentDesktopDirectGesture) {
    guard let frame, frameMessage.isEmpty else { queued.removeAll(); return }
    switch gesture {
    case let .click(point, width, height, right, count):
      guard width == frame.width, height == frame.height else {
        queued.removeAll()
        return
      }
      inputTarget = nil
      targetSelected = false
      startInput(AgentDesktopControlRequestFactory.click(snapshot: snapshot, routing: routing,
        x: Int(point.x), y: Int(point.y), coordinateWidth: width, coordinateHeight: height,
        interactive: true, button: right ? "right" : "left", clicks: count, nowMillis: now),
        opensKeyboard: !right)
    case .scroll(let delta):
      startInput(AgentDesktopControlRequestFactory.scroll(snapshot: snapshot, routing: routing,
        delta: delta, interactive: true, nowMillis: now))
    }
  }

  private func sendHotkey(_ keys: [String]) {
    startInput(AgentDesktopControlRequestFactory.hotkey(snapshot: snapshot, routing: routing,
      keys: keys, interactive: true, targetId: inputTarget, nowMillis: now))
  }

  private func submitDraft() {
    guard targetSelected else { return }
    startInput(AgentDesktopControlRequestFactory.typeText(snapshot: snapshot, routing: routing,
      text: draft.text, interactive: true, targetId: inputTarget, nowMillis: now), revision: draft.revision)
  }

  private func startInput(_ request: AgentDesktopControlActionRequest?, revision: UInt64? = nil,
                          opensKeyboard: Bool = false) {
    guard inputAllowed, let activeLink, pending == nil, let request else { return }
    let id = request.actionId
    pending = .init(id: id, revision: revision, opensKeyboard: opensKeyboard)
    inputMessage = ""
    inputTask = Task { @MainActor in
      guard await coordinator.sendDesktopControl(request, link: activeLink) else {
        if !Task.isCancelled { failInput(id: id) }
        return
      }
      do { try await Task.sleep(nanoseconds: UInt64(max(1, request.expiresAt - now)) * 1_000_000) }
      catch { return }
      failInput(id: id)
    }
  }

  private func failInput(id: String) {
    guard pending?.id == id else { return }
    coordinator.forgetDesktopInteractiveInput(id, desktopId: link.desktopId)
    pending = nil
    queued.removeAll()
    inputMessage = t("desktop_control_direct_unconfirmed", "Input not confirmed. Check the computer before retrying.")
  }

  private func receiveReceipt(_ event: AgentDesktopInteractiveReceipt) {
    guard inputAllowed, event.desktopId == link.desktopId, let pending,
          event.receipt.actionId == pending.id, event.receipt.desktopSessionId == sessionId else { return }
    inputTask?.cancel()
    if event.receipt.status != "succeeded" {
      failInput(id: pending.id)
      if event.receipt.errorCode == "input_focus_changed" {
        inputTarget = nil
        targetSelected = false
        inputMessage = t("desktop_control_direct_focus_changed", "Remote focus changed. Select the field again.")
      }
      return
    }
    self.pending = nil
    if let revision = pending.revision { draft.confirm(revision) }
    if !queued.isEmpty {
      let next = queued.removeFirst()
      dispatchGesture(next)
    } else if pending.opensKeyboard, let focus = event.focus, focus.canBindText {
      openKeyboard(target: focus.targetId)
    }
  }

  private func previousSessionChanged(to value: String) {
    let preserveEmptyEditor = keyboardOpen && draft.text.isEmpty && inputTarget == nil
    reset()
    if preserveEmptyEditor && !value.isEmpty { openKeyboard(target: nil) }
  }

  private func runPreview() async {
    while !Task.isCancelled, phase == .active {
      if let activeLink, coordinator.mqttClient.isConnected {
        if let pendingFrame, now >= pendingFrame.deadline {
          coordinator.forgetDesktopInteractiveInput(pendingFrame.id, desktopId: link.desktopId)
          self.pendingFrame = nil
          frameMessage = t("desktop_control_direct_frame_failed", "Remote frame unavailable")
        }
        if inputAllowed, pendingFrame == nil {
          let id = AgentDesktopControlRequestFactory.directFramePrefix + UUID().uuidString
          if let request = AgentDesktopControlRequestFactory.screenshotStreamFrame(snapshot: snapshot, routing: routing,
            fps: 1, actionId: id, nowMillis: now) {
            pendingFrame = (id, request.expiresAt)
            if !(await coordinator.sendDesktopControl(request, link: activeLink)), pendingFrame?.id == id {
              pendingFrame = nil
              frameMessage = t("desktop_control_direct_frame_failed", "Remote frame unavailable")
            }
          }
        } else if !inputAllowed, now - authorizationRequestedAt >= 4_000 {
          authorizationRequestedAt = now
          frameMessage = t("desktop_control_request_unavailable", "Desktop session unavailable")
          _ = await coordinator.requestDirectDesktopAuthorization(activeLink)
        }
      } else {
        frameMessage = t("galaxyssi.status.disconnected", "Disconnected")
      }
      do { try await Task.sleep(nanoseconds: 1_000_000_000) }
      catch { return }
    }
  }

  private func receiveFrame(_ event: AgentDesktopDirectFrameReceipt) {
    guard inputAllowed, event.receipt.actionId == pendingFrame?.id,
          event.receipt.desktopSessionId == sessionId else { return }
    pendingFrame = nil
    if let screenshot = event.screenshot {
      frame = screenshot
      frameMessage = ""
    } else {
      frameMessage = t("desktop_control_direct_frame_failed", "Remote frame unavailable")
    }
  }

  private func reset() {
    inputTask?.cancel()
    inputTask = nil
    if let pending { coordinator.forgetDesktopInteractiveInput(pending.id, desktopId: link.desktopId) }
    if let pendingFrame { coordinator.forgetDesktopInteractiveInput(pendingFrame.id, desktopId: link.desktopId) }
    pending = nil
    pendingFrame = nil
    queued.removeAll()
    frame = nil
    frameMessage = ""
    inputMessage = ""
    closeKeyboard()
  }
}

private struct GalaxySSIDesktopTouchSurface: UIViewRepresentable {
  let frame: AgentDesktopControlScreenshot
  let enabled: Bool
  let onGesture: (AgentDesktopDirectGesture) -> Void

  func makeUIView(context: Context) -> TouchView { TouchView() }

  func updateUIView(_ view: TouchView, context: Context) {
    view.onGesture = enabled ? onGesture : nil
    if view.frameData != frame {
      view.frameData = frame
      view.image.image = UIImage(data: frame.jpegBytes)
    }
  }

  final class TouchView: UIScrollView, UIScrollViewDelegate {
    private final class WheelDelegate: NSObject, UIGestureRecognizerDelegate {
      weak var pinch: UIGestureRecognizer?

      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer === pinch
      }
    }

    let image = UIImageView()
    var frameData: AgentDesktopControlScreenshot?
    var onGesture: ((AgentDesktopDirectGesture) -> Void)?
    private var previousSize = CGSize.zero
    private var twoFingerStartZoom: CGFloat = 1
    private let wheelDelegate = WheelDelegate()

    init() {
      super.init(frame: .zero)
      delegate = self
      minimumZoomScale = 1
      maximumZoomScale = 4
      contentInsetAdjustmentBehavior = .never
      image.contentMode = .scaleAspectFit
      addSubview(image)
      panGestureRecognizer.maximumNumberOfTouches = 1
      panGestureRecognizer.isEnabled = false
      let single = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
      let double = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
      double.numberOfTapsRequired = 2
      let long = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
      single.require(toFail: double)
      single.require(toFail: long)
      double.require(toFail: long)
      let wheel = UIPanGestureRecognizer(target: self, action: #selector(scrollRemotely(_:)))
      wheel.minimumNumberOfTouches = 2
      wheel.maximumNumberOfTouches = 2
      wheelDelegate.pinch = pinchGestureRecognizer
      wheel.delegate = wheelDelegate
      [single, double, long, wheel].forEach(addGestureRecognizer)
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
      super.layoutSubviews()
      if previousSize != bounds.size {
        previousSize = bounds.size
        setZoomScale(1, animated: false)
        image.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
      }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      panGestureRecognizer.isEnabled = zoomScale > 1.01
    }

    @objc private func tap(_ recognizer: UITapGestureRecognizer) {
      click(recognizer, right: false, count: recognizer.numberOfTapsRequired)
    }

    @objc private func longPress(_ recognizer: UILongPressGestureRecognizer) {
      if recognizer.state == .began { click(recognizer, right: true, count: 1) }
    }

    private func click(_ recognizer: UIGestureRecognizer, right: Bool, count: Int) {
      guard image.image != nil, let frameData,
            let point = AgentDesktopDirectGesture.coordinate(recognizer.location(in: image),
              in: image.bounds.size, width: frameData.width, height: frameData.height) else { return }
      onGesture?(.click(point, width: frameData.width, height: frameData.height, right: right, count: count))
    }

    @objc private func scrollRemotely(_ recognizer: UIPanGestureRecognizer) {
      if recognizer.state == .began { twoFingerStartZoom = zoomScale }
      guard recognizer.state == .ended, abs(zoomScale - twoFingerStartZoom) < 0.04 else { return }
      let movement = recognizer.translation(in: self)
      guard abs(movement.y) >= 16, abs(movement.y) > abs(movement.x) else { return }
      let ticks = min(10, max(1, Int(abs(movement.y) / 24)))
      onGesture?(.scroll(ticks * (movement.y > 0 ? -120 : 120)))
    }
  }
}
