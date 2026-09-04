import Foundation

#if canImport(Darwin)
import Darwin
#endif

struct VoiceWhisperBenchmarkDeviceIdentity: Equatable {
  var manufacturer: String
  var device: String
  var soc: String
  var osVersion: String

  init(
    manufacturer: String = "Apple",
    device: String,
    soc: String,
    osVersion: String
  ) {
    self.manufacturer = manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).benchmarkIfBlank("Apple")
    self.device = device.trimmingCharacters(in: .whitespacesAndNewlines).benchmarkIfBlank("unknown-device")
    self.soc = soc.trimmingCharacters(in: .whitespacesAndNewlines).benchmarkIfBlank(self.device)
    self.osVersion = osVersion.trimmingCharacters(in: .whitespacesAndNewlines).benchmarkIfBlank("unknown-ios")
  }

  static func detect(processInfo: ProcessInfo = .processInfo) -> VoiceWhisperBenchmarkDeviceIdentity {
    let machine = hardwareMachineIdentifier()
    return VoiceWhisperBenchmarkDeviceIdentity(
      device: machine,
      soc: machine,
      osVersion: processInfo.operatingSystemVersionString
    )
  }

  private static func hardwareMachineIdentifier() -> String {
    #if canImport(Darwin)
    var systemInfo = utsname()
    guard uname(&systemInfo) == 0 else {
      return "unknown-device"
    }
    return Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { result, element in
      guard let value = element.value as? Int8 else { return }
      let byte = UInt8(bitPattern: value)
      guard byte != 0, let scalar = UnicodeScalar(Int(byte)) else { return }
      result.unicodeScalars.append(scalar)
    }.benchmarkIfBlank("unknown-device")
    #else
    return ProcessInfo.processInfo.hostName.benchmarkIfBlank("unknown-device")
    #endif
  }
}

struct VoiceWhisperBenchmarkBuildInfo: Equatable {
  var appVersionCode: Int
  var whisperNativeVersion: String
  var nativeBuildFingerprint: String

  init(
    appVersionCode: Int = 1,
    whisperNativeVersion: String = "ios-whisper-runtime-v1",
    nativeBuildFingerprint: String = "ios-native-build"
  ) {
    self.appVersionCode = max(appVersionCode, 1)
    self.whisperNativeVersion = whisperNativeVersion.trimmingCharacters(in: .whitespacesAndNewlines)
      .benchmarkIfBlank("ios-whisper-runtime-v1")
    self.nativeBuildFingerprint = nativeBuildFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
      .benchmarkIfBlank("ios-native-build")
  }

  static func fromBundle(_ bundle: Bundle = .main) -> VoiceWhisperBenchmarkBuildInfo {
    let rawBuild = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
    let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    let bundleId = bundle.bundleIdentifier ?? "galaxyssi"
    let nativeVersion = (bundle.object(forInfoDictionaryKey: "WHISPER_NATIVE_VERSION") as? String) ??
      "ios-whisper-runtime-v1"
    let nativeFingerprint = (bundle.object(forInfoDictionaryKey: "WHISPER_NATIVE_BUILD_FINGERPRINT") as? String) ??
      ["ios-native", bundleId, shortVersion, rawBuild.benchmarkIfBlank("0")].joined(separator: ":")
    return VoiceWhisperBenchmarkBuildInfo(
      appVersionCode: Int(rawBuild.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1,
      whisperNativeVersion: nativeVersion,
      nativeBuildFingerprint: nativeFingerprint
    )
  }
}

struct VoiceWhisperBenchmarkDecisionContext: Equatable {
  var network: VoiceWhisperNetworkState
  var availableMemoryBytes: Int64?
  var currentPssBytes: Int64?
  var thermalStatus: Int?
  var batteryPercent: Int?
  var charging: Bool?
  var foreground: Bool
  var recentRealTimeFactor: Double?
  var decodeQueueDepth: Int
  var utteranceDurationMillis: Int64
  var highRiskTask: Bool
  var accuracySensitiveTask: Bool
  var remoteAllowed: Bool

