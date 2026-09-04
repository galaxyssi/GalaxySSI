import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum AgentDeviceProfileKind: String, Codable, CaseIterable, Identifiable {
  case phone = "PHONE"
  case tablet = "TABLET"
  case automotive = "AUTOMOTIVE"
  case legacyIOSPhone = "LEGACY_IOS_PHONE"
  case legacyIOSTablet = "LEGACY_IOS_TABLET"

  var id: String { rawValue }
}

enum AgentDeviceInterfaceClass: String, Codable, CaseIterable, Identifiable {
  case phone = "phone"
  case tablet = "tablet"
  case automotive = "automotive"
  case desktop = "desktop"
  case unknown = "unknown"

  var id: String { rawValue }
}

enum AgentDeviceOrientationPolicy: String, Codable, Equatable {
  case portrait = "PORTRAIT"
  case flexible = "FLEXIBLE"
}

struct AgentDeviceProfileSignals: Codable, Equatable {
  var interfaceClass: AgentDeviceInterfaceClass
  var osMajorVersion: Int
  var smallestScreenWidthDp: Int
  var lowMemoryDevice: Bool
  var totalMemoryBytes: Int64
  var processorCount: Int
  var lowPowerMode: Bool
  var thermalPressure: Bool
  var reduceMotionEnabled: Bool

  init(
    interfaceClass: AgentDeviceInterfaceClass = .phone,
    osMajorVersion: Int = 17,
    smallestScreenWidthDp: Int = 393,
    lowMemoryDevice: Bool = false,
    totalMemoryBytes: Int64 = 8 * 1024 * 1024 * 1024,
    processorCount: Int = 6,
    lowPowerMode: Bool = false,
    thermalPressure: Bool = false,
    reduceMotionEnabled: Bool = false
  ) {
    self.interfaceClass = interfaceClass
    self.osMajorVersion = max(0, osMajorVersion)
    self.smallestScreenWidthDp = max(0, smallestScreenWidthDp)
    self.lowMemoryDevice = lowMemoryDevice
    self.totalMemoryBytes = max(0, totalMemoryBytes)
    self.processorCount = max(1, processorCount)
    self.lowPowerMode = lowPowerMode
    self.thermalPressure = thermalPressure
    self.reduceMotionEnabled = reduceMotionEnabled
  }

  enum CodingKeys: String, CodingKey {
    case interfaceClass = "interface_class"
    case osMajorVersion = "os_major_version"
    case smallestScreenWidthDp = "smallest_screen_width_dp"
    case lowMemoryDevice = "low_memory_device"
    case totalMemoryBytes = "total_memory_bytes"
    case processorCount = "processor_count"
    case lowPowerMode = "low_power_mode"
    case thermalPressure = "thermal_pressure"
    case reduceMotionEnabled = "reduce_motion_enabled"
  }
}

struct AgentDeviceCaptureSize: Codable, Equatable {
  var width: Int
  var height: Int

  init(width: Int, height: Int) {
    self.width = max(Self.minimumEdgePx, width)
    self.height = max(Self.minimumEdgePx, height)
  }

  enum CodingKeys: String, CodingKey {
    case width
    case height
  }

  static let minimumEdgePx = 320
}

struct AgentDeviceRuntimeBudget: Codable, Equatable {
  var cpuCount: Int
  var memoryMegabytes: Int

  init(cpuCount: Int, memoryMegabytes: Int) {
    self.cpuCount = max(1, cpuCount)
    self.memoryMegabytes = max(128, memoryMegabytes)
  }

  enum CodingKeys: String, CodingKey {
    case cpuCount = "cpu_count"
    case memoryMegabytes = "memory_megabytes"
  }
}

struct AgentDeviceInputTargetPolicy: Codable, Equatable {
  var minimumTouchTargetDp: Int
  var voiceButtonMinimumWidthDp: Int?
  var orientation: AgentDeviceOrientationPolicy
  var reduceMotion: Bool

  enum CodingKeys: String, CodingKey {
    case minimumTouchTargetDp = "minimum_touch_target_dp"
    case voiceButtonMinimumWidthDp = "voice_button_minimum_width_dp"
    case orientation
    case reduceMotion = "reduce_motion"
  }
}

