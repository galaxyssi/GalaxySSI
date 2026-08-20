import CryptoKit
import Foundation

enum AgentRuntimeGuestProtocol {
  static let version = 1
}

struct AgentEmbeddedRuntimePack: Codable, Equatable, Identifiable {
  var packId: String
  var version: String
  var architecture: String
  var assetPath: String
  var archiveSha256: String
  var archiveSizeBytes: Int64
  var installedSizeBytes: Int64
  var dependencies: [String]

  var id: String { packId }

  init(
    packId: String,
    version: String,
    architecture: String,
    assetPath: String,
    archiveSha256: String,
    archiveSizeBytes: Int64,
    installedSizeBytes: Int64,
    dependencies: [String] = []
  ) {
    self.packId = packId
    self.version = version
    self.architecture = architecture
    self.assetPath = assetPath
    self.archiveSha256 = archiveSha256.lowercased()
    self.archiveSizeBytes = archiveSizeBytes
    self.installedSizeBytes = installedSizeBytes
    self.dependencies = dependencies
  }

  enum CodingKeys: String, CodingKey {
    case packId = "pack_id"
    case version
    case architecture
    case assetPath = "asset_path"
    case archiveSha256 = "archive_sha256"
    case archiveSizeBytes = "archive_size_bytes"
    case installedSizeBytes = "installed_size_bytes"
    case dependencies
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      packId: try container.decode(String.self, forKey: .packId),
      version: try container.decode(String.self, forKey: .version),
      architecture: try container.decode(String.self, forKey: .architecture),
      assetPath: try container.decode(String.self, forKey: .assetPath),
      archiveSha256: try container.decode(String.self, forKey: .archiveSha256),
      archiveSizeBytes: try container.decode(Int64.self, forKey: .archiveSizeBytes),
      installedSizeBytes: try container.decode(Int64.self, forKey: .installedSizeBytes),
      dependencies: try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
    )
  }
}

struct AgentEmbeddedRuntimeBundle: Codable, Equatable {
  var architecture: String
  var packs: [AgentEmbeddedRuntimePack]
  var formatVersion: Int

  init(
    architecture: String,
    packs: [AgentEmbeddedRuntimePack],
    formatVersion: Int = 1
  ) {
    self.architecture = architecture
    self.packs = packs
    self.formatVersion = formatVersion
  }

  enum CodingKeys: String, CodingKey {
    case architecture
    case packs
    case formatVersion = "format_version"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      architecture: try container.decode(String.self, forKey: .architecture),
      packs: try container.decodeIfPresent([AgentEmbeddedRuntimePack].self, forKey: .packs) ?? [],
      formatVersion: try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 0
    )
  }
}

struct AgentEmbeddedRuntimeBootstrapResult: Codable, Equatable {
  var bundled: Bool
  var installed: [String]
  var retained: [String]

  init(
    bundled: Bool,
    installed: [String] = [],
    retained: [String] = []
  ) {
    self.bundled = bundled
    self.installed = installed
    self.retained = retained
  }
}

enum AgentEmbeddedRuntimeBundleCodec {
  static func decode(_ raw: String) throws -> AgentEmbeddedRuntimeBundle {
    let size = Data(raw.utf8).count
    guard (1...maxIndexBytes).contains(size) else {
      throw AgentRuntimeCapabilityError.invalid("Embedded runtime index exceeds the size limit")
    }
    let bundle = try JSONDecoder().decode(AgentEmbeddedRuntimeBundle.self, from: Data(raw.utf8))
    try validate(bundle)
    return bundle
  }

