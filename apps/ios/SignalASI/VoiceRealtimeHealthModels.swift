import Foundation

enum VoiceHealthComponent: String, Codable, CaseIterable, Identifiable {
  case wakeWord = "WAKE_WORD"
  case asr = "ASR"
  case tts = "TTS"

  var id: String { rawValue }
}

enum VoiceHealthState: String, Codable, CaseIterable, Identifiable {
  case active = "ACTIVE"
  case healthy = "HEALTHY"
  case ready = "READY"
  case checking = "CHECKING"
  case degraded = "DEGRADED"
  case blocked = "BLOCKED"
  case disabled = "DISABLED"

  var id: String { rawValue }
}

enum VoiceHealthIssue: String, Codable, CaseIterable, Identifiable {
  case none = "NONE"
  case disabled = "DISABLED"
  case checking = "CHECKING"
  case microphoneMissing = "MICROPHONE_MISSING"
  case permissionRequired = "PERMISSION_REQUIRED"
  case runtimeMissing = "RUNTIME_MISSING"
  case modelMissing = "MODEL_MISSING"
  case providerUnavailable = "PROVIDER_UNAVAILABLE"
  case networkRequired = "NETWORK_REQUIRED"
  case languageUnsupported = "LANGUAGE_UNSUPPORTED"
  case recentFailure = "RECENT_FAILURE"

  var id: String { rawValue }
}

enum VoiceRuntimeChannel: String, Codable, CaseIterable, Identifiable {
  case openWakeWord = "OPEN_WAKE_WORD"
  case androidWakeASR = "ANDROID_WAKE_ASR"
  case localWhisperASR = "LOCAL_WHISPER_ASR"
  case onlineRealtimeASR = "ONLINE_REALTIME_ASR"
  case remoteWhisperASR = "REMOTE_WHISPER_ASR"
  case androidSystemASR = "ANDROID_SYSTEM_ASR"
  case androidSystemTTS = "ANDROID_SYSTEM_TTS"
  case microsoftEdgeTTS = "MICROSOFT_EDGE_TTS"

  var id: String { rawValue }
}

struct VoiceRuntimeHealthRecord: Codable, Equatable {
  var active: Bool
  var startedAtMillis: Int64
  var lastSuccessAtMillis: Int64
  var lastFailureAtMillis: Int64
  var lastFailureReason: String

  init(
    active: Bool = false,
    startedAtMillis: Int64 = 0,
    lastSuccessAtMillis: Int64 = 0,
    lastFailureAtMillis: Int64 = 0,
    lastFailureReason: String = ""
  ) {
    self.active = active
    self.startedAtMillis = max(0, startedAtMillis)
    self.lastSuccessAtMillis = max(0, lastSuccessAtMillis)
    self.lastFailureAtMillis = max(0, lastFailureAtMillis)
    self.lastFailureReason = Self.normalizedFailureReason(lastFailureReason)
  }

  var lastEventAtMillis: Int64 {
    max(startedAtMillis, lastSuccessAtMillis, lastFailureAtMillis)
  }

  static func normalizedFailureReason(_ value: String) -> String {
    String(
      value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .prefix(160)
    )
  }

  enum CodingKeys: String, CodingKey {
    case active
    case startedAtMillis = "started_at_millis"
    case lastSuccessAtMillis = "last_success_at_millis"
    case lastFailureAtMillis = "last_failure_at_millis"
    case lastFailureReason = "last_failure_reason"
  }
}

enum VoiceRuntimeHealthRegistry {
  private static let lock = NSLock()
  private static var records: [VoiceRuntimeChannel: VoiceRuntimeHealthRecord] = [:]

  static func begin(
    _ channel: VoiceRuntimeChannel,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    lock.lock()
    var current = records[channel] ?? VoiceRuntimeHealthRecord()
    current.active = true
    current.startedAtMillis = max(0, nowMillis)
    records[channel] = current
    lock.unlock()
  }