struct AgentDeviceProfile: Codable, Equatable, Identifiable {
  var kind: AgentDeviceProfileKind
  var id: String
  var maxReadReasoningTasks: Int
  var maxTeamConcurrency: Int
  var maxQemuCpuCount: Int
  var maxQemuMemoryMegabytes: Int
  var maxScreenCaptureLongEdgePx: Int
  var minimumTouchTargetDp: Int
  var voiceFirst: Bool
  var reduceMotion: Bool
  var conservativeMedia: Bool

  init(
    kind: AgentDeviceProfileKind,
    id: String,
    maxReadReasoningTasks: Int,
    maxTeamConcurrency: Int,
    maxQemuCpuCount: Int,
    maxQemuMemoryMegabytes: Int,
    maxScreenCaptureLongEdgePx: Int,
    minimumTouchTargetDp: Int,
    voiceFirst: Bool = false,
    reduceMotion: Bool = false,
    conservativeMedia: Bool = false
  ) {
    self.kind = kind
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.rawValue.lowercased() : id
    self.maxReadReasoningTasks = max(1, maxReadReasoningTasks)
    self.maxTeamConcurrency = max(1, maxTeamConcurrency)
    self.maxQemuCpuCount = max(1, maxQemuCpuCount)
    self.maxQemuMemoryMegabytes = max(128, maxQemuMemoryMegabytes)
    self.maxScreenCaptureLongEdgePx = max(AgentDeviceCaptureSize.minimumEdgePx, maxScreenCaptureLongEdgePx)
    self.minimumTouchTargetDp = max(44, minimumTouchTargetDp)
    self.voiceFirst = voiceFirst
    self.reduceMotion = reduceMotion
    self.conservativeMedia = conservativeMedia
  }

  var orientation: AgentDeviceOrientationPolicy {
    switch kind {
    case .tablet, .automotive, .legacyIOSTablet:
      return .flexible
    case .phone, .legacyIOSPhone:
      return .portrait
    }
  }

  var inputTargetPolicy: AgentDeviceInputTargetPolicy {
    AgentDeviceInputTargetPolicy(
      minimumTouchTargetDp: minimumTouchTargetDp,
      voiceButtonMinimumWidthDp: voiceFirst ? Self.automotiveVoiceButtonWidthDp : nil,
      orientation: orientation,
      reduceMotion: reduceMotion
    )
  }

  func constrainCaptureSize(width: Int, height: Int) -> AgentDeviceCaptureSize {
    let safeWidth = max(AgentDeviceCaptureSize.minimumEdgePx, width)
    let safeHeight = max(AgentDeviceCaptureSize.minimumEdgePx, height)
    let longEdge = max(safeWidth, safeHeight)
    guard longEdge > maxScreenCaptureLongEdgePx else {
      return AgentDeviceCaptureSize(width: safeWidth, height: safeHeight)
    }
    let scale = Double(maxScreenCaptureLongEdgePx) / Double(longEdge)
    return AgentDeviceCaptureSize(
      width: max(AgentDeviceCaptureSize.minimumEdgePx, Int((Double(safeWidth) * scale).rounded())),
      height: max(AgentDeviceCaptureSize.minimumEdgePx, Int((Double(safeHeight) * scale).rounded()))
    )
  }

  func constrainRuntime(cpuCount: Int, memoryMegabytes: Int) -> AgentDeviceRuntimeBudget {
    AgentDeviceRuntimeBudget(
      cpuCount: min(max(1, cpuCount), maxQemuCpuCount),
      memoryMegabytes: min(max(128, memoryMegabytes), maxQemuMemoryMegabytes)
    )
  }

  func adaptMedia(_ profile: AgentMediaDeliveryProfile) -> AgentMediaDeliveryProfile {
    guard conservativeMedia else { return profile }
    return AgentMediaDeliveryProfile(
      state: profile.state,
      id: profile.id,
      imageTargetBytes: min(profile.imageTargetBytes, Self.conservativeImageBytes),
      audioSampleRateHz: min(profile.audioSampleRateHz, Self.conservativeAudioSampleRateHz),
      audioBitRateBps: min(profile.audioBitRateBps, Self.conservativeAudioBitRateBps),
      deferMediaUpload: profile.deferMediaUpload
    )
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case id
    case maxReadReasoningTasks = "max_read_reasoning_tasks"
    case maxTeamConcurrency = "max_team_concurrency"
    case maxQemuCpuCount = "max_qemu_cpu_count"
    case maxQemuMemoryMegabytes = "max_qemu_memory_megabytes"
    case maxScreenCaptureLongEdgePx = "max_screen_capture_long_edge_px"
    case minimumTouchTargetDp = "minimum_touch_target_dp"
    case voiceFirst = "voice_first"
    case reduceMotion = "reduce_motion"
    case conservativeMedia = "conservative_media"
  }