  private static func validate(_ bundle: AgentEmbeddedRuntimeBundle) throws {
    guard bundle.formatVersion == 1 else {
      throw AgentRuntimeCapabilityError.invalid("Embedded runtime index version is unsupported")
    }
    guard bundle.architecture == defaultArchitecture else {
      throw AgentRuntimeCapabilityError.invalid("Embedded runtime architecture is unsupported")
    }
    guard bundle.packs.map(\.packId) == defaultPacks else {
      throw AgentRuntimeCapabilityError.invalid("Embedded runtime must contain linux-base followed by python-uv")
    }
    for pack in bundle.packs {
      guard pack.architecture == defaultArchitecture, matches(pack.version, versionPattern) else {
        throw AgentRuntimeCapabilityError.invalid("Embedded runtime pack is incompatible: \(pack.packId)")
      }
      guard matches(pack.assetPath, assetPathPattern), matches(pack.archiveSha256, sha256Pattern) else {
        throw AgentRuntimeCapabilityError.invalid("Embedded runtime pack metadata is invalid: \(pack.packId)")
      }
      guard (1...maxArchiveBytes).contains(pack.archiveSizeBytes),
            (1...maxInstalledBytes).contains(pack.installedSizeBytes) else {
        throw AgentRuntimeCapabilityError.invalid("Embedded runtime pack size is invalid: \(pack.packId)")
      }
      guard Set(pack.dependencies).count == pack.dependencies.count,
            pack.dependencies.allSatisfy({ defaultPacks.contains($0) && $0 != pack.packId }) else {
        throw AgentRuntimeCapabilityError.invalid("Embedded runtime pack dependencies are invalid: \(pack.packId)")
      }
    }
    guard bundle.packs.first?.dependencies.isEmpty == true else {
      throw AgentRuntimeCapabilityError.invalid("linux-base cannot depend on another embedded pack")
    }
    guard bundle.packs.last?.dependencies == ["linux-base"] else {
      throw AgentRuntimeCapabilityError.invalid("python-uv must depend on linux-base")
    }
  }

  private static func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }

  private static let maxIndexBytes = 64 * 1_024
  private static let maxArchiveBytes: Int64 = 6 * 1_024 * 1_024 * 1_024
  private static let maxInstalledBytes: Int64 = 12 * 1_024 * 1_024 * 1_024
  private static let defaultArchitecture = "arm64-v8a"
  private static let defaultPacks = ["linux-base", "python-uv"]
  private static let versionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z._-]+)?$"#
  private static let sha256Pattern = #"^[0-9a-f]{64}$"#
  private static let assetPathPattern = #"^runtime/bootstrap/[A-Za-z0-9._+-]+\.sarpack$"#
}

enum AgentEmbeddedRuntimeBootstrap {
  static func compareVersions(_ left: String, _ right: String) -> Int {
    let leftValue = left.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    let rightValue = right.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    let leftRelease = leftValue.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    let rightRelease = rightValue.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    let leftParts = leftRelease.split(separator: ".").map { Int($0) ?? 0 }
    let rightParts = rightRelease.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(leftParts.count, rightParts.count) {
      let comparison = (leftParts.indices.contains(index) ? leftParts[index] : 0) -
        (rightParts.indices.contains(index) ? rightParts[index] : 0)
      if comparison != 0 {
        return comparison > 0 ? 1 : -1
      }
    }
    let leftPrerelease = prerelease(leftValue)
    let rightPrerelease = prerelease(rightValue)
    switch (leftPrerelease, rightPrerelease) {
    case (nil, nil):
      return 0
    case (nil, _):
      return 1
    case (_, nil):
      return -1
    case (let left?, let right?):
      if left == right { return 0 }
      return left < right ? -1 : 1
    }
  }

  private static func prerelease(_ value: String) -> String? {
    let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[1].isEmpty else { return nil }
    return String(parts[1])
  }
}

enum AgentRuntimePackState: String, Codable, CaseIterable, Identifiable {
  case ready = "ready"
  case notInstalled = "not_installed"
  case invalid = "invalid"
  case incompatible = "incompatible"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRuntimePackState {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_")
    return allCases.first { $0.rawValue == normalized } ?? .notInstalled
  }
}

enum AgentRuntimeLanguage: String, Codable, CaseIterable, Identifiable {
  case shell = "shell"
  case python = "python"
  case uv = "uv"
  case javascript = "javascript"
  case typescript = "typescript"
  case go = "go"
  case rust = "rust"
  case c = "c"
  case cpp = "cpp"
  case java = "java"
  case browser = "browser"
  case ffmpeg = "ffmpeg"
  case ffprobe = "ffprobe"

  var id: String { rawValue }

  var requiredPack: String {
    switch self {
    case .shell:
      return "linux-base"
    case .python, .uv:
      return "python-uv"
    case .javascript, .typescript:
      return "node-js"
    case .go:
      return "go"
    case .rust:
      return "rust"
    case .c, .cpp:
      return "cpp"
    case .java:
      return "java"
    case .browser:
      return "browser-automation"
    case .ffmpeg, .ffprobe:
      return "ffmpeg"
    }
  }

