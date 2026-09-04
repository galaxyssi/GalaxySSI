import Foundation

/// Keeps only short-lived, consent-bearing Whisper capabilities announced by paired desktops.
/// The encrypted persistence lets a cold-started voice session use a recent verified manifest.
final class VoiceRemoteWhisperNodeRegistry {
  static let shared = VoiceRemoteWhisperNodeRegistry()

  static let maximumManifestAgeMillis: Int64 = 5 * 60 * 1_000
  private static let storageKey = "galaxyssi.voice.remote_whisper_nodes.v1"

  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.secrets = secrets
  }

  func ingest(
    payload: [String: Any],
    sourceDesktopID: String,
    nowMillis: Int64 = VoiceRemoteWhisperNodeRegistry.nowMillis()
  ) {
    let source = sourceDesktopID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard payload.string("type") == "capability_manifest" else { return }
    var nodes = load()
    if let node = VoiceRemoteWhisperProtocol.parseCapability(
      payload,
      sourceDesktopID: source,
      generatedAtMillis: payload.integer64("generated_at", fallback: nowMillis)
    ) {
      nodes[node.desktopID] = node
    } else if !source.isEmpty {
      nodes.removeValue(forKey: source)
    }
    save(nodes)
  }

  func all(
    nowMillis: Int64 = VoiceRemoteWhisperNodeRegistry.nowMillis(),
    linkIsValid: (VoiceRemoteWhisperNodeCapability) -> Bool
  ) -> [VoiceRemoteWhisperNodeCapability] {
    var nodes = load()
    let active = nodes.values.filter { node in
      let age = nowMillis - node.generatedAtMillis
      return age >= 0 && age <= Self.maximumManifestAgeMillis && linkIsValid(node)
    }
    let activeIDs = Set(active.map(\.desktopID))
    if activeIDs.count != nodes.count {
      nodes = Dictionary(uniqueKeysWithValues: active.map { ($0.desktopID, $0) })
      save(nodes)
    }
    return active.sorted { left, right in
      let leftRank = modelRank(left.activeProfile.id)
      let rightRank = modelRank(right.activeProfile.id)
      if leftRank != rightRank { return leftRank > rightRank }
      if left.generatedAtMillis != right.generatedAtMillis {
        return left.generatedAtMillis > right.generatedAtMillis
      }
      return left.desktopID < right.desktopID
    }
  }

  func best(
    nowMillis: Int64 = VoiceRemoteWhisperNodeRegistry.nowMillis(),
    linkIsValid: (VoiceRemoteWhisperNodeCapability) -> Bool
  ) -> VoiceRemoteWhisperNodeCapability? {
    all(nowMillis: nowMillis, linkIsValid: linkIsValid).first
  }

  func remove(desktopID: String) {
    let desktopID = desktopID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !desktopID.isEmpty else { return }
    var nodes = load()
    guard nodes.removeValue(forKey: desktopID) != nil else { return }
    save(nodes)
  }

  func clear() {
    GalaxySSIEncryptedUserDefaultsStore.destroy(
      defaults: defaults,
      key: Self.storageKey,
      secrets: secrets
    )
  }

  private func load() -> [String: VoiceRemoteWhisperNodeCapability] {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: Self.storageKey,
      secrets: secrets
    ), data.count <= 128 * 1_024,
      let decoded = try? JSONDecoder().decode([String: VoiceRemoteWhisperNodeCapability].self, from: data) else {
      return [:]
    }
    return decoded.filter { key, value in key == value.desktopID }
  }

  private func save(_ nodes: [String: VoiceRemoteWhisperNodeCapability]) {
    guard nodes.count <= 32,
          let data = try? JSONEncoder().encode(nodes),
          data.count <= 128 * 1_024 else {
      return
    }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(
      data,
      defaults: defaults,
      key: Self.storageKey,
      secrets: secrets
    )
  }

  private func modelRank(_ profileID: String) -> Int {
    switch profileID.lowercased() {
    case "large-v3-turbo": return 2
    case "large-v3": return 1
    default: return 0
    }
  }

  private static func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}

private extension Dictionary where Key == String, Value == Any {
  func integer64(_ key: String, fallback: Int64) -> Int64 {
    if let value = self[key] as? Int64 { return value }
    if let value = self[key] as? Int { return Int64(value) }
    if let value = self[key] as? NSNumber { return value.int64Value }
    return fallback
  }
}