  init(
    network: VoiceWhisperNetworkState = .offline,
    availableMemoryBytes: Int64? = nil,
    currentPssBytes: Int64? = nil,
    thermalStatus: Int? = nil,
    batteryPercent: Int? = nil,
    charging: Bool? = nil,
    foreground: Bool = true,
    recentRealTimeFactor: Double? = nil,
    decodeQueueDepth: Int = 0,
    utteranceDurationMillis: Int64 = 0,
    highRiskTask: Bool = false,
    accuracySensitiveTask: Bool = false,
    remoteAllowed: Bool = false
  ) {
    self.network = network
    self.availableMemoryBytes = availableMemoryBytes
    self.currentPssBytes = currentPssBytes
    self.thermalStatus = thermalStatus
    self.batteryPercent = batteryPercent
    self.charging = charging
    self.foreground = foreground
    self.recentRealTimeFactor = recentRealTimeFactor
    self.decodeQueueDepth = max(decodeQueueDepth, 0)
    self.utteranceDurationMillis = max(utteranceDurationMillis, 0)
    self.highRiskTask = highRiskTask
    self.accuracySensitiveTask = accuracySensitiveTask
    self.remoteAllowed = remoteAllowed
  }

  func runtimeEnvironment(
    device: LocalModelDeviceSnapshot,
    thermalController: VoiceWhisperThermalController
  ) -> VoiceWhisperRuntimeEnvironment {
    let observedThermal = thermalStatus ?? device.thermalStatus ?? 0
    return VoiceWhisperRuntimeEnvironment(
      network: network,
      availableMemoryBytes: availableMemoryBytes ?? device.availableMemoryBytes,
      currentPssBytes: currentPssBytes ?? 0,
      thermalStatus: thermalController.effectiveStatus(observedStatus: observedThermal),
      batteryPercent: batteryPercent ?? device.batteryPercent,
      charging: charging ?? device.charging,
      foreground: foreground,
      recentRealTimeFactor: recentRealTimeFactor,
      decodeQueueDepth: decodeQueueDepth,
      utteranceDurationMillis: utteranceDurationMillis,
      highRiskTask: highRiskTask,
      accuracySensitiveTask: accuracySensitiveTask,
      remoteAllowed: remoteAllowed
    )
  }
}

final class VoiceWhisperBenchmarkManager {
  static let benchmarkAudioVersion = "zh_cn_v2"
  static let benchmarkAudioSHA256 = "9a3505df8e1d6c1a60c87c7f7cc6e303e882189512d218f075a20f4784db05da"
  static let storeName = "benchmark-certifications.json"

  private let storage: VoiceWhisperModelStorage
  let recordStore: VoiceWhisperBenchmarkStore
  private let thermalController: VoiceWhisperThermalController
  private let modelsProvider: () -> [VoiceWhisperModelProfile]
  private let deviceIdentityProvider: () -> VoiceWhisperBenchmarkDeviceIdentity
  private let buildInfoProvider: () -> VoiceWhisperBenchmarkBuildInfo
  private let deviceSnapshotProvider: () -> LocalModelDeviceSnapshot

  init(
    modelsDirectory: URL = VoiceWhisperModelCatalog.defaultModelsDirectory(),
    storage: VoiceWhisperModelStorage? = nil,
    store: VoiceWhisperBenchmarkStore? = nil,
    thermalController: VoiceWhisperThermalController = VoiceWhisperThermalController(),
    modelsProvider: @escaping () -> [VoiceWhisperModelProfile] = { VoiceWhisperModelCatalog.models },
    deviceIdentityProvider: @escaping () -> VoiceWhisperBenchmarkDeviceIdentity = {
      VoiceWhisperBenchmarkDeviceIdentity.detect()
    },
    buildInfoProvider: @escaping () -> VoiceWhisperBenchmarkBuildInfo = {
      VoiceWhisperBenchmarkBuildInfo.fromBundle()
    },
    deviceSnapshotProvider: @escaping () -> LocalModelDeviceSnapshot = {
      LocalModelDeviceSnapshotDetector.capture()
    }
  ) {
    let normalizedDirectory = modelsDirectory.standardizedFileURL
    self.storage = storage ?? VoiceWhisperModelStorage(rootDirectory: normalizedDirectory)
    self.recordStore = store ?? VoiceWhisperBenchmarkStore(
      fileURL: normalizedDirectory.appendingPathComponent(Self.storeName, isDirectory: false)
    )
    self.thermalController = thermalController
    self.modelsProvider = modelsProvider
    self.deviceIdentityProvider = deviceIdentityProvider
    self.buildInfoProvider = buildInfoProvider
    self.deviceSnapshotProvider = deviceSnapshotProvider
  }

