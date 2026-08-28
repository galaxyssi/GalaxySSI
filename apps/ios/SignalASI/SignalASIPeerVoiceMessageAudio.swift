import AVFoundation
import Foundation
import SwiftUI
import UIKit

enum SignalASIPeerVoiceMessageAudio {
  static let sampleRateHz = 48_000
  static let channelCount = 1
  static let opusBitRateBPS = 48_000
  static let highPassHz = 75
  static let targetLUFS = -18.0
  static let peakDBFS = -1.0
  static let maximumDuration: TimeInterval = 60

  static func shouldUseDedicatedCapture(purpose: String, isPersonContact: Bool) -> Bool {
    purpose == "chat_message" && isPersonContact
  }
}

struct SignalASIPeerVoiceRecording: Equatable {
  var data: Data
  var durationMillis: Int64
  var fileURL: URL?
  var mimeType: String
  var fileExtension: String
}

struct SignalASIPeerMessageAttachmentStore {
  private static let rootName = "peer-message-attachments-v2"
  private static let outgoingVoicePath = "outgoing/voice"
  private static let supportedVoiceExtensions = Set(["m4a", "wav", "opus"])

  private let rootURL: URL
  private let cacheRootURLs: [URL]
  private let fileManager: FileManager
  private let cipher: SignalASIAttachmentAtRestCipher

