import AVFoundation
import Combine
import MediaPlayer
import UIKit

extension Notification.Name {
  static let galaxySSIVoiceRecordingWillStart = Notification.Name("galaxyssi.voice_recording_will_start")
}

@MainActor
final class AgentCompletedReplyPlayback: ObservableObject {
  static let shared = AgentCompletedReplyPlayback()

  enum Phase { case idle, preparing, playing, paused }
  @Published private(set) var selection: AgentCompletedReplyPlaybackSelection?
  @Published private(set) var phase = Phase.idle
  @Published private(set) var lastErrorDescription = ""
  @Published private(set) var failedMessageID: UUID?

  private lazy var speech = VoiceProgressiveReplySpeechService()
  private var loadTask: Task<Void, Never>?
  private var sessionID = ""
  private var ownsAudioSession = false
  private var commands: [(command: MPRemoteCommand, target: Any, wasEnabled: Bool)] = []
  private var observations = Set<AnyCancellable>()

  private init() {
    let center = NotificationCenter.default
    center.publisher(for: .galaxySSIVoiceRecordingWillStart)
      .sink { [weak self] _ in
        if Thread.isMainThread { MainActor.assumeIsolated { self?.stop() } }
        else { DispatchQueue.main.sync { self?.stop() } }
      }.store(in: &observations)
    center.publisher(for: UIApplication.willResignActiveNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        if self?.phase == .preparing { self?.stop() }
      }.store(in: &observations)
    center.publisher(for: AVAudioSession.interruptionNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] notification in
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        if self?.phase == .preparing { self?.stop() }
        else { self?.pause() }
      }.store(in: &observations)
    center.publisher(for: AVAudioSession.routeChangeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] notification in
        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.stop() }
      }.store(in: &observations)
    center.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.stop() }.store(in: &observations)
  }

  func play(
    _ selection: AgentCompletedReplyPlaybackSelection,
    database: GalaxySSIChatHistoryDatabase,
    settings: VoiceSettings,
    languagePolicy: LanguagePolicySettings,
    isAllowed: @escaping () -> Bool
  ) {
    stop()
    lastErrorDescription = ""
    failedMessageID = nil
    guard settings.textToSpeechEnabled, isAllowed(), UIApplication.shared.applicationState == .active else { return }
    let id = UUID().uuidString
    sessionID = id
    self.selection = selection
    phase = .preparing
    loadTask = Task { [weak self] in
      let text = await Task.detached(priority: .userInitiated) {
        selection.resolve(database.message(id: selection.messageID))
      }.value
      guard let self, !Task.isCancelled, self.sessionID == id else { return }
      self.loadTask = nil
      guard isAllowed(), UIApplication.shared.applicationState == .active else { self.stop(); return }
      guard let text else { self.fail(); return }
      self.start(text: text, sessionID: id, settings: settings, languagePolicy: languagePolicy)
    }
  }

  func stop() {
    guard !sessionID.isEmpty || ownsAudioSession || loadTask != nil else { return }
    loadTask?.cancel()
    loadTask = nil
    sessionID = ""
    _ = speech.stop()
    phase = .idle
    selection = nil
    if !commands.isEmpty { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    for entry in commands {
      entry.command.removeTarget(entry.target)
      entry.command.isEnabled = entry.wasEnabled
    }
    commands.removeAll()
    if ownsAudioSession {
      ownsAudioSession = false
      let audio = AVAudioSession.sharedInstance()
      if audio.category == .playback {
        try? audio.setActive(false, options: .notifyOthersOnDeactivation)
      }
    }
  }

  private func start(text: String, sessionID: String, settings: VoiceSettings, languagePolicy: LanguagePolicySettings) {
    GalaxySSIRichMediaPlaybackCoordinator.shared.pauseForRuntimeBoundary()
    let audio = AVAudioSession.sharedInstance()
    do {
      try audio.setCategory(.playback, mode: .spokenAudio)
      try audio.setActive(true)
      ownsAudioSession = true
    } catch {
      fail()
      return
    }
    let language = LanguagePolicySettings.resolve(languagePolicy.ttsLanguage)
    let request = VoiceReplyPlaybackRequest(
      sessionId: sessionID, utteranceId: "completed-agent-reply:\(sessionID)", text: "",
      language: language, providerId: settings.ttsProvider.rawValue, runtimeChannel: settings.ttsProvider.runtimeChannel,
      voiceName: settings.ttsProvider == .microsoftEdge
        ? LanguagePolicySettings.microsoftVoice(languageTag: language, configuredVoice: settings.microsoftVoice)
        : ""
    )
    speech.beginProgressive(request, onPlaybackStarted: { [weak self] request in
      guard let self, self.sessionID == request.sessionId else { return }
      self.phase = .playing
      self.installCommands()
      self.publishNowPlaying()
    }, onDone: { [weak self] request, success, _ in
      guard let self, self.sessionID == request.sessionId else { return }
      if success { self.stop() }
      else { self.fail() }
    })
    speech.appendProgressive(text, isFinal: true)
  }

  private func pause() {
    guard phase == .playing, speech.pauseProgressive() else { return }
    phase = .paused
    publishNowPlaying()
  }

  private func resume() {
    guard phase == .paused else { return }
    do { try AVAudioSession.sharedInstance().setActive(true) }
    catch { fail(); return }
    phase = .playing
    if speech.resumeProgressive(), phase == .playing { publishNowPlaying() }
  }

  private func fail() {
    failedMessageID = selection?.messageID
    stop()
    lastErrorDescription = GalaxySSILocalization.string("galaxyssi.agent.reply_speech.failed", fallback: "Reply speech failed.")
  }

  private func publishNowPlaying() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: GalaxySSILocalization.string(
        "galaxyssi.agent.reply_speech.now_playing", fallback: "Agent reply"),
      MPNowPlayingInfoPropertyPlaybackRate: phase == .playing ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyIsLiveStream: false
    ]
  }

  private func installCommands() {
    guard commands.isEmpty else { return }
    let remote = MPRemoteCommandCenter.shared()
    register(remote.playCommand) { $0.resume() }
    register(remote.pauseCommand) { $0.pause() }
    register(remote.togglePlayPauseCommand) { player in
      if player.phase == .paused { player.resume() }
      else { player.pause() }
    }
    register(remote.stopCommand) { $0.stop() }
  }

  private func register(_ command: MPRemoteCommand, action: @escaping (AgentCompletedReplyPlayback) -> Void) {
    let wasEnabled = command.isEnabled
    command.isEnabled = true
    let id = sessionID
    let target = command.addTarget { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.sessionID == id else { return }
        action(self)
      }
      return .success
    }
    commands.append((command, target, wasEnabled))
  }
}