  var requiredCapability: String {
    switch self {
    case .shell:
      return "shell.execute"
    case .python:
      return "python.execute"
    case .uv:
      return "uv.sync"
    case .javascript:
      return "javascript.execute"
    case .typescript:
      return "typescript.execute"
    case .go:
      return "go.execute"
    case .rust:
      return "rust.execute"
    case .c:
      return "c.execute"
    case .cpp:
      return "cpp.execute"
    case .java:
      return "java.execute"
    case .browser:
      return "browser.automation.execute"
    case .ffmpeg:
      return "ffmpeg.execute"
    case .ffprobe:
      return "ffprobe.inspect"
    }
  }
}

struct AgentRuntimePackManifest: Codable, Equatable {
  var id: String
  var version: String
  var architecture: String
  var imageFile: String
  var imageSha256: String
  var capabilities: [String]
  var dependencies: [String]
  var installedSizeBytes: Int64
  var license: String
  var signatureKeyId: String
  var signature: String
  var formatVersion: Int
  var archiveSizeBytes: Int64
  var minimumHostVersionCode: Int64
  var guestApiVersion: Int

  init(
    id: String,
    version: String,
    architecture: String,
    imageFile: String,
    imageSha256: String,
    capabilities: [String],
    dependencies: [String],
    installedSizeBytes: Int64,
    license: String,
    signatureKeyId: String,
    signature: String,
    formatVersion: Int = 1,
    archiveSizeBytes: Int64 = 0,
    minimumHostVersionCode: Int64 = 1,
    guestApiVersion: Int = AgentRuntimeGuestProtocol.version
  ) {
    self.id = id
    self.version = version
    self.architecture = architecture
    self.imageFile = imageFile
    self.imageSha256 = imageSha256
    self.capabilities = capabilities
    self.dependencies = dependencies
    self.installedSizeBytes = installedSizeBytes
    self.license = license
    self.signatureKeyId = signatureKeyId
    self.signature = signature
    self.formatVersion = formatVersion
    self.archiveSizeBytes = archiveSizeBytes
    self.minimumHostVersionCode = minimumHostVersionCode
    self.guestApiVersion = guestApiVersion
  }

  enum CodingKeys: String, CodingKey {
    case id
    case version
    case architecture
    case imageFile = "image_file"
    case imageSha256 = "image_sha256"
    case capabilities
    case dependencies
    case installedSizeBytes = "installed_size_bytes"
    case license
    case signatureKeyId = "signature_key_id"
    case signature
    case formatVersion = "format_version"
    case archiveSizeBytes = "archive_size_bytes"
    case minimumHostVersionCode = "minimum_host_version_code"
    case guestApiVersion = "guest_api_version"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(String.self, forKey: .id),
      version: try container.decode(String.self, forKey: .version),
      architecture: try container.decode(String.self, forKey: .architecture),
      imageFile: try container.decode(String.self, forKey: .imageFile),
      imageSha256: try container.decode(String.self, forKey: .imageSha256),
      capabilities: try container.decodeIfPresent([String].self, forKey: .capabilities) ?? [],
      dependencies: try container.decodeIfPresent([String].self, forKey: .dependencies) ?? [],
      installedSizeBytes: try container.decode(Int64.self, forKey: .installedSizeBytes),
      license: try container.decode(String.self, forKey: .license),
      signatureKeyId: try container.decode(String.self, forKey: .signatureKeyId),
      signature: try container.decode(String.self, forKey: .signature),
      formatVersion: try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1,
      archiveSizeBytes: try container.decodeIfPresent(Int64.self, forKey: .archiveSizeBytes) ?? 0,
      minimumHostVersionCode: try container.decodeIfPresent(Int64.self, forKey: .minimumHostVersionCode) ?? 1,
      guestApiVersion: try container.decodeIfPresent(Int.self, forKey: .guestApiVersion) ?? 1
    )
  }

  func signingPayload() -> Data {
    let values = [
      String(formatVersion),
      id,
      version,
      architecture,
      imageFile,
      imageSha256.lowercased(),
      capabilities.sorted().joined(separator: ","),
      dependencies.sorted().joined(separator: ","),
      String(installedSizeBytes),
      String(archiveSizeBytes),
      String(minimumHostVersionCode),
      String(guestApiVersion),
      license,
      signatureKeyId.lowercased()
    ]
    return Data(values.map { "\($0.utf8.count):\($0)" }.joined().utf8)
  }
}