  init(
    rootURL: URL? = nil,
    cacheRootURLs: [URL]? = nil,
    fileManager: FileManager = .default,
    cipher: SignalASIAttachmentAtRestCipher = .shared
  ) {
    self.fileManager = fileManager
    self.cipher = cipher
    let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    self.rootURL = (rootURL ?? applicationSupport.appendingPathComponent(
      Self.rootName,
      isDirectory: true
    )).standardizedFileURL
    self.cacheRootURLs = (cacheRootURLs
      ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)).map {
        $0.standardizedFileURL.resolvingSymlinksInPath()
      }
  }

  func persistOutgoingVoice(
    sourceURL: URL?,
    fallbackData: Data? = nil,
    messageID: String,
    fileExtension: String
  ) throws -> URL {
    let identity = try normalizedIdentity(messageID)
    let normalizedExtension = normalizedVoiceExtension(fileExtension)
    let directory = rootURL
      .appendingPathComponent(Self.outgoingVoicePath, isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent(
      "msg_\(identity).\(normalizedExtension).\(SignalASIAttachmentAtRestCipher.containerExtension)",
      isDirectory: false
    )
    if let sourceURL,
       canonicalURL(sourceURL) == canonicalURL(destination),
       cipher.isEncryptedFile(destination) {
      return destination
    }

    let plaintext: Data
    if let sourceURL, fileSize(sourceURL) > 0 {
      plaintext = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
    } else if let fallbackData, !fallbackData.isEmpty {
      plaintext = fallbackData
    } else {
      throw SignalASIError.invalidPayload("Voice recording is unavailable.")
    }
    guard !plaintext.isEmpty else {
      throw SignalASIError.invalidPayload("Voice message copy is incomplete.")
    }
    try cipher.write(plaintext, to: destination, purpose: voicePurpose(identity))
    if let sourceURL,
       cacheRootURLs.contains(where: { contains(sourceURL, root: $0) }) {
      try? fileManager.removeItem(at: sourceURL)
    }
    return destination
  }

  func resolveAudio(displayName: String, sourceURL: URL?) -> URL? {
    if let sourceURL, !sourceURL.isFileURL { return sourceURL }
    if let sourceURL, fileSize(sourceURL) > 0 {
      guard let identity = voiceIdentity(displayName, sourceURL.lastPathComponent) else {
        return sourceURL
      }
      let encryptedURL: URL
      if cacheRootURLs.contains(where: { contains(sourceURL, root: $0) }) {
        guard let persisted = try? persistOutgoingVoice(
          sourceURL: sourceURL,
          messageID: identity.id,
          fileExtension: identity.extension
        ) else { return nil }
        encryptedURL = persisted
      } else if cipher.isEncryptedFile(sourceURL) {
        encryptedURL = sourceURL
      } else if contains(sourceURL, root: rootURL) {
        _ = try? cipher.readMigratingPlaintext(
          from: sourceURL,
          purpose: voicePurpose(identity.id)
        )
        encryptedURL = sourceURL
      } else {
        return sourceURL
      }
      return (try? cipher.materializeTemporaryFile(
        from: encryptedURL,
        purpose: voicePurpose(identity.id),
        displayName: displayName
      )) ?? nil
    }
    guard let identity = voiceIdentity(displayName, sourceURL?.lastPathComponent ?? "") else {
      return nil
    }
    let candidate = outgoingVoiceURL(identity: identity.id, fileExtension: identity.extension)
    guard fileSize(candidate) > 0 else { return nil }
    return try? cipher.materializeTemporaryFile(
      from: candidate,
      purpose: voicePurpose(identity.id),
      displayName: displayName
    )
  }

  func resolveOutgoingVoice(displayName: String) -> URL? {
    guard let identity = voiceIdentity(displayName, displayName) else { return nil }
    let candidate = outgoingVoiceURL(identity: identity.id, fileExtension: identity.extension)
    guard fileSize(candidate) > 0 else { return nil }
    return try? cipher.materializeTemporaryFile(
      from: candidate,
      purpose: voicePurpose(identity.id),
      displayName: displayName
    )
  }

  static func shouldPruneIncoming(
    receivedAt: Date?,
    hasCompletedData: Bool,
    now: Date,
    maximumAge: TimeInterval
  ) -> Bool {
    guard !hasCompletedData else { return false }
    guard let receivedAt else { return true }
    return now.timeIntervalSince(receivedAt) > maximumAge
  }

  private func outgoingVoiceURL(identity: String, fileExtension: String) -> URL {
    rootURL
      .appendingPathComponent(Self.outgoingVoicePath, isDirectory: true)
      .appendingPathComponent(
        "msg_\(identity).\(fileExtension).\(SignalASIAttachmentAtRestCipher.containerExtension)",
        isDirectory: false
      )
  }

  private func voicePurpose(_ identity: String) -> String {
    "peer-voice:\(identity)"
  }

  private func voiceIdentity(_ displayName: String, _ storedName: String) -> (id: String, extension: String)? {
    parseVoiceIdentity(displayName) ?? parseVoiceIdentity(storedName)
  }

  private func parseVoiceIdentity(_ value: String) -> (id: String, extension: String)? {
    var name = URL(fileURLWithPath: value).lastPathComponent
    if name.pathExtension.lowercased() == SignalASIAttachmentAtRestCipher.containerExtension {
      name = name.deletingPathExtension
    }
    let fileExtension = normalizedVoiceExtension(name.pathExtension)
    guard Self.supportedVoiceExtensions.contains(name.pathExtension.lowercased()) else { return nil }
    let stem = name.deletingPathExtension
    let identity: String
    if stem.hasPrefix("voice-") {
      identity = String(stem.dropFirst("voice-".count))
    } else if stem.hasPrefix("msg_") {
      identity = String(stem.dropFirst("msg_".count))
    } else {
      return nil
    }
    guard let normalized = try? normalizedIdentity(identity) else { return nil }
    return (normalized, fileExtension)
  }

  private func normalizedVoiceExtension(_ value: String) -> String {
    let normalized = value.lowercased()
    return Self.supportedVoiceExtensions.contains(normalized) ? normalized : "wav"
  }

  private func normalizedIdentity(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    guard !normalized.isEmpty,
          normalized.count <= 128,
          normalized.unicodeScalars.allSatisfy(allowed.contains) else {
      throw SignalASIError.invalidPayload("Voice message identity is invalid.")
    }
    return normalized
  }

  private func contains(_ candidate: URL, root: URL) -> Bool {
    let path = canonicalURL(candidate).path
    let rootPath = canonicalURL(root).path
    return path == rootPath || path.hasPrefix(rootPath + "/")
  }

  private func canonicalURL(_ url: URL) -> URL {
    url.standardizedFileURL.resolvingSymlinksInPath()
  }

  private func fileSize(_ url: URL) -> Int64 {
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber else { return -1 }
    return size.int64Value
  }
}

private extension String {
  var pathExtension: String { (self as NSString).pathExtension }
  var deletingPathExtension: String { (self as NSString).deletingPathExtension }
}

