import AVFoundation
import CallKit
import Combine
import UIKit
import UserNotifications

enum GalaxySSIContactReminderNotification {
  static let prefix = "galaxyssi.contact-reminder."
  static let category = "galaxyssi.contact-reminder"
  static let pendingKey = "galaxyssi.contact-reminder.pending-action"
  static let actionNotification = Notification.Name("galaxyssi.contact-reminder.action")
  static let quietKey = "contact_reminder_quiet"

  static func request(_ id: String, language: String, quiet: Bool, soundAllowed: Bool) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = "GalaxySSI"
    content.body = GalaxySSILocalization.string("galaxyssi.contact_reminder.notification",
      fallback: "You received a contact reminder.", language: language)
    content.categoryIdentifier = category
    content.userInfo = [quietKey: quiet]
    content.interruptionLevel = quiet ? .passive : .active
    content.sound = !quiet && soundAllowed ? .default : nil
    return UNNotificationRequest(identifier: identifier(id), content: content, trigger: nil)
  }

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

@MainActor
final class GalaxySSIContactReminderAlert {
  private let calls = CXCallObserver()
  private var audio: AVAudioPlayer?
  private var audioID: String?
  private var stopTask: Task<Void, Never>?
  private var audioSession: (previous: AVAudioSession.Category, mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions, applied: AVAudioSession.Category, appliedOptions: AVAudioSession.CategoryOptions)?
  private var observations = Set<AnyCancellable>()

  init() {
    NotificationCenter.default.publisher(for: .galaxySSIVoiceRecordingWillStart)
      .sink { [weak self] _ in
        if Thread.isMainThread { MainActor.assumeIsolated { self?.stop() } }
        else { DispatchQueue.main.sync { self?.stop() } }
      }.store(in: &observations)
    NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] notification in
        guard notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ==
          AVAudioSession.InterruptionType.began.rawValue else { return }
        self?.stop()
      }.store(in: &observations)
  }

  var mustBeQuiet: Bool {
    calls.calls.contains { !$0.hasEnded } || AgentCompletedReplyPlayback.shared.phase != .idle ||
      GalaxySSIContactReminderRecordingState.isActive
  }

  func show(_ record: GalaxySSIContactReminder, language: String, audibleInSilentMode: Bool) {
    let remaining = record.expiresAt - AgentControlPlaneClock.nowMillis()
    guard remaining > 0, !record.status.terminal else { return }
    let quiet = record.status == .quiet || mustBeQuiet
    if UIApplication.shared.applicationState == .active {
      if !quiet, audioID == nil {
        play(id: record.id, duration: min(remaining, GalaxySSIContactReminderEnvelope.soundDuration),
          audibleInSilentMode: audibleInSilentMode)
      }
      return
    }
  }

  func reconcile(_ records: [GalaxySSIContactReminder]) {
    if let audioID, !records.contains(where: { $0.id == audioID && !$0.status.terminal && $0.status != .muted }) {
      stop()
    }
  }

  func stop() {
    stopTask?.cancel()
    stopTask = nil
    audio?.stop()
    audio = nil
    audioID = nil
    if let configuration = audioSession {
      let session = AVAudioSession.sharedInstance()
      if session.category == configuration.applied && session.mode == .default &&
        session.categoryOptions == configuration.appliedOptions {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(configuration.previous, mode: configuration.mode, options: configuration.options)
      }
      audioSession = nil
    }
  }

  private func play(id: String, duration: Int64, audibleInSilentMode: Bool) {
    let session = AVAudioSession.sharedInstance()
    let category: AVAudioSession.Category = audibleInSilentMode ? .playback : .ambient
    let options: AVAudioSession.CategoryOptions = audibleInSilentMode ? .mixWithOthers : []
    let previous = (session.category, session.mode, session.categoryOptions)
    do {
      let player = try AVAudioPlayer(data: Self.tone())
      try session.setCategory(category, mode: .default, options: options)
      audioSession = (previous.0, previous.1, previous.2, session.category, session.categoryOptions)
      try session.setActive(true)
      player.numberOfLoops = -1
      player.volume = 0.65
      guard player.play() else { stop(); return }
      audio = player
      audioID = id
      stopTask = Task { @MainActor [weak self] in
        do { try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000) }
        catch { return }
        self?.stop()
      }
    } catch { stop() }
  }

  private static func tone() -> Data {
    let sampleRate = 16_000
    let samples = sampleRate * 2
    var data = Data()
    func text(_ value: String) { data.append(contentsOf: value.utf8) }
    func number<T: FixedWidthInteger>(_ value: T) {
      var littleEndian = value.littleEndian
      withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
    text("RIFF"); number(UInt32(36 + samples * 2)); text("WAVEfmt "); number(UInt32(16))
    number(UInt16(1)); number(UInt16(1)); number(UInt32(sampleRate)); number(UInt32(sampleRate * 2))
    number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(samples * 2))
    for sample in 0..<samples {
      let t = Double(sample) / Double(sampleRate)
      let offset = t < 0.36 ? t : t - 0.36
      let frequency = t < 0.36 ? 660.0 : 880.0
      let gain = max(0, min(1, offset * 80, (0.22 - offset) * 20))
      number(Int16(sin(2 * .pi * frequency * offset) * gain * 8_000))
    }
    return data
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
