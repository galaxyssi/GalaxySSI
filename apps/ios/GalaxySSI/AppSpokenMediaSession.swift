import AVFoundation
import Combine
import MediaPlayer
import UIKit

extension Notification.Name {
  static let galaxySSIVoiceRecordingWillStart = Notification.Name("galaxyssi.voice_recording_will_start")
}

@MainActor
final class AppSpokenMediaSession {
  static let shared = AppSpokenMediaSession()

  struct Controls {
    let title: String
    let resume: () -> Void
    let pause: () -> Void
    let stop: () -> Void
    let relinquish: () -> Void
    var next: (() -> Void)? = nil
  }

  private var owner: ObjectIdentifier?
  private var controls: Controls?
  private var generation: UInt64 = 0
  private var activeAudio = false
  private var playing = false
  private var commands: [(command: MPRemoteCommand, target: Any, wasEnabled: Bool)] = []
  private var observations = Set<AnyCancellable>()

  private init() {
    let center = NotificationCenter.default
    center.publisher(for: .galaxySSIVoiceRecordingWillStart).sink { [weak self] _ in
      if Thread.isMainThread { MainActor.assumeIsolated { self?.yieldOwner() } }
      else { DispatchQueue.main.sync { self?.yieldOwner() } }
    }.store(in: &observations)
    center.publisher(for: UIApplication.willResignActiveNotification).receive(on: RunLoop.main).sink { [weak self] _ in
      guard let self, self.commands.isEmpty else { return }
      self.yieldOwner()
    }.store(in: &observations)
    center.publisher(for: AVAudioSession.interruptionNotification).receive(on: RunLoop.main).sink { [weak self] event in
      guard let self, let raw = event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
      if self.commands.isEmpty { self.yieldOwner() }
      else { self.controls?.pause() }
    }.store(in: &observations)
    center.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main).sink { [weak self] event in
      let raw = event.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
      if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.yieldOwner() }
    }.store(in: &observations)
    center.publisher(for: AVAudioSession.mediaServicesWereResetNotification).receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.yieldOwner() }.store(in: &observations)
  }

  func owns(_ candidate: AnyObject) -> Bool { owner == ObjectIdentifier(candidate) }

  func reserve(_ candidate: AnyObject, controls: Controls) {
    if owns(candidate) { return }
    yieldOwner()
    owner = ObjectIdentifier(candidate)
    self.controls = controls
    generation &+= 1
  }

  func activate(_ candidate: AnyObject) -> Bool {
    guard owns(candidate) else { return false }
    if activeAudio { return true }
    GalaxySSIRichMediaPlaybackCoordinator.shared.pauseForRuntimeBoundary()
    let audio = AVAudioSession.sharedInstance()
    do {
      try audio.setCategory(.playback, mode: .spokenAudio)
      try audio.setActive(true)
      activeAudio = true
      return true
    } catch {
      return false
    }
  }

  func setPlaying(_ value: Bool, owner candidate: AnyObject) {
    guard owns(candidate), let controls else { return }
    if value && commands.isEmpty { installCommands() }
    playing = value
    guard !commands.isEmpty else { return }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: controls.title,
      MPNowPlayingInfoPropertyPlaybackRate: value ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyIsLiveStream: false
    ]
  }

  func suspend(_ candidate: AnyObject) {
    guard owns(candidate) else { return }
    setPlaying(false, owner: candidate)
    deactivateAudio()
  }

  func release(_ candidate: AnyObject) {
    if owns(candidate) { clear() }
  }

  private func yieldOwner() {
    let current = owner
    controls?.relinquish()
    if owner == current { clear() }
  }

  private func clear() {
    generation &+= 1
    owner = nil
    controls = nil
    playing = false
    if !commands.isEmpty { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    for entry in commands {
      entry.command.removeTarget(entry.target)
      entry.command.isEnabled = entry.wasEnabled
    }
    commands.removeAll()
    deactivateAudio()
  }

  private func deactivateAudio() {
    guard activeAudio else { return }
    activeAudio = false
    let audio = AVAudioSession.sharedInstance()
    if audio.category == .playback {
      try? audio.setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  private func installCommands() {
    let remote = MPRemoteCommandCenter.shared()
    register(remote.playCommand) { $0.controls?.resume() }
    register(remote.pauseCommand) { $0.controls?.pause() }
    register(remote.togglePlayPauseCommand) { session in
      if session.playing { session.controls?.pause() }
      else { session.controls?.resume() }
    }
    register(remote.stopCommand) { $0.controls?.stop() }
    if controls?.next != nil { register(remote.nextTrackCommand) { $0.controls?.next?() } }
  }

  private func register(_ command: MPRemoteCommand, action: @escaping (AppSpokenMediaSession) -> Void) {
    let wasEnabled = command.isEnabled
    command.isEnabled = true
    let token = generation
    let target = command.addTarget { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.generation == token else { return }
        action(self)
      }
      return .success
    }
    commands.append((command, target, wasEnabled))
  }
}
