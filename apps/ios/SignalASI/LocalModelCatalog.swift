import Foundation

struct LocalModelProfileStore {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func list() -> [LocalModelRuntimeProfile] {
    guard let data = defaults.data(forKey: Self.key) else { return [] }
    return (try? JSONDecoder().decode([LocalModelRuntimeProfile].self, from: data)) ?? []
  }

  func upsert(_ profile: LocalModelRuntimeProfile) {
    guard profile.sourceTrust == .hubVerified, profile.downloadable else { return }
    let updated = (list().filter { $0.id != profile.id } + [profile])
      .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    guard let data = try? JSONEncoder().encode(updated) else { return }
    defaults.set(data, forKey: Self.key)
  }

  func delete(profileId: String) {
    let updated = list().filter { $0.id != profileId }
    guard let data = try? JSONEncoder().encode(updated) else { return }
    defaults.set(data, forKey: Self.key)
  }

  private static let key = "signalasi_local_model_catalog_v1.hub_profiles"
}

enum LocalModelRuntimeCatalog {
  static func profiles(defaults: UserDefaults = .standard) -> [LocalModelRuntimeProfile] {
    var values: [LocalModelRuntimeProfile] = []
    for profile in LocalModelRuntimeProfiles.all + LocalModelProfileStore(defaults: defaults).list() {
      if !values.contains(where: { $0.id == profile.id }) {
        values.append(profile)
      }
    }
    return values
  }

  static func find(_ id: String, defaults: UserDefaults = .standard) -> LocalModelRuntimeProfile {
    profiles(defaults: defaults).first { $0.id == id } ?? LocalModelRuntimeProfiles.GEMMA_3_4B_Q4
  }

  static func addHubArtifact(
    _ artifact: LocalModelHubArtifact,
    defaults: UserDefaults = .standard
  ) -> LocalModelRuntimeProfile {
    let profile = hubProfile(for: artifact)
    LocalModelProfileStore(defaults: defaults).upsert(profile)
    return profile
  }

  static func hubProfile(for artifact: LocalModelHubArtifact) -> LocalModelRuntimeProfile {
    let shape = estimatedShape(parameterCountBillions: artifact.parameterCountBillions)
    let repositoryKey = artifact.repositoryId
      .lowercased()
      .map { character in
        character.isLetter || character.isNumber ? String(character) : "-"
      }
      .joined()
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let profile = LocalModelRuntimeProfile(
      id: "hub-\(artifact.source.rawValue.lowercased())-\(String(repositoryKey.prefix(40)))-\(String(artifact.sha256.prefix(12)))",
      displayName: artifact.displayName,
      expectedModelFileBytes: artifact.sizeBytes,
      layerCount: shape.layers,
      keyValueHeadCount: shape.keyValueHeads,
      headDimension: shape.headDimension,
      defaultContextTokens: 4_096,
      maximumContextTokens: 32_768,
      quantizationLabel: artifact.quantization,
      repositoryId: artifact.repositoryId,
      fileName: artifact.fileName,
      sha256: artifact.sha256,
      parameterCountBillions: artifact.parameterCountBillions,
      defaultNoThink: artifact.repositoryId.localizedCaseInsensitiveContains("qwen3") &&
        !artifact.repositoryId.localizedCaseInsensitiveContains("qwen3.5"),
      sourceTrust: .hubVerified,
      sourceHub: artifact.source
    )
  }

  static func removeHubProfile(_ profile: LocalModelRuntimeProfile, defaults: UserDefaults = .standard) {
    guard profile.sourceTrust == .hubVerified else { return }
    let wasSelected = LocalModelRuntimeSettings.selectedProfile(defaults: defaults).id == profile.id
    LocalModelProfileStore(defaults: defaults).delete(profileId: profile.id)
    if wasSelected {
      defaults.set(LocalModelRuntimeProfiles.GEMMA_3_4B_Q4.id, forKey: "signalasi_local_model_runtime_v1.profile")
    }
  }

  private struct EstimatedShape {
    var layers: Int
    var keyValueHeads: Int
    var headDimension: Int
  }

  private static func estimatedShape(parameterCountBillions: Double) -> EstimatedShape {
    switch parameterCountBillions {
    case ..<1.5:
      return EstimatedShape(layers: 26, keyValueHeads: 4, headDimension: 128)
    case ..<5:
      return EstimatedShape(layers: 36, keyValueHeads: 8, headDimension: 128)
    case ..<10:
      return EstimatedShape(layers: 36, keyValueHeads: 8, headDimension: 128)
    case ..<14:
      return EstimatedShape(layers: 48, keyValueHeads: 8, headDimension: 128)
    default:
      return EstimatedShape(layers: 64, keyValueHeads: 8, headDimension: 128)
    }
  }
}