struct AgentRuntimePackStatus: Codable, Equatable, Identifiable {
  var id: String
  var state: AgentRuntimePackState
  var reason: String
  var manifest: AgentRuntimePackManifest?

  init(
    id: String,
    state: AgentRuntimePackState,
    reason: String = "",
    manifest: AgentRuntimePackManifest? = nil
  ) {
    self.id = id
    self.state = state
    self.reason = reason
    self.manifest = manifest
  }
}

struct AgentRuntimePackCatalogEntry: Codable, Equatable, Identifiable {
  var packId: String
  var version: String
  var architecture: String
  var downloadUrl: String
  var archiveSha256: String
  var archiveSizeBytes: Int64
  var installedSizeBytes: Int64
  var dependencies: [String]
  var license: String
  var minimumHostVersionCode: Int64
  var guestApiVersion: Int
  var releaseNotes: String

  var id: String { "\(packId)|\(architecture)" }

  init(
    packId: String,
    version: String,
    architecture: String,
    downloadUrl: String,
    archiveSha256: String,
    archiveSizeBytes: Int64,
    installedSizeBytes: Int64,
    dependencies: [String],
    license: String,
    minimumHostVersionCode: Int64,
    guestApiVersion: Int,
    releaseNotes: String = ""
  ) {
    self.packId = packId
    self.version = version
    self.architecture = architecture
    self.downloadUrl = downloadUrl
    self.archiveSha256 = archiveSha256
    self.archiveSizeBytes = archiveSizeBytes
    self.installedSizeBytes = installedSizeBytes
    self.dependencies = dependencies
    self.license = license
    self.minimumHostVersionCode = minimumHostVersionCode
    self.guestApiVersion = guestApiVersion
    self.releaseNotes = releaseNotes
  }

  enum CodingKeys: String, CodingKey {
    case packId = "pack_id"
    case version
    case architecture
    case downloadUrl = "download_url"
    case archiveSha256 = "archive_sha256"
    case archiveSizeBytes = "archive_size_bytes"
    case installedSizeBytes = "installed_size_bytes"
    case dependencies
    case license
    case minimumHostVersionCode = "minimum_host_version_code"
    case guestApiVersion = "guest_api_version"
    case releaseNotes = "release_notes"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      packId: try container.decode(String.self, forKey: .packId),
      version: try container.decode(String.self, forKey: .version),
      architecture: try container.decode(String.self, forKey: .architecture),
      downloadUrl: try container.decode(String.self, forKey: .downloadUrl),
      archiveSha256: try container.decode(String.self, forKey: .archiveSha256),
      archiveSizeBytes: try container.decode(Int64.self, forKey: .archiveSizeBytes),
      installedSizeBytes: try container.decode(Int64.self, forKey: .installedSizeBytes),
      dependencies: try container.decodeIfPresent([String].self, forKey: .dependencies) ?? [],
      license: try container.decode(String.self, forKey: .license),
      minimumHostVersionCode: try container.decodeIfPresent(Int64.self, forKey: .minimumHostVersionCode) ?? 1,
      guestApiVersion: try container.decodeIfPresent(Int.self, forKey: .guestApiVersion) ?? 1,
      releaseNotes: try container.decodeIfPresent(String.self, forKey: .releaseNotes) ?? ""
    )
  }

  func canonicalValue() -> String {
    let values = [
      packId,
      version,
      architecture,
      downloadUrl,
      archiveSha256.lowercased(),
      String(archiveSizeBytes),
      String(installedSizeBytes),
      dependencies.sorted().joined(separator: ","),
      license,
      String(minimumHostVersionCode),
      String(guestApiVersion),
      releaseNotes
    ]
    return values.map { "\($0.utf8.count):\($0)" }.joined()
  }
}

struct AgentRuntimePackCatalog: Codable, Equatable {
  var formatVersion: Int
  var catalogVersion: String
  var generatedAtMillis: Int64
  var expiresAtMillis: Int64
  var entries: [AgentRuntimePackCatalogEntry]
  var signatureKeyId: String
  var signature: String

