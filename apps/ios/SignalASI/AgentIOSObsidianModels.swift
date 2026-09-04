import Foundation

struct AgentIOSObsidianSettings: Codable, Equatable {
  var enabled = false
  var bookmarkData = Data()
  var vaultName = ""
  var lastProjectionAtMillis: Int64 = 0
  var lastError = ""
}

enum AgentIOSObsidianEditStatus: String, Codable, Equatable {
  case pending
  case approved
  case rejected
}

struct AgentIOSObsidianEditCandidate: Codable, Equatable, Identifiable {
  var id = UUID().uuidString
  var sourceKey: String
  var relativePath: String
  var title: String
  var content: String
  var status = AgentIOSObsidianEditStatus.pending
  var detectedAtMillis = AgentMemoryClock.nowMillis()
  var reviewedAtMillis: Int64 = 0
}

struct AgentIOSObsidianProjectionResult: Equatable {
  var configured: Bool
  var writtenCount = 0
  var unchangedCount = 0
  var candidateCount = 0
  var remainingCount = 0
  var error = ""
}

struct AgentIOSObsidianProjectionIndexEntry: Codable, Equatable {
  var sourceKey: String
  var relativePath: String
  var sourceRevision: String
  var generatedHash: String
  var lastModifiedMillis: Int64
  var userModified = false
}

private struct AgentIOSObsidianState: Codable {
  var settings = AgentIOSObsidianSettings()
  var index: [AgentIOSObsidianProjectionIndexEntry] = []
  var candidates: [AgentIOSObsidianEditCandidate] = []
  var editScanCursor = 0
}

final class AgentIOSObsidianStateStore {
  private let defaults: UserDefaults
  private let secrets: SignalASISecretStore
  private let key: String
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: SignalASISecretStore = KeychainSecretStore.shared,
    key: String = "signalasi-ios-obsidian-v1"
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
  }

  func settings() -> AgentIOSObsidianSettings { locked { load().settings } }

  func saveSettings(_ settings: AgentIOSObsidianSettings) {
    locked {
      var state = load()
      state.settings = settings
      save(state)
    }
  }

  func index() -> [AgentIOSObsidianProjectionIndexEntry] { locked { load().index } }

  func index(sourceKey: String) -> AgentIOSObsidianProjectionIndexEntry? {
    locked { load().index.first { $0.sourceKey == sourceKey } }
  }

  func saveIndex(_ entry: AgentIOSObsidianProjectionIndexEntry) {
    locked {
      var state = load()
      state.index.removeAll { $0.sourceKey == entry.sourceKey }
      state.index.append(entry)
      state.index = Array(state.index.suffix(1_500))
      save(state)
    }
  }

  func removeIndex(sourceKey: String) {
    locked {
      var state = load()
      state.index.removeAll { $0.sourceKey == sourceKey }
      save(state)
    }
  }

  func candidates(status: AgentIOSObsidianEditStatus? = nil) -> [AgentIOSObsidianEditCandidate] {
    locked {
      load().candidates
        .filter { status == nil || $0.status == status }
        .sorted { $0.detectedAtMillis > $1.detectedAtMillis }
    }
  }

  func saveCandidate(_ candidate: AgentIOSObsidianEditCandidate) {
    locked {
      var state = load()
      state.candidates.removeAll { $0.id == candidate.id }
      state.candidates.append(candidate)
      state.candidates = Array(state.candidates.suffix(300))
      save(state)
    }
  }

  func editScanCursor() -> Int { locked { load().editScanCursor } }

  func saveEditScanCursor(_ value: Int) {
    locked {
      var state = load()
      state.editScanCursor = max(value, 0)
      save(state)
    }
  }

  func clear() {
    locked {
      SignalASIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
    }
  }

  private func load() -> AgentIOSObsidianState {
    guard let data = SignalASIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(AgentIOSObsidianState.self, from: data) else {
      return AgentIOSObsidianState()
    }
    return state
  }

  private func save(_ state: AgentIOSObsidianState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    _ = SignalASIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }
}

enum AgentIOSObsidianProjectionPrivacyPolicy {
  static func safeKnowledge(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sensitive(value)
  }

  static func safeMetadata(_ value: String) -> Bool {
    value.isEmpty || (!sensitive(value) && value.range(of: metadataSecretPattern, options: .regularExpression) == nil)
  }

  static func transcriptText(_ value: String) -> String {
    sensitive(value) ? "[Sensitive content omitted by SignalASI]" : value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func sensitive(_ value: String) -> Bool {
    let normalized = value.lowercased()
    return AgentLearningAnalyzer.containsSensitiveData(value) || sensitiveTerms.contains { normalized.contains($0) }
  }

  private static let sensitiveTerms = [
    "identity_key", "identity key", "identity_key_sha256", "private key", "mnemonic",
    "mqtt password", "mqtt_password", "api key", "api_key", "access token", "access_token",
    "refresh token", "refresh_token", "signalasi fingerprint",
    "\u{8EAB}\u{4EFD}\u{6307}\u{7EB9}", "\u{79C1}\u{94A5}", "\u{52A9}\u{8BB0}\u{8BCD}",
    "mqtt \u{5BC6}\u{7801}", "api \u{5BC6}\u{94A5}"
  ]
  private static let metadataSecretPattern = #"(?i)(?:[?&]|^)(?:access_token|refresh_token|token|api_key|key|password)=[^&\s]+"#
}