  private static let automotiveVoiceButtonWidthDp = 160
  private static let conservativeImageBytes = 64 * 1024
  private static let conservativeAudioSampleRateHz = 16_000
  private static let conservativeAudioBitRateBps = 32_000
}

enum AgentDeviceProfilePolicy {
  static func resolve(signals: AgentDeviceProfileSignals) -> AgentDeviceProfile {
    let tablet = signals.interfaceClass == .tablet ||
      signals.interfaceClass == .desktop ||
      (signals.interfaceClass == .unknown && signals.smallestScreenWidthDp >= tabletMinimumWidthDp)
    let legacyIOS = signals.osMajorVersion <= legacyIOSMaximumMajorVersion ||
      signals.lowMemoryDevice ||
      (1...legacyIOSMaximumRamBytes).contains(signals.totalMemoryBytes)
    let conservativeDynamic = signals.lowPowerMode || signals.thermalPressure

    switch (signals.interfaceClass, tablet, legacyIOS) {
    case (.automotive, _, _):
      return profile(
        kind: .automotive,
        id: "automotive",
        readTasks: 1,
        teamConcurrency: 1,
        qemuCpu: 1,
        qemuMemoryMb: 512,
        captureLongEdgePx: 1_280,
        touchTargetDp: 64,
        voiceFirst: true,
        reduceMotion: true,
        conservativeMedia: true,
        signals: signals
      )
    case (_, true, true):
      return profile(
        kind: .legacyIOSTablet,
        id: "legacy_ios_tablet",
        readTasks: 1,
        teamConcurrency: 2,
        qemuCpu: 2,
        qemuMemoryMb: 768,
        captureLongEdgePx: 1_400,
        touchTargetDp: 52,
        reduceMotion: true,
        conservativeMedia: true,
        signals: signals
      )
    case (_, true, false):
      return profile(
        kind: .tablet,
        id: "tablet",
        readTasks: 3,
        teamConcurrency: 4,
        qemuCpu: 4,
        qemuMemoryMb: 1_536,
        captureLongEdgePx: 2_048,
        touchTargetDp: 48,
        conservativeMedia: conservativeDynamic,
        signals: signals
      )
    case (_, false, true):
      return profile(
        kind: .legacyIOSPhone,
        id: "legacy_ios_phone",
        readTasks: 1,
        teamConcurrency: 1,
        qemuCpu: 2,
        qemuMemoryMb: 640,
        captureLongEdgePx: 1_280,
        touchTargetDp: 48,
        reduceMotion: true,
        conservativeMedia: true,
        signals: signals
      )
    default:
      return profile(
        kind: .phone,
        id: "phone",
        readTasks: 2,
        teamConcurrency: 3,
        qemuCpu: 4,
        qemuMemoryMb: 1_536,
        captureLongEdgePx: 1_920,
        touchTargetDp: 48,
        conservativeMedia: conservativeDynamic,
        signals: signals
      )
    }
  }

  private static func profile(
    kind: AgentDeviceProfileKind,
    id: String,
    readTasks: Int,
    teamConcurrency: Int,
    qemuCpu: Int,
    qemuMemoryMb: Int,
    captureLongEdgePx: Int,
    touchTargetDp: Int,
    voiceFirst: Bool = false,
    reduceMotion: Bool = false,
    conservativeMedia: Bool = false,
    signals: AgentDeviceProfileSignals = AgentDeviceProfileSignals()
  ) -> AgentDeviceProfile {
    AgentDeviceProfile(
      kind: kind,
      id: id,
      maxReadReasoningTasks: readTasks,
      maxTeamConcurrency: min(teamConcurrency, signals.processorCount),
      maxQemuCpuCount: min(qemuCpu, signals.processorCount),
      maxQemuMemoryMegabytes: qemuMemoryMb,
      maxScreenCaptureLongEdgePx: captureLongEdgePx,
      minimumTouchTargetDp: touchTargetDp,
      voiceFirst: voiceFirst,
      reduceMotion: reduceMotion || signals.reduceMotionEnabled,
      conservativeMedia: conservativeMedia
    )
  }