@MainActor
final class SignalASIPeerVoiceMessageRecorder: NSObject, ObservableObject {
  @Published private(set) var isPending = false
  @Published private(set) var isRecording = false
  @Published private(set) var cancelPending = false
  @Published private(set) var elapsedLabel = "00:00"
  @Published private(set) var waveformPhase = 0.0
  @Published private(set) var waveformAmplitude = 0.0
  @Published private(set) var statusMessage = ""

  private var recorder: SignalASIPeerVoicePCMRecorder?
  private var holdTask: Task<Void, Never>?
  private var timer: Timer?
  private var startedAt: Date?
  private var touchActive = false
  private var messages = SignalASIAgentHoldToTalkMessages.default
  private var onFinish: ((SignalASIPeerVoiceRecording) -> Void)?
  private var onCancel: (() -> Void)?

  private static let holdStartDelayNs: UInt64 = 280_000_000
  private static let cancelThreshold: CGFloat = 56
  private static let minimumSendDuration: TimeInterval = 0.8

  func dragChanged(
    translation: CGSize,
    messages: SignalASIAgentHoldToTalkMessages,
    onFinish: @escaping (SignalASIPeerVoiceRecording) -> Void,
    onCancel: @escaping () -> Void
  ) {
    if !touchActive {
      touchActive = true
      beginPending(messages: messages, onFinish: onFinish, onCancel: onCancel)
    }
    updateCancelState(translation: translation)
  }

  func dragEnded(translation: CGSize) {
    let shouldCancel = cancelPending || translation.height <= -Self.cancelThreshold
    touchActive = false
    holdTask?.cancel()
    holdTask = nil
    guard isRecording else {
      cancelFromView()
      return
    }
    let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
    if shouldCancel {
      finish(send: false, status: messages.cancelled)
    } else if elapsed < Self.minimumSendDuration {
      finish(send: false, status: messages.tooShort)
    } else {
      finish(send: true, status: "")
    }
  }

  func cancelFromView() {
    touchActive = false
    holdTask?.cancel()
    holdTask = nil
    if isPending || isRecording {
      finish(send: false, status: "")
    } else {
      reset()
    }
  }

  private func beginPending(
    messages: SignalASIAgentHoldToTalkMessages,
    onFinish: @escaping (SignalASIPeerVoiceRecording) -> Void,
    onCancel: @escaping () -> Void
  ) {
    isPending = true
    isRecording = false
    cancelPending = false
    statusMessage = ""
    elapsedLabel = "00:00"
    waveformPhase = 0
    waveformAmplitude = 0
    self.messages = messages
    self.onFinish = onFinish
    self.onCancel = onCancel
    holdTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: Self.holdStartDelayNs)
      guard !Task.isCancelled else { return }
      await self?.requestPermissionAndStart()
    }
  }

  private func requestPermissionAndStart() async {
    let allowed = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
    guard isPending else { return }
    guard allowed else {
      fail(messages.permissionDenied)
      return
    }
    do {
      let recorder = SignalASIPeerVoicePCMRecorder()
      try recorder.start()
      self.recorder = recorder
      startedAt = Date()
      isPending = false
      isRecording = true
      startTimer()
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    } catch {
      fail(error.localizedDescription.ifBlank(messages.speechUnavailable))
    }
  }

  private func updateCancelState(translation: CGSize) {
    guard isRecording else { return }
    let next = translation.height <= -Self.cancelThreshold
    guard next != cancelPending else { return }
    cancelPending = next
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  private func finish(send: Bool, status: String) {
    let completion = onFinish
    guard send else {
      recorder?.cancel()
      releaseRecorder()
      onCancel?()
      statusMessage = status
      reset(keepStatus: true)
      return
    }
    do {
      guard let encoded = try recorder?.stopAndEncode(), !encoded.data.isEmpty else {
        throw SignalASIPeerVoiceOpusError.emptyRecording
      }
      releaseRecorder()
      completion?(SignalASIPeerVoiceRecording(
        data: encoded.data,
        durationMillis: max(encoded.durationMillis, 1_000),
        fileURL: nil,
        mimeType: encoded.mimeType,
        fileExtension: encoded.fileExtension
      ))
      reset()
    } catch {
      fail(error.localizedDescription.ifBlank(messages.speechUnavailable))
    }
  }

  private func fail(_ message: String) {
    recorder?.cancel()
    releaseRecorder()
    onCancel?()
    statusMessage = message
    reset(keepStatus: true)
  }

  private func releaseRecorder() {
    recorder = nil
  }

  private func startTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  private func tick() {
    guard let recorder, let startedAt else { return }
    let elapsed = Date().timeIntervalSince(startedAt)
    let seconds = max(0, Int(elapsed))
    elapsedLabel = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    waveformPhase += 0.34
    waveformAmplitude = recorder.currentAmplitude()
    if elapsed >= SignalASIPeerVoiceMessageAudio.maximumDuration {
      finish(send: true, status: "")
    }
  }

  private func reset(
    keepStatus: Bool = false
  ) {
    timer?.invalidate()
    timer = nil
    isPending = false
    isRecording = false
    cancelPending = false
    startedAt = nil
    touchActive = false
    holdTask?.cancel()
    holdTask = nil
    onFinish = nil
    onCancel = nil
    waveformAmplitude = 0
    if !keepStatus { statusMessage = "" }
  }

  deinit {
    holdTask?.cancel()
    timer?.invalidate()
    recorder?.cancel()
  }
}