  static func success(
    _ channel: VoiceRuntimeChannel,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    lock.lock()
    var current = records[channel] ?? VoiceRuntimeHealthRecord()
    current.active = false
    current.lastSuccessAtMillis = max(0, nowMillis)
    records[channel] = current
    lock.unlock()
  }

  static func failure(
    _ channel: VoiceRuntimeChannel,
    reason: String,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    lock.lock()
    var current = records[channel] ?? VoiceRuntimeHealthRecord()
    current.active = false
    current.lastFailureAtMillis = max(0, nowMillis)
    current.lastFailureReason = VoiceRuntimeHealthRecord.normalizedFailureReason(reason)
    records[channel] = current
    lock.unlock()
  }

  static func idle(_ channel: VoiceRuntimeChannel) {
    lock.lock()
    if var current = records[channel] {
      current.active = false
      records[channel] = current
    }
    lock.unlock()
  }

  static func record(_ channel: VoiceRuntimeChannel) -> VoiceRuntimeHealthRecord {
    lock.lock()
    defer { lock.unlock() }
    return records[channel] ?? VoiceRuntimeHealthRecord()
  }

  static func resetForTests() {
    lock.lock()
    records.removeAll()
    lock.unlock()
  }
}

struct VoiceHealthDependency: Codable, Equatable {
  var ready: Bool
  var checking: Bool
  var issue: VoiceHealthIssue

  init(
    ready: Bool,
    checking: Bool = false,
    issue: VoiceHealthIssue = .none
  ) {
    self.ready = ready
    self.checking = checking
    self.issue = issue
  }
}

struct VoiceHealthProbe: Codable, Equatable {
  var component: VoiceHealthComponent
  var enabled: Bool
  var provider: String
  var dependency: VoiceHealthDependency
  var runtime: VoiceRuntimeHealthRecord
}

struct VoiceHealthEntry: Codable, Equatable {
  var component: VoiceHealthComponent
  var provider: String
  var state: VoiceHealthState
  var issue: VoiceHealthIssue
  var runtime: VoiceRuntimeHealthRecord
}

struct VoiceRealtimeHealthSnapshot: Codable, Equatable {
  var entries: [VoiceHealthEntry]
  var checkedAtMillis: Int64

  subscript(component: VoiceHealthComponent) -> VoiceHealthEntry {
    entries.first { $0.component == component }!
  }

  enum CodingKeys: String, CodingKey {
    case entries
    case checkedAtMillis = "checked_at_millis"
  }
}

enum VoiceRealtimeHealthPolicy {
  static let recentFailureWindowMillis: Int64 = 5 * 60 * 1_000
  static let successFreshnessMillis: Int64 = 10 * 60 * 1_000