  init(
    catalogVersion: String,
    generatedAtMillis: Int64,
    expiresAtMillis: Int64,
    entries: [AgentRuntimePackCatalogEntry],
    signatureKeyId: String,
    signature: String,
    formatVersion: Int = 1
  ) {
    self.formatVersion = formatVersion
    self.catalogVersion = catalogVersion
    self.generatedAtMillis = generatedAtMillis
    self.expiresAtMillis = expiresAtMillis
    self.entries = entries
    self.signatureKeyId = signatureKeyId
    self.signature = signature
  }

  enum CodingKeys: String, CodingKey {
    case formatVersion = "format_version"
    case catalogVersion = "catalog_version"
    case generatedAtMillis = "generated_at_millis"
    case expiresAtMillis = "expires_at_millis"
    case entries
    case signatureKeyId = "signature_key_id"
    case signature
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      catalogVersion: try container.decode(String.self, forKey: .catalogVersion),
      generatedAtMillis: try container.decode(Int64.self, forKey: .generatedAtMillis),
      expiresAtMillis: try container.decode(Int64.self, forKey: .expiresAtMillis),
      entries: try container.decodeIfPresent([AgentRuntimePackCatalogEntry].self, forKey: .entries) ?? [],
      signatureKeyId: try container.decode(String.self, forKey: .signatureKeyId),
      signature: try container.decode(String.self, forKey: .signature),
      formatVersion: try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
    )
  }

  func signingPayload() -> Data {
    let sortedEntries = entries.sorted {
      if $0.packId != $1.packId {
        return $0.packId < $1.packId
      }
      if $0.architecture != $1.architecture {
        return $0.architecture < $1.architecture
      }
      return $0.version < $1.version
    }
    var payload = "\(formatVersion)\n\(catalogVersion)\n\(generatedAtMillis)\n\(expiresAtMillis)\n"
    for entry in sortedEntries {
      payload += entry.canonicalValue()
      payload += "\n"
    }
    payload += signatureKeyId.lowercased()
    return Data(payload.utf8)
  }
}

enum AgentRuntimePackInstallStage: String, Codable, CaseIterable, Identifiable {
  case preparing = "PREPARING"
  case copying = "COPYING"
  case extracting = "EXTRACTING"
  case verifying = "VERIFYING"
  case activating = "ACTIVATING"
  case completed = "COMPLETED"

  var id: String { rawValue }
}

struct AgentRuntimePackInstallProgress: Codable, Equatable {
  var stage: AgentRuntimePackInstallStage
  var processedBytes: Int64
  var totalBytes: Int64

  init(
    stage: AgentRuntimePackInstallStage,
    processedBytes: Int64 = 0,
    totalBytes: Int64 = -1
  ) {
    self.stage = stage
    self.processedBytes = processedBytes
    self.totalBytes = totalBytes
  }

  enum CodingKeys: String, CodingKey {
    case stage
    case processedBytes = "processed_bytes"
    case totalBytes = "total_bytes"
  }
}

struct AgentRuntimePackInstallResult: Codable, Equatable {
  var packId: String
  var version: String
  var state: AgentRuntimePackState
  var installedBytes: Int64
  var replacedExisting: Bool
  var reason: String

  init(
    packId: String,
    version: String,
    state: AgentRuntimePackState,
    installedBytes: Int64,
    replacedExisting: Bool,
    reason: String = ""
  ) {
    self.packId = packId
    self.version = version
    self.state = state
    self.installedBytes = installedBytes
    self.replacedExisting = replacedExisting
    self.reason = reason
  }

  enum CodingKeys: String, CodingKey {
    case packId = "pack_id"
    case version
    case state
    case installedBytes = "installed_bytes"
    case replacedExisting = "replaced_existing"
    case reason
  }
}

enum AgentRuntimeDistributionSources {
  static let githubCatalogURL =
    "https://github.com/signalasi/SignalASI/releases/download/android-runtime-v1/android-runtime-catalog-v1.json"

  static func catalogCandidates(languageTag: String) -> [String] {
    downloadCandidates(url: githubCatalogURL, languageTag: languageTag)
  }

  static func downloadCandidates(url: String, languageTag: String) -> [String] {
    guard isChinese(languageTag), isSignalAsiGitHubReleaseURL(url) else {
      return [url]
    }
    var seen = Set<String>()
    return (chinaAcceleratorPrefixes.map { "\($0)\(url)" } + [url]).filter { seen.insert($0).inserted }
  }