final class SignalASIGentleSpeechPlaybackEngine {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let file: AVAudioFile
  private let temporaryPlaybackURL: URL?
  private let sampleRate: Double
  private var startFrame: AVAudioFramePosition = 0
  private var generation = 0
  private(set) var isPlaying = false
  var onCompletion: (() -> Void)?

  var duration: TimeInterval {
    sampleRate > 0 ? Double(file.length) / sampleRate : 0
  }

  var currentTime: TimeInterval {
    guard sampleRate > 0 else { return 0 }
    let rendered = playerNode.lastRenderTime
      .flatMap { playerNode.playerTime(forNodeTime: $0) }
      .map { AVAudioFramePosition($0.sampleTime) } ?? 0
    return min(max(Double(startFrame + rendered) / sampleRate, 0), duration)
  }

  init(url: URL) throws {
    let playbackURL = try SignalASIPeerVoiceOpusPlayback.materializePCMFile(for: url)
    temporaryPlaybackURL = playbackURL == url ? nil : playbackURL
    do {
      file = try AVAudioFile(forReading: playbackURL)
    } catch {
      if playbackURL != url { try? FileManager.default.removeItem(at: playbackURL) }
      throw error
    }
    sampleRate = file.processingFormat.sampleRate
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
    engine.prepare()
  }

  func play() throws {
    if startFrame >= file.length { startFrame = 0 }
    if !engine.isRunning { try engine.start() }
    isPlaying = true
    scheduleFromCurrentFrame()
    playerNode.play()
  }

  func pause() {
    let pausedFrame = frame(for: currentTime)
    generation += 1
    playerNode.stop()
    startFrame = pausedFrame
    isPlaying = false
  }

  func seek(to seconds: TimeInterval) throws {
    let shouldResume = isPlaying
    generation += 1
    playerNode.stop()
    startFrame = frame(for: min(max(seconds, 0), duration))
    isPlaying = false
    if shouldResume { try play() }
  }

  func stop() {
    generation += 1
    playerNode.stop()
    engine.stop()
    startFrame = 0
    isPlaying = false
  }

  private func scheduleFromCurrentFrame() {
    let remaining = max(file.length - startFrame, 0)
    guard remaining > 0 else {
      finishPlayback()
      return
    }
    generation += 1
    let scheduledGeneration = generation
    playerNode.scheduleSegment(
      file,
      startingFrame: startFrame,
      frameCount: AVAudioFrameCount(min(remaining, AVAudioFramePosition(UInt32.max))),
      at: nil,
      completionCallbackType: .dataPlayedBack
    ) { [weak self] _ in
      DispatchQueue.main.async { self?.finishPlayback(generation: scheduledGeneration) }
    }
  }

  private func finishPlayback(generation: Int? = nil) {
    if let generation, generation != self.generation { return }
    playerNode.stop()
    engine.stop()
    startFrame = 0
    isPlaying = false
    onCompletion?()
  }

  private func frame(for seconds: TimeInterval) -> AVAudioFramePosition {
    min(max(AVAudioFramePosition((seconds * sampleRate).rounded()), 0), file.length)
  }

  deinit {
    if let temporaryPlaybackURL {
      try? FileManager.default.removeItem(at: temporaryPlaybackURL)
    }
  }
}