  private static let tabletMinimumWidthDp = 600
  private static let legacyIOSMaximumMajorVersion = 15
  private static let legacyIOSMaximumRamBytes: Int64 = 4 * 1024 * 1024 * 1024
}

enum AgentDeviceProfileDetector {
  static func detect(
    processInfo: ProcessInfo = .processInfo,
    signalsOverride: AgentDeviceProfileSignals? = nil
  ) -> AgentDeviceProfile {
    if let signalsOverride {
      return AgentDeviceProfilePolicy.resolve(signals: signalsOverride)
    }
    return AgentDeviceProfilePolicy.resolve(signals: signals(processInfo: processInfo))
  }

  static func signals(processInfo: ProcessInfo = .processInfo) -> AgentDeviceProfileSignals {
    let operatingSystem = processInfo.operatingSystemVersion
    #if canImport(UIKit)
    if Thread.isMainThread {
      let idiom = UIDevice.current.userInterfaceIdiom
      let screen = UIScreen.main
      let size = screen.bounds.size
      let smallestWidth = Int(min(size.width, size.height).rounded())
      return AgentDeviceProfileSignals(
        interfaceClass: interfaceClass(for: idiom),
        osMajorVersion: operatingSystem.majorVersion,
        smallestScreenWidthDp: smallestWidth,
        lowMemoryDevice: lowMemoryDevice(processInfo),
        totalMemoryBytes: boundedPhysicalMemory(processInfo),
        processorCount: processInfo.processorCount,
        lowPowerMode: processInfo.isLowPowerModeEnabled,
        thermalPressure: thermalPressure(processInfo.thermalState),
        reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
      )
    }
    return AgentDeviceProfileSignals(
      interfaceClass: .unknown,
      osMajorVersion: operatingSystem.majorVersion,
      lowMemoryDevice: lowMemoryDevice(processInfo),
      totalMemoryBytes: boundedPhysicalMemory(processInfo),
      processorCount: processInfo.processorCount,
      lowPowerMode: processInfo.isLowPowerModeEnabled,
      thermalPressure: thermalPressure(processInfo.thermalState),
      reduceMotionEnabled: false
    )
    #else
    return AgentDeviceProfileSignals(
      interfaceClass: .unknown,
      osMajorVersion: operatingSystem.majorVersion,
      lowMemoryDevice: false,
      totalMemoryBytes: boundedPhysicalMemory(processInfo),
      processorCount: processInfo.processorCount,
      lowPowerMode: processInfo.isLowPowerModeEnabled,
      thermalPressure: false,
      reduceMotionEnabled: false
    )
    #endif
  }

  #if canImport(UIKit)
  private static func interfaceClass(for idiom: UIUserInterfaceIdiom) -> AgentDeviceInterfaceClass {
    switch idiom {
    case .phone:
      return .phone
    case .pad:
      return .tablet
    case .carPlay:
      return .automotive
    case .mac, .tv:
      return .desktop
    default:
      return .unknown
    }
  }

  private static func thermalPressure(_ state: ProcessInfo.ThermalState) -> Bool {
    switch state {
    case .serious, .critical:
      return true
    case .nominal, .fair:
      return false
    @unknown default:
      return false
    }
  }
  #endif

  private static func boundedPhysicalMemory(_ processInfo: ProcessInfo) -> Int64 {
    Int64(min(processInfo.physicalMemory, UInt64(Int64.max)))
  }

  private static func lowMemoryDevice(_ processInfo: ProcessInfo) -> Bool {
    processInfo.physicalMemory > 0 &&
      processInfo.physicalMemory <= UInt64(AgentDeviceProfilePolicyLegacy.lowMemoryBytes)
  }
}

private enum AgentDeviceProfilePolicyLegacy {
  static let lowMemoryBytes: Int64 = 4 * 1024 * 1024 * 1024
}
