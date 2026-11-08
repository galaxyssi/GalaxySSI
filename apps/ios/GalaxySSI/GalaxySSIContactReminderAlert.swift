import AVFoundation
import CallKit
import Combine
import OSLog
import UIKit
import UserNotifications

enum GalaxySSIContactReminderNotification {
  static let prefix = "galaxyssi.contact-reminder."
  static let category = "galaxyssi.contact-reminder"
  static let pendingKey = "galaxyssi.contact-reminder.pending-action"
  static let actionNotification = Notification.Name("galaxyssi.contact-reminder.action")

  static func register() {
    let center = UNUserNotificationCenter.current()
    center.getNotificationCategories { existing in
      let language = Locale.preferredLanguages.first ?? "en"
      let actions: [(GalaxySSIContactReminderAction, String, String)] = [
        (.muted, "mute", "Mute"), (.dismissed, "ignore", "Ignore"), (.acknowledged, "got_it", "Got it")
      ]
      let buttons = actions.map { action, key, fallback in
        UNNotificationAction(identifier: action.rawValue,
          title: GalaxySSILocalization.string("galaxyssi.contact_reminder." + key, fallback: fallback, language: language),
          options: [.foreground])
      }
      let reminder = UNNotificationCategory(identifier: category, actions: buttons, intentIdentifiers: [], options: [])
      center.setNotificationCategories(Set(existing.filter { $0.identifier != category }).union([reminder]))
    }
  }

  static func identifier(_ id: String) -> String { prefix + id }

  static func reminderID(_ identifier: String) -> String? {
    guard identifier.hasPrefix(prefix) else { return nil }
    let id = String(identifier.dropFirst(prefix.count))
    return id.range(of: #"^[A-Za-z0-9-]{16,64}$"#, options: .regularExpression) == nil ? nil : id
  }

  static func recordAction(id: String, action: String) {
    guard action == UNNotificationDefaultActionIdentifier ||
      [GalaxySSIContactReminderAction.muted.rawValue, GalaxySSIContactReminderAction.dismissed.rawValue,
       GalaxySSIContactReminderAction.acknowledged.rawValue].contains(action) else { return }
    UserDefaults.standard.set(["id": id, "action": action], forKey: pendingKey)
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: actionNotification, object: nil)
    }
  }

  static func remove(_ id: String) {
    let identifiers = [identifier(id)]
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }
}

enum GalaxySSIContactReminderAudioPolicy {
  static func duration(for record: GalaxySSIContactReminder, currentID: String?, now: Int64,
                       busy: Bool) -> Int64? {
    guard !busy, record.id != currentID, !record.outgoing, record.status == .received,
          record.expiresAt > now, now > 0 else { return nil }
    return min(record.expiresAt - now, GalaxySSIContactReminderEnvelope.soundDuration)
  }

  static func tone(duration: Int64) -> Data {
    let frames = Int(max(0, min(duration, GalaxySSIContactReminderEnvelope.soundDuration))) * 16
    let bytes = frames * 2
    var data = Data()
    data.reserveCapacity(44 + bytes)
    func text(_ value: String) { data.append(contentsOf: value.utf8) }
    func number<T: FixedWidthInteger>(_ value: T) {
      var littleEndian = value.littleEndian
      withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
    text("RIFF"); number(UInt32(36 + bytes)); text("WAVEfmt "); number(UInt32(16))
    number(UInt16(1)); number(UInt16(1)); number(UInt32(16_000)); number(UInt32(32_000))
    number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(bytes))
    var remaining = bytes
    while remaining > 0 {
      let count = min(remaining, cycle.count)
      data.append(contentsOf: cycle.prefix(count))
      remaining -= count
    }
    return data
  }

  private static let cycle: Data = {
    var pcm = Data(capacity: 64_000)
    for sample in 0..<32_000 {
      let t = Double(sample) / 16_000
      let offset = t < 0.36 ? t : t - 0.36
      let frequency = t < 0.36 ? 660.0 : 880.0
      let gain = max(0, min(1, offset * 80, (0.22 - offset) * 20))
      var value = Int16(sin(2 * .pi * frequency * offset) * gain * 8_000).littleEndian
      withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
    }
    return pcm
  }()
}

@MainActor
final class GalaxySSIContactReminderAlert {
  private enum StopReason: String {
    case explicitAction, replaced, interrupted, busy, deadline, recordChanged, playbackError
  }

  private let calls = CXCallObserver()
  private var audio: AVAudioPlayer?
  private var audioID: String?
  private var stopTask: Task<Void, Never>?
  private var audioSession: (previous: AVAudioSession.Category, mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions, applied: AVAudioSession.Category, appliedOptions: AVAudioSession.CategoryOptions)?
  private var activatedSession = false
  private var observations = Set<AnyCancellable>()