  private static func isChinese(_ languageTag: String) -> Bool {
    let normalized = languageTag
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: "-")
    return normalized == "zh" || normalized.hasPrefix("zh-")
  }

  private static func isSignalAsiGitHubReleaseURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value) else {
      return false
    }
    return components.scheme?.lowercased() == "https" &&
      components.host?.lowercased() == "github.com" &&
      components.path.hasPrefix(signalASIReleasePath)
  }

  private static let signalASIReleasePath = "/signalasi/SignalASI/releases/download/"
  private static let chinaAcceleratorPrefixes = [
    "https://ghfast.top/",
    "https://ghproxy.net/",
    "https://gh-proxy.com/"
  ]
}

enum AgentRuntimePackCatalogPolicy {
  static let linuxBaseRecoveryVersion = "1.3.9"

  static let requiredPacks = [
    "linux-base",
    "python-uv",
    "node-js",
    "go",
    "rust",
    "cpp",
    "java",
    "browser-automation",
    "ffmpeg"
  ]

  static let requiredPackCapabilities: [String: Set<String>] =
    Dictionary(grouping: AgentRuntimeLanguage.allCases, by: \.requiredPack)
      .mapValues { Set($0.map(\.requiredCapability)) }

  static var defaultSupportedArchitectures: [String] {
    #if arch(arm64)
      return ["arm64", "arm64-v8a"]
    #elseif arch(x86_64)
      return ["x86_64", "x86"]
    #else
      return []
    #endif
  }

  @discardableResult
  static func validate(
    _ catalog: AgentRuntimePackCatalog,
    nowMillis: Int64,
    verifier: (AgentRuntimePackCatalog) -> Bool
  ) throws -> AgentRuntimePackCatalog {
    try require(catalog.formatVersion == formatVersion, "Runtime catalog format is incompatible")
    try require(matches(catalog.catalogVersion, versionPattern), "Runtime catalog version is invalid")
    try require(
      catalog.generatedAtMillis > 0 && catalog.generatedAtMillis <= nowMillis + clockSkewMillis,
      "Runtime catalog generation time is invalid"
    )
    try require(
      catalog.expiresAtMillis > catalog.generatedAtMillis && catalog.expiresAtMillis >= nowMillis,
      "Runtime catalog is expired"
    )
    try require((1...maxEntries).contains(catalog.entries.count), "Runtime catalog entry count is invalid")
    try require(matches(catalog.signatureKeyId, sha256Pattern), "Runtime catalog signing key id is invalid")
    try require(!catalog.signature.isEmpty, "Runtime catalog signature is missing")

    var identities = Set<String>()
    for entry in catalog.entries {
      try validate(entry)
      try require(
        identities.insert("\(entry.packId)|\(entry.architecture)").inserted,
        "Runtime catalog contains duplicate pack entries"
      )
    }
    try validateDependencyGraphs(catalog.entries)
    try require(verifier(catalog), "Runtime catalog signature is not trusted")
    return catalog
  }

  static func compatibleEntries(
    in catalog: AgentRuntimePackCatalog,
    supportedArchitectures: [String] = defaultSupportedArchitectures,
    hostVersionCode: Int64,
    guestApiVersion: Int = AgentRuntimeGuestProtocol.version
  ) -> [AgentRuntimePackCatalogEntry] {
    catalog.entries.filter { entry in
      supportedArchitectures.contains(entry.architecture) &&
        entry.minimumHostVersionCode <= hostVersionCode &&
        entry.guestApiVersion == guestApiVersion
    }
  }

  static func meetsLinuxBaseRecoveryBaseline(_ version: String) -> Bool {
    AgentEmbeddedRuntimeBootstrap.compareVersions(version, linuxBaseRecoveryVersion) >= 0
  }

  static func validateReplacement(
    previous: AgentRuntimePackCatalog?,
    candidate: AgentRuntimePackCatalog
  ) throws {
    guard let previous else {
      return
    }
    try require(
      candidate.generatedAtMillis >= previous.generatedAtMillis,
      "Runtime catalog rollback was rejected"
    )
    if candidate.generatedAtMillis == previous.generatedAtMillis {
      try require(
        candidate.signingPayload() == previous.signingPayload(),
        "Runtime catalog generation was reused with different content"
      )
    }
  }

