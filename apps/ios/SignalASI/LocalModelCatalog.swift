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
    guard (profile.sourceTrust == .hubVerified || profile.sourceTrust == .signedDeployment),
          profile.catalogPersistable else { return }
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
    profiles(defaults: defaults).first { $0.id == id } ?? LocalModelRuntimeProfiles.find(id)
  }

  static func addHubArtifact(
    _ artifact: LocalModelHubArtifact,
    defaults: UserDefaults = .standard
  ) -> LocalModelRuntimeProfile {
    let profile = profile(for: artifact, defaults: defaults)
    if profile.sourceTrust == .hubVerified {
      LocalModelProfileStore(defaults: defaults).upsert(profile)
    }
    return profile
  }

  static func addSignedDeployment(
    _ profile: LocalModelRuntimeProfile,
    defaults: UserDefaults = .standard
  ) {
    guard profile.sourceTrust == .signedDeployment else { return }
    LocalModelProfileStore(defaults: defaults).upsert(profile)
  }

  static func profile(
    for artifact: LocalModelHubArtifact,
    defaults: UserDefaults = .standard
  ) -> LocalModelRuntimeProfile {
    profiles(defaults: defaults).first {
      $0.repositoryId == artifact.repositoryId &&
        $0.fileName == artifact.fileName &&
        $0.sha256.caseInsensitiveCompare(artifact.sha256) == .orderedSame &&
        $0.sourceHub == artifact.source
    } ?? hubProfile(for: artifact)
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
      visionCapable: artifact.visionCapable,
      sourceTrust: .hubVerified,
      sourceHub: artifact.source
    )
    return profile
  }

  static func artifact(for profile: LocalModelRuntimeProfile) -> LocalModelHubArtifact? {
    guard profile.downloadable,
          let encodedRepository = profile.repositoryId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let encodedFileName = profile.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
      return nil
    }
    let downloadURL: URL?
    switch profile.sourceHub {
    case .huggingFace:
      downloadURL = URL(string: "https://huggingface.co/\(encodedRepository)/resolve/main/\(encodedFileName)")
    case .modelScope:
      var components = URLComponents(string: "https://modelscope.cn/api/v1/models/\(encodedRepository)/repo")
      components?.queryItems = [
        URLQueryItem(name: "Revision", value: "master"),
        URLQueryItem(name: "FilePath", value: profile.fileName)
      ]
      downloadURL = components?.url
    }
    guard let downloadURL else { return nil }
    return LocalModelHubArtifact(
      repositoryId: profile.repositoryId,
      fileName: profile.fileName,
      sizeBytes: profile.expectedModelFileBytes,
      sha256: profile.sha256,
      quantization: profile.quantizationLabel,
      parameterCountBillions: profile.parameterCountBillions,
      downloadURL: downloadURL,
      source: profile.sourceHub,
      visionCapable: profile.visionCapable
    )
  }

  static func removeHubProfile(_ profile: LocalModelRuntimeProfile, defaults: UserDefaults = .standard) {
    removeProfile(profile, defaults: defaults)
  }

  static func removeProfile(_ profile: LocalModelRuntimeProfile, defaults: UserDefaults = .standard) {
    guard profile.sourceTrust == .hubVerified || profile.sourceTrust == .signedDeployment else { return }
    LocalModelProfileStore(defaults: defaults).delete(profileId: profile.id)
    LocalModelRuntimeSettings.removeProfile(profile.id, defaults: defaults)
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