  init() {
    NotificationCenter.default.publisher(for: .galaxySSIVoiceRecordingWillStart)
      .sink { [weak self] _ in
        if Thread.isMainThread { MainActor.assumeIsolated { self?.stop(.busy) } }
        else { DispatchQueue.main.sync { self?.stop(.busy) } }
      }.store(in: &observations)
    NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.stop(.interrupted) }
      .store(in: &observations)
    NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] notification in
        guard notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ==
          AVAudioSession.InterruptionType.began.rawValue else { return }
        self?.stop(.interrupted)
      }.store(in: &observations)
  }

  var mustBeQuiet: Bool {
    calls.calls.contains { !$0.hasEnded } || AgentCompletedReplyPlayback.shared.phase != .idle ||
      GalaxySSIContactReminderRecordingState.isActive
  }

  func show(_ record: GalaxySSIContactReminder, language: String, audibleInSilentMode: Bool) {
    let now = AgentControlPlaneClock.nowMillis()
    guard record.expiresAt > now, !record.outgoing, !record.status.terminal, record.status != .muted else { return }
    let quiet = record.status == .quiet || mustBeQuiet
    if UIApplication.shared.applicationState == .active {
      if let duration = GalaxySSIContactReminderAudioPolicy.duration(for: record, currentID: audioID,
        now: now, busy: quiet) {
        stop(.replaced)
        play(id: record.id, expiresAt: record.expiresAt, duration: duration, audibleInSilentMode: audibleInSilentMode)
      } else {
        diagnostic(quiet ? "Skipped: call, recording, spoken playback, or quiet reminder" : "Skipped: already playing")
      }
      return
    }
    let content = UNMutableNotificationContent()
    content.title = "GalaxySSI"
    content.body = GalaxySSILocalization.string("galaxyssi.contact_reminder.notification",
      fallback: "You received a contact reminder.", language: language)
    content.categoryIdentifier = GalaxySSIContactReminderNotification.category
    content.sound = quiet ? nil : .default
    let request = UNNotificationRequest(identifier: GalaxySSIContactReminderNotification.identifier(record.id),
      content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }

  func reconcile(_ records: [GalaxySSIContactReminder]) {
    let now = AgentControlPlaneClock.nowMillis()
    if let audioID, !records.contains(where: { $0.id == audioID &&
      GalaxySSIContactReminderAudioPolicy.duration(for: $0, currentID: nil, now: now, busy: false) != nil }) {
      stop(.recordChanged)
    }
  }

  func stop() { stop(.explicitAction) }

  private func stop(_ reason: StopReason) {
    if audioID != nil || audioSession != nil { diagnostic("Stopped: " + reason.rawValue) }
    stopTask?.cancel()
    stopTask = nil
    audio?.stop()
    audio = nil
    audioID = nil
    if let configuration = audioSession {
      let session = AVAudioSession.sharedInstance()
      if session.category == configuration.applied && session.mode == .default &&
        session.categoryOptions == configuration.appliedOptions {
        if activatedSession { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
        try? session.setCategory(configuration.previous, mode: configuration.mode, options: configuration.options)
      }
      audioSession = nil
    }
    activatedSession = false
  }

  private func play(id: String, expiresAt: Int64, duration: Int64, audibleInSilentMode: Bool) {
    let session = AVAudioSession.sharedInstance()
    let category: AVAudioSession.Category = audibleInSilentMode ? .playback : .ambient
    let options: AVAudioSession.CategoryOptions = audibleInSilentMode ? .mixWithOthers : []
    let previous = (session.category, session.mode, session.categoryOptions)
    do {
      try session.setCategory(category, mode: .default, options: options)
      audioSession = (previous.0, previous.1, previous.2, session.category, session.categoryOptions)
      try session.setActive(true)
      activatedSession = true
      let available = min(duration, expiresAt - AgentControlPlaneClock.nowMillis())
      guard available > 0 else { stop(.deadline); return }
      guard !mustBeQuiet else { stop(.busy); return }
      // The clip itself is bounded even when the app cannot run its watchdog.
      let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(available) * 1_000_000
      let player = try AVAudioPlayer(data: GalaxySSIContactReminderAudioPolicy.tone(duration: available))
      player.volume = 0.65
      guard DispatchTime.now().uptimeNanoseconds < deadline else { stop(.deadline); return }
      guard player.play() else { stop(.playbackError); return }
      audio = player
      audioID = id
      diagnostic("Playback accepted by audio session")
      stopTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
          let now = DispatchTime.now().uptimeNanoseconds
          if now >= deadline { self?.stop(.deadline); return }
          do { try await Task.sleep(nanoseconds: min(500_000_000, deadline - now)) }
          catch { return }
          guard !Task.isCancelled, let self, self.audioID == id else { return }
          if self.mustBeQuiet { self.stop(.busy); return }
          if self.audio?.isPlaying != true || AgentControlPlaneClock.nowMillis() >= expiresAt {
            self.stop(.deadline)
            return
          }
        }
      }
    } catch {
      diagnostic("Playback could not start")
      stop(.playbackError)
    }
  }

  private func diagnostic(_ message: String) {
    #if DEBUG
    Logger(subsystem: "com.galaxyssi.ios", category: "contact-reminder-audio").debug("\(message, privacy: .public)")
    #endif
  }
}

enum GalaxySSIContactReminderRecordingState {
  private static let lock = NSLock()
  private static let owners = NSHashTable<AnyObject>.weakObjects()

  static var isActive: Bool {
    lock.lock(); defer { lock.unlock() }
    return !owners.allObjects.isEmpty
  }

  static func set(_ owner: AnyObject, active: Bool) {
    lock.lock(); defer { lock.unlock() }
    if active { owners.add(owner) } else { owners.remove(owner) }
  }
}