  private static func validate(_ entry: AgentRuntimePackCatalogEntry) throws {
    try require(requiredPacks.contains(entry.packId), "Runtime catalog pack id is unsupported")
    try require(matches(entry.version, versionPattern), "Runtime catalog pack version is invalid")
    try require(matches(entry.architecture, architecturePattern), "Runtime catalog architecture is invalid")
    try require(matches(entry.archiveSha256, sha256Pattern), "Runtime catalog archive digest is invalid")
    try require((1...maxArchiveBytes).contains(entry.archiveSizeBytes), "Runtime catalog archive size is invalid")
    try require((1...maxInstalledBytes).contains(entry.installedSizeBytes), "Runtime catalog installed size is invalid")
    try require(
      Set(entry.dependencies).count == entry.dependencies.count &&
        entry.dependencies.allSatisfy { requiredPacks.contains($0) && $0 != entry.packId },
      "Runtime catalog dependencies are invalid"
    )
    try require(!entry.license.isEmpty && entry.license.count <= 256, "Runtime catalog license is invalid")
    try require(
      entry.minimumHostVersionCode > 0 && entry.guestApiVersion > 0,
      "Runtime catalog compatibility metadata is invalid"
    )
    try require(
      entry.releaseNotes.count <= maxReleaseNotesCharacters &&
        !entry.canonicalValue().contains("\n") &&
        !entry.canonicalValue().contains("\r"),
      "Runtime catalog text is invalid"
    )
    try validateHTTPSURL(entry.downloadUrl)
  }

  private static func validateDependencyGraphs(_ entries: [AgentRuntimePackCatalogEntry]) throws {
    let entriesByArchitecture = Dictionary(grouping: entries, by: \.architecture)
    for (architecture, architectureEntries) in entriesByArchitecture {
      let entriesById = Dictionary(uniqueKeysWithValues: architectureEntries.map { ($0.packId, $0) })
      for entry in architectureEntries {
        try require(
          entry.dependencies.allSatisfy { entriesById[$0] != nil },
          "Runtime catalog dependency is missing for \(architecture)"
        )
      }

      var visiting = Set<String>()
      var visited = Set<String>()
      func visit(_ packId: String) throws {
        if visited.contains(packId) {
          return
        }
        try require(visiting.insert(packId).inserted, "Runtime catalog contains a dependency cycle")
        for dependency in entriesById[packId]?.dependencies ?? [] {
          try visit(dependency)
        }
        visiting.remove(packId)
        visited.insert(packId)
      }
      for packId in entriesById.keys {
        try visit(packId)
      }
    }
  }

  @discardableResult
  static func validateHTTPSURL(_ value: String) throws -> URLComponents {
    try require((1...maxURLCharacters).contains(value.count), "Runtime pack URL is invalid")
    guard let components = URLComponents(string: value) else {
      throw AgentRuntimeCapabilityError.invalid("Runtime pack URL is invalid")
    }
    let host = components.host?.lowercased() ?? ""
    try require(
      components.scheme?.lowercased() == "https" &&
        !host.isEmpty &&
        components.user == nil &&
        components.password == nil &&
        components.fragment == nil &&
        (components.port ?? -1) != 0,
      "Runtime pack URL must be public HTTPS"
    )
    try require(
      host != "localhost" && !host.hasSuffix(".localhost") && !host.hasSuffix(".local"),
      "Runtime pack URL must not target a local host"
    )
    return components
  }

  private static func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: [.regularExpression]) != nil
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
      throw AgentRuntimeCapabilityError.invalid(message)
    }
  }

  private static let formatVersion = 1
  private static let maxEntries = 128
  private static let maxURLCharacters = 4_096
  private static let maxReleaseNotesCharacters = 8_192
  private static let maxArchiveBytes: Int64 = 6 * 1_024 * 1_024 * 1_024
  private static let maxInstalledBytes: Int64 = 12 * 1_024 * 1_024 * 1_024
  private static let clockSkewMillis: Int64 = 24 * 60 * 60 * 1_000
  private static let versionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9._-]+)?$"#
  private static let architecturePattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#
  private static let sha256Pattern = #"^[a-fA-F0-9]{64}$"#
}