  static func evaluate(
    probes: [VoiceHealthProbe],
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> VoiceRealtimeHealthSnapshot {
    VoiceRealtimeHealthSnapshot(
      entries: probes.map { evaluate($0, nowMillis: max(0, nowMillis)) },
      checkedAtMillis: max(0, nowMillis)
    )
  }

  private static func evaluate(
    _ probe: VoiceHealthProbe,
    nowMillis: Int64
  ) -> VoiceHealthEntry {
    let runtime = probe.runtime
    let recentFailure = runtime.lastFailureAtMillis > runtime.lastSuccessAtMillis &&
      (0...recentFailureWindowMillis).contains(nowMillis - runtime.lastFailureAtMillis)
    let recentSuccess = runtime.lastSuccessAtMillis > 0 &&
      (0...successFreshnessMillis).contains(nowMillis - runtime.lastSuccessAtMillis)
    let state: VoiceHealthState
    if !probe.enabled {
      state = .disabled
    } else if probe.dependency.checking {
      state = .checking
    } else if !probe.dependency.ready {
      state = .blocked
    } else if runtime.active {
      state = .active
    } else if recentFailure {
      state = .degraded
    } else if recentSuccess {
      state = .healthy
    } else {
      state = .ready
    }
    let issue: VoiceHealthIssue
    switch state {
    case .disabled:
      issue = .disabled
    case .checking:
      issue = .checking
    case .degraded:
      issue = .recentFailure
    case .blocked:
      issue = probe.dependency.issue
    case .active, .healthy, .ready:
      issue = .none
    }
    return VoiceHealthEntry(
      component: probe.component,
      provider: probe.provider,
      state: state,
      issue: issue,
      runtime: runtime
    )
  }
}

enum VoiceRealtimeHealthDetector {
  static func detect(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot,
    checkedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> VoiceRealtimeHealthSnapshot {
    let asr = VoiceASRProviderRoutingPolicy.route(
      settings: settings,
      capabilities: capabilities,
      onlineRealtimeAvailable: VoiceOnlineRealtimeASRConfiguration.isConfigured &&
        settings.onlineAsrAllowed && capabilities[.cloudASR].ready
    )
    let tts = preferredTTSCapability(settings: settings, capabilities: capabilities)
    let wakeCapabilityId: VoiceProviderCapabilityId = settings.wakeProvider == .openWakeWord
      ? .openWakeWord
      : .androidSystemASR
    let wakeRuntimeChannel: VoiceRuntimeChannel = settings.wakeProvider == .openWakeWord
      ? .openWakeWord
      : .androidWakeASR
    return VoiceRealtimeHealthPolicy.evaluate(
      probes: [
        VoiceHealthProbe(
          component: .wakeWord,
          enabled: settings.wakeListeningEnabled,
          provider: settings.wakeProvider.displayTitle,
          dependency: dependency(for: capabilities[wakeCapabilityId]),
          runtime: VoiceRuntimeHealthRegistry.record(wakeRuntimeChannel)
        ),
        VoiceHealthProbe(
          component: .asr,
          enabled: settings.speechRecognitionEnabled,
          provider: asr.provider,
          dependency: dependency(for: asr.capability),
          runtime: VoiceRuntimeHealthRegistry.record(asr.channel)
        ),
        VoiceHealthProbe(
          component: .tts,
          enabled: settings.textToSpeechEnabled,
          provider: tts.provider,
          dependency: dependency(for: tts.capability),
          runtime: VoiceRuntimeHealthRegistry.record(tts.channel)
        )
      ],
      nowMillis: checkedAtMillis
    )
  }

  static func dependency(for capability: VoiceProviderCapability) -> VoiceHealthDependency {
    switch capability.state {
    case .ready:
      return VoiceHealthDependency(ready: true)
    case .checking:
      return VoiceHealthDependency(ready: false, checking: true, issue: .checking)
    case .needsPermission, .needsDownload, .needsNetwork, .unavailable:
      return VoiceHealthDependency(
        ready: false,
        issue: issue(for: capability.reason)
      )
    }
  }

  private static func issue(for reason: VoiceProviderCapabilityReason) -> VoiceHealthIssue {
    switch reason {
    case .ready:
      return .none
    case .checking:
      return .checking
    case .microphoneMissing:
      return .microphoneMissing
    case .microphonePermissionRequired:
      return .permissionRequired
    case .whisperRuntimeMissing:
      return .runtimeMissing
    case .whisperModelMissing:
      return .modelMissing
    case .networkRequired:
      return .networkRequired
    case .ttsLanguageUnsupported:
      return .languageUnsupported
    case .systemRecognizerMissing, .offlineRecognizerMissing, .ttsEngineMissing:
      return .providerUnavailable
    }
  }

  private static func preferredTTSCapability(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot
  ) -> (capability: VoiceProviderCapability, channel: VoiceRuntimeChannel, provider: String) {
    let system = capabilities[.androidSystemTTS]
    let edge = capabilities[.microsoftEdgeTTS]
    if settings.ttsProvider == .microsoftEdge {
      return (edge, .microsoftEdgeTTS, "Microsoft Edge TTS")
    }
    return (system, .androidSystemTTS, "iOS System TTS")
  }
}