  func current(profile: VoiceWhisperModelProfile) -> VoiceWhisperBenchmarkRecord? {
    let record = recordStore.find(key(profile: profile))
    if record == nil {
      resetCertificationIfInstalled(profile)
    }
    return record
  }

  func latest(profile: VoiceWhisperModelProfile) -> VoiceWhisperBenchmarkRecord? {
    recordStore.latestForProfile(profile.id)
  }

  @discardableResult
  func save(
    _ record: VoiceWhisperBenchmarkRecord,
    profile explicitProfile: VoiceWhisperModelProfile? = nil
  ) throws -> VoiceWhisperBenchmarkRecord {
    try recordStore.save(record)
    let profile = explicitProfile ?? modelsProvider().first {
      $0.id == record.certification.key.modelProfileId
    }
    if let profile,
       storage.inspect(profile).installed,
       record.certification.key == key(profile: profile) {
      try storage.updateCertification(profile, certification: record.certification.level)
    }
    return record
  }

  func remove(profile: VoiceWhisperModelProfile) throws {
    try recordStore.removeForProfile(profile.id)
  }

  func decide(
    userMode: VoiceWhisperUserVoiceMode,
    selectedProfileId: String? = nil,
    context: VoiceWhisperBenchmarkDecisionContext = VoiceWhisperBenchmarkDecisionContext()
  ) -> VoiceWhisperRuntimeDecision {
    let environment = context.runtimeEnvironment(
      device: deviceSnapshotProvider(),
      thermalController: thermalController
    )
    return VoiceWhisperRuntimePolicyEngine.decide(
      VoiceWhisperRuntimePolicyInput(
        userMode: userMode,
        selectedProfileId: selectedProfileId,
        candidates: candidates(),
        environment: environment
      )
    )
  }

  func key(profile: VoiceWhisperModelProfile) -> VoiceWhisperBenchmarkKey {
    key(profile: profile, benchmarkAudioVersion: Self.benchmarkAudioIdentity)
  }

  func key(
    profile: VoiceWhisperModelProfile,
    benchmarkAudioVersion: String
  ) -> VoiceWhisperBenchmarkKey {
    let identity = deviceIdentityProvider()
    let build = buildInfoProvider()
    return VoiceWhisperBenchmarkKey(
      manufacturer: identity.manufacturer,
      device: identity.device,
      soc: identity.soc,
      osVersion: identity.osVersion,
      appVersionCode: build.appVersionCode,
      whisperNativeVersion: build.whisperNativeVersion,
      nativeBuildFingerprint: build.nativeBuildFingerprint,
      modelProfileId: profile.id,
      modelSha256: profile.sha256,
      benchmarkAudioVersion: benchmarkAudioVersion
    )
  }

  private func candidates() -> [VoiceWhisperRuntimeCandidate] {
    modelsProvider().map { profile in
      let snapshot = storage.inspect(profile)
      return VoiceWhisperRuntimeCandidate(
        profile: profile,
        installed: snapshot.installed,
        certification: snapshot.installed ? current(profile: profile)?.certification : nil
      )
    }
  }

  private func resetCertificationIfInstalled(_ profile: VoiceWhisperModelProfile) {
    let snapshot = storage.inspect(profile)
    guard snapshot.installed, snapshot.metadata?.certification != .untested else {
      return
    }
    try? storage.updateCertification(profile, certification: .untested)
  }

  private static var benchmarkAudioIdentity: String {
    "\(benchmarkAudioVersion):\(String(benchmarkAudioSHA256.prefix(16)))"
  }
}

private extension String {
  func benchmarkIfBlank(_ fallback: String) -> String {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
  }
}
