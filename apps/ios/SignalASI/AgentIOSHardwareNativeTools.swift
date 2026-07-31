import Foundation
#if canImport(AVFoundation) && os(iOS)
import AVFoundation
#endif
#if canImport(CoreBluetooth) && os(iOS)
import CoreBluetooth
#endif
#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif
#if canImport(CoreNFC) && os(iOS)
import CoreNFC
#endif
#if canImport(UIKit)
import UIKit
#endif

protocol AgentIOSHardwareStatusProviding {
  func batteryStatus(nowMillis: Int64) -> AgentMcpJSONObject
  func powerStatus(nowMillis: Int64) -> AgentMcpJSONObject
  func storageStatus(nowMillis: Int64) -> AgentMcpJSONObject
  func networkStatus(nowMillis: Int64) -> AgentMcpJSONObject
  func bluetoothStatus(nowMillis: Int64) -> AgentMcpJSONObject
  func nfcStatus(nowMillis: Int64) -> AgentMcpJSONObject
  func sensorsList(limit: Int, nowMillis: Int64) -> AgentMcpJSONObject
  func setFlashlight(enabled: Bool, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSDefaultHardwareStatusProvider: AgentIOSHardwareStatusProviding {
  var networkProbeProvider: () -> AgentMediaNetworkProbe

  init(
    networkProbeProvider: @escaping () -> AgentMediaNetworkProbe = { AgentMediaNetworkDetector.shared.currentProbe }
  ) {
    self.networkProbeProvider = networkProbeProvider
  }

  func batteryStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    let battery = currentBatterySnapshot()
    [
      "percent": battery.percent.map(AgentMcpJSONValue.int) ?? .null,
      "charging": .bool(battery.charging),
      "plugged": .string(battery.plugged),
      "status": .string(battery.status),
      "health": .string("unknown"),
      "scope": .string("app_visible_ios"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
  }

  func powerStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    [
      "interactive": .bool(true),
      "low_power_mode": .bool(ProcessInfo.processInfo.isLowPowerModeEnabled),
      "thermal_state": .string(thermalState(ProcessInfo.processInfo.thermalState)),
      "settings_changed": .bool(false),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
  }

  func storageStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    let attributes = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())) ?? [:]
    let total = int64(attributes[.systemSize])
    let available = int64(attributes[.systemFreeSize])
    return [
      "scope": .string("app_private_volume"),
      "total_bytes": .int(total),
      "available_bytes": .int(available),
      "used_bytes": .int(max(0, total - available)),
      "low_storage": .bool(total > 0 && available < max(100 * 1_024 * 1_024, total / 20)),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
  }

  func networkStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    let probe = networkProbeProvider()
    let transports = boundedNetworkTransports(probe.transports, cellular: probe.cellular)
    [
      "connected": .bool(probe.networkPresent && probe.internetCapable),
      "validated": .bool(probe.validated),
      "metered": .bool(probe.metered),
      "roaming": .bool(probe.roaming),
      "transports": .array(transports.map(AgentMcpJSONValue.string)),
      "downstream_kbps": .int(Int64(max(0, probe.downstreamKbps))),
      "upstream_kbps": .int(Int64(max(0, probe.upstreamKbps))),
      "identifiers_included": .bool(false),
      "scope": .string("app_visible_ios"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
  }

  func nfcStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    #if canImport(CoreNFC) && os(iOS)
    let readingAvailable = NFCNDEFReaderSession.readingAvailable
    let framework = "core_nfc"
    #else
    let readingAvailable = false
    let framework = "unavailable"
    #endif
    return [
      "supported": .bool(readingAvailable),
      "enabled": .bool(readingAvailable),
      "secure_nfc_supported": .bool(false),
      "secure_nfc_enabled": .bool(false),
      "tag_capture_started": .bool(false),
      "settings_changed": .bool(false),
      "framework": .string(framework),
      "scope": .string("ios_core_nfc_status_only"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
  }

  func bluetoothStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    #if canImport(CoreBluetooth) && os(iOS)
    let framework = "core_bluetooth"
    let authorization = bluetoothAuthorization(CBCentralManager.authorization)
    let supported = true
    #else
    let framework = "unavailable"
    let authorization = "unavailable"
    let supported = false
    #endif
    return [
      "supported": .bool(supported),
      "enabled": .bool(false),
      "enabled_state": .string("unknown_without_foreground_observation"),
      "discovering": .bool(false),
      "bonded_device_count": .null,
      "device_identifiers_included": .bool(false),
      "state_observation_started": .bool(false),
      "foreground_observation_required": .bool(true),
      "framework": .string(framework),
      "authorization": .string(authorization),
      "scope": .string("ios_corebluetooth_status_boundary"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
  }

  #if canImport(CoreBluetooth) && os(iOS)
  private func bluetoothAuthorization(_ authorization: CBManagerAuthorization) -> String {
    switch authorization {
    case .allowedAlways:
      return "allowed_always"
    case .denied:
      return "denied"
    case .notDetermined:
      return "not_determined"
    case .restricted:
      return "restricted"
    @unknown default:
      return "unknown"
    }
  }
  #endif

  func sensorsList(limit: Int, nowMillis: Int64) -> AgentMcpJSONObject {
    let boundedLimit = max(1, min(AgentIOSHardwareNativeToolCatalog.maxSensorResults, limit))
    #if canImport(CoreMotion) && os(iOS)
    let manager = CMMotionManager()
    let sensors = [
      sensorDescriptor(
        available: manager.isAccelerometerAvailable,
        type: "accelerometer",
        androidType: 1,
        name: "iOS Accelerometer"
      ),
      sensorDescriptor(
        available: manager.isDeviceMotionAvailable,
        type: "game_rotation_vector",
        androidType: 15,
        name: "iOS Game Rotation Vector"
      ),
      sensorDescriptor(
        available: manager.isDeviceMotionAvailable,
        type: "gravity",
        androidType: 9,
        name: "iOS Gravity Estimate"
      ),
      sensorDescriptor(
        available: manager.isGyroAvailable,
        type: "gyroscope",
        androidType: 4,
        name: "iOS Gyroscope"
      ),
      sensorDescriptor(
        available: manager.isDeviceMotionAvailable,
        type: "linear_acceleration",
        androidType: 10,
        name: "iOS User Acceleration"
      ),
      sensorDescriptor(
        available: manager.isMagnetometerAvailable,
        type: "magnetic_field",
        androidType: 2,
        name: "iOS Magnetometer"
      ),
      sensorDescriptor(
        available: manager.isDeviceMotionAvailable,
        type: "rotation_vector",
        androidType: 11,
        name: "iOS Device Motion"
      )
    ].compactMap { $0 }
    let framework = "core_motion"
    #else
    let sensors: [AgentMcpJSONObject] = []
    let framework = "unavailable"
    #endif
    let selected = Array(sensors.prefix(boundedLimit))
    return [
      "sensors": .array(selected.map { .object($0) }),
      "result_count": .int(Int64(selected.count)),
      "truncated": .bool(sensors.count > boundedLimit),
      "sampling_started": .bool(false),
      "framework": .string(framework),
      "scope": .string("ios_coremotion_metadata"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
  }

  private func sensorDescriptor(
    available: Bool,
    type: String,
    androidType: Int64,
    name: String
  ) -> AgentMcpJSONObject? {
    guard available else { return nil }
    return [
      "type": .string(type),
      "android_type": .int(androidType),
      "name": .string(name),
      "vendor": .string("Apple"),
      "version": .int(1),
      "maximum_range": .double(0),
      "resolution": .double(0),
      "power_milliamps": .double(0),
      "reporting_mode": .string("continuous"),
      "wake_up": .bool(false),
      "runtime_permission": .null
    ]
  }

  func setFlashlight(enabled: Bool, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    #if canImport(AVFoundation) && os(iOS)
    let authorization = AVCaptureDevice.authorizationStatus(for: .video)
    guard authorization != .denied && authorization != .restricted else {
      return AgentNativeToolExecutionResult.failure(
        code: "flashlight_camera_permission_required",
        message: "Camera hardware permission is required before iOS torch control can run.",
        retryable: true,
        details: flashlightDetails(nowMillis: nowMillis, cameraAuthorization: cameraAuthorization(authorization))
      )
    }
    guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
      return AgentNativeToolExecutionResult.failure(
        code: "flashlight_unavailable",
        message: "This iOS device does not expose an app-visible torch.",
        details: flashlightDetails(nowMillis: nowMillis, cameraAuthorization: cameraAuthorization(authorization))
      )
    }
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      if enabled {
        guard device.isTorchModeSupported(.on) else {
          return AgentNativeToolExecutionResult.failure(
            code: "flashlight_on_unsupported",
            message: "The iOS torch does not support the requested on state.",
            details: flashlightDetails(nowMillis: nowMillis, cameraAuthorization: cameraAuthorization(authorization))
          )
        }
        try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
      } else if device.isTorchModeSupported(.off) {
        device.torchMode = .off
      }
      let verified = enabled ? device.torchMode == .on : device.torchMode == .off
      return AgentNativeToolExecutionResult.success(
        output: [
          "requested_enabled": .bool(enabled),
          "request_accepted": .bool(true),
          "state_verified": .bool(verified),
          "settings_changed": .bool(false),
          "observed_at_epoch_ms": .int(nowMillis)
        ],
        message: "Flashlight request submitted",
        metadata: [
          "camera_capture": .bool(false),
          "continuous_state_guarantee": .bool(false),
          "framework": .string("avfoundation_torch"),
          "camera_authorization": .string(cameraAuthorization(authorization))
        ]
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "flashlight_control_failed",
        message: "iOS torch control failed.",
        retryable: true,
        details: flashlightDetails(
          nowMillis: nowMillis,
          cameraAuthorization: cameraAuthorization(authorization),
          errorDescription: String(error.localizedDescription.prefix(240))
        )
      )
    }
    #else
    return AgentNativeToolExecutionResult.failure(
      code: "flashlight_unavailable",
      message: "AVFoundation torch control is unavailable on this platform.",
      details: flashlightDetails(nowMillis: nowMillis, cameraAuthorization: "unavailable")
    )
    #endif
  }

  private func flashlightDetails(
    nowMillis: Int64,
    cameraAuthorization: String,
    errorDescription: String = ""
  ) -> AgentMcpJSONObject {
    var details: AgentMcpJSONObject = [
      "camera_capture": .bool(false),
      "settings_changed": .bool(false),
      "camera_authorization": .string(cameraAuthorization),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
    if !errorDescription.isEmpty {
      details["error_description"] = .string(errorDescription)
    }
    return details
  }

  #if canImport(AVFoundation) && os(iOS)
  private func cameraAuthorization(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .notDetermined:
      return "not_determined"
    case .restricted:
      return "restricted"
    @unknown default:
      return "unknown"
    }
  }
  #endif

  private func int64(_ value: Any?) -> Int64 {
    if let value = value as? NSNumber {
      return max(0, value.int64Value)
    }
    if let value = value as? Int64 {
      return max(0, value)
    }
    if let value = value as? Int {
      return max(0, Int64(value))
    }
    return 0
  }

  private func boundedNetworkTransports(_ values: [String], cellular: Bool) -> [String] {
    let allowed: Set<String> = ["wifi", "cellular", "ethernet", "vpn", "bluetooth", "wifi_aware", "lowpan", "usb"]
    var ordered = values
    if cellular && !ordered.contains("cellular") {
      ordered.append("cellular")
    }
    var seen: Set<String> = []
    let filtered = ordered.filter { value in
      guard allowed.contains(value), !seen.contains(value) else {
        return false
      }
      seen.insert(value)
      return true
    }
    return Array(filtered.prefix(8))
  }

  private func thermalState(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal:
      return "nominal"
    case .fair:
      return "fair"
    case .serious:
      return "serious"
    case .critical:
      return "critical"
    @unknown default:
      return "unknown"
    }
  }

  private func currentBatterySnapshot() -> (percent: Int64?, charging: Bool, plugged: String, status: String) {
    #if canImport(UIKit)
    let device = UIDevice.current
    let wasMonitoring = device.isBatteryMonitoringEnabled
    device.isBatteryMonitoringEnabled = true
    defer { device.isBatteryMonitoringEnabled = wasMonitoring }

    let percent: Int64?
    if device.batteryLevel >= 0 {
      let rounded = Int((device.batteryLevel * 100).rounded())
      percent = Int64(max(0, min(100, rounded)))
    } else {
      percent = nil
    }

    switch device.batteryState {
    case .charging:
      return (percent, true, "unknown", "charging")
    case .full:
      return (percent ?? 100, true, "unknown", "full")
    case .unplugged:
      return (percent, false, "none", "discharging")
    case .unknown:
      return (percent, false, "unknown", "unknown")
    @unknown default:
      return (percent, false, "unknown", "unknown")
    }
    #else
    return (nil, false, "unknown", "unknown")
    #endif
  }
}

enum AgentIOSHardwareNativeToolCatalog {
  static let batteryStatus = AgentPhoneCapabilityNativeCoverage.batteryStatus
  static let powerStatus = AgentPhoneCapabilityNativeCoverage.powerStatus
  static let storageStatus = "signalasi.hardware.storage.status"
  static let networkStatus = AgentPhoneCapabilityNativeCoverage.networkStatus
  static let locationForegroundRead = AgentPhoneCapabilityNativeCoverage.locationForegroundRead
  static let sensorsList = AgentPhoneCapabilityNativeCoverage.sensorsList
  static let sensorSample = AgentPhoneCapabilityNativeCoverage.sensorSample
  static let flashlightSet = "signalasi.hardware.flashlight.set"
  static let bluetoothStatus = AgentPhoneCapabilityNativeCoverage.bluetoothStatus
  static let bluetoothDiscoveryForeground = AgentPhoneCapabilityNativeCoverage.bluetoothDiscoveryForeground
  static let bluetoothPairingHandoff = AgentPhoneCapabilityNativeCoverage.bluetoothPairingHandoff
  static let nfcStatus = AgentPhoneCapabilityNativeCoverage.nfcStatus
  static let installedAppsList = AgentPhoneCapabilityNativeCoverage.installedAppsList
  static let packageDetail = AgentPhoneCapabilityNativeCoverage.packageDetail

  static let executorId = "signalasi.ios.hardware_native"
  static let hardwareStatusPermission = "signalasi.scope.ios_app_visible_hardware_status"
  static let appVisibilityBoundaryPermission = "signalasi.scope.ios_app_visibility_boundary"
  static let sensorSamplePermission = "signalasi.scope.ios_coremotion_foreground_sample"
  static let foregroundLocationConsent = "signalasi.consent.location.foreground_once"
  static let sensorSampleConsent = "signalasi.consent.sensor.foreground_once"
  static let userVisibleHandoffConsent = "signalasi.consent.ios_settings_handoff"
  static let flashlightControlConsent = "signalasi.consent.flashlight.control"
  static let bluetoothDiscoveryConsent = "signalasi.consent.bluetooth.discovery.foreground_once"
  static let installedAppsConsent = "signalasi.consent.installed_apps.query_visible"
  static let packageDetailConsent = "signalasi.consent.package_detail.query_visible"
  static let maxLocationTimeoutMillis: Int64 = 30_000
  static let minSensorTimeoutMillis: Int64 = 250
  static let maxSensorTimeoutMillis: Int64 = 5_000
  static let minBluetoothDiscoveryMillis: Int64 = 1_000
  static let maxBluetoothDiscoveryMillis: Int64 = 15_000
  static let maxSensorResults = 64
  static let maxSensorValues = 16
  static let maxBluetoothResults = 32
  static let maxBluetoothNameChars: Int64 = 160
  static let sensorSampleTypes = [
    "accelerometer",
    "game_rotation_vector",
    "gravity",
    "gyroscope",
    "linear_acceleration",
    "magnetic_field",
    "rotation_vector"
  ]

  static let executableToolIds: Set<String> = [
    batteryStatus,
    powerStatus,
    storageStatus,
    networkStatus,
    locationForegroundRead,
    sensorsList,
    sensorSample,
    flashlightSet,
    bluetoothStatus,
    bluetoothDiscoveryForeground,
    nfcStatus,
    bluetoothPairingHandoff,
    installedAppsList,
    packageDetail
  ]

  static var orderedToolIds: [String] {
    specifications.map(\.id)
  }

  static var toolIds: Set<String> {
    Set(orderedToolIds)
  }

  static func definitions() -> [AgentPhoneNativeToolDefinition] {
    specifications.map(definition)
  }

  static func descriptors() -> [AgentNativeToolDescriptor] {
    definitions().map(\.descriptor)
  }

  private struct Specification {
    var id: String
    var title: String
    var description: String
    var risk: AgentNativeToolRisk
    var capabilities: Set<String>
    var permissions: [AgentNativePermissionRequirement]
    var consents: [AgentNativeConsentRequirement]
    var availability: AgentNativeToolAvailability
    var inputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema()
    var outputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema()
    var timeoutMillis: Int64 = 15_000
    var idempotency: AgentNativeToolIdempotency = .nonIdempotent
  }

  private static let specifications: [Specification] = [
    statusSpec(batteryStatus, "Read battery status", "Reads app-visible iOS battery status without vendor diagnostics.", ["battery.status"]),
    statusSpec(powerStatus, "Read power status", "Reads app-visible iOS power and thermal status without changing settings.", ["power.status"]),
    statusSpec(storageStatus, "Read storage status", "Reads bounded app-volume storage capacity signals.", ["storage.status"]),
    statusSpec(networkStatus, "Read network status", "Returns identifier-free app-visible network state from the iOS status provider.", ["network.status"]),
    foregroundLocationSpec(
      locationForegroundRead,
      "Read foreground location",
      "Reads one bounded iOS CoreLocation foreground fix after permission and per-invocation consent."
    ),
    statusSpec(
      sensorsList,
      "List iOS sensors",
      "Lists bounded iOS CoreMotion sensor metadata without registering listeners or collecting samples.",
      ["sensors.metadata.read", "sensors.no_sampling"],
      inputSchema: inputSchema(properties: [
        "limit": integerSchema(minimum: 1, maximum: Int64(maxSensorResults))
      ])
    ),
    sensorSampleSpec(
      sensorSample,
      "Read one foreground sensor sample",
      "Reads one sample from an iOS CoreMotion non-health sensor allowlist and stops updates immediately."
    ),
    flashlightSpec(
      flashlightSet,
      "Set flashlight",
      "Requests an explicit iOS torch state through AVFoundation after consent; no camera image is captured."
    ),
    bluetoothStatusSpec(
      bluetoothStatus,
      "Read Bluetooth status",
      "Reads iOS CoreBluetooth permission/framework boundary without device identifiers or discovery."
    ),
    bluetoothDiscoverySpec(
      bluetoothDiscoveryForeground,
      "Discover Bluetooth devices once",
      "Runs one bounded foreground CoreBluetooth LE scan, returns app-scoped observations, then stops scanning."
    ),
    handoffSpec(
      bluetoothPairingHandoff,
      "Open Bluetooth pairing settings",
      "Returns a user-visible iOS Settings handoff request; iOS does not allow silent Bluetooth pairing."
    ),
    statusSpec(
      nfcStatus,
      "Read NFC capability status",
      "Reads iOS CoreNFC reader availability without starting a tag capture session.",
      ["nfc.status.read", "nfc.no_tag_capture", "nfc.no_transaction"]
    ),
    appVisibilityBoundarySpec(
      installedAppsList,
      "List visible apps",
      "Returns a structured iOS app visibility boundary result; iOS cannot enumerate all installed apps for normal apps.",
      ["apps.query_visible"],
      [installedAppsConsent],
      inputSchema: inputSchema(properties: [
        "query": stringSchema(maxLength: 160),
        "limit": integerSchema(minimum: 1, maximum: 100)
      ])
    ),
    appVisibilityBoundarySpec(
      packageDetail,
      "Read visible app detail",
      "Returns a structured iOS package visibility boundary result; iOS cannot inspect arbitrary package metadata.",
      ["apps.package_detail"],
      [packageDetailConsent],
      inputSchema: inputSchema(
        properties: ["package_name": stringSchema(maxLength: 255)],
        required: ["package_name"]
      )
    )
  ]

  private static func definition(_ specification: Specification) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: specification.id,
      version: AgentPhoneNativeToolCatalog.version,
      title: specification.title,
      description: specification.description,
      location: .application,
      inputSchema: specification.inputSchema,
      outputSchema: specification.outputSchema,
      risk: specification.risk,
      capabilities: specification.capabilities,
      requiredPermissions: specification.permissions,
      requiredConsents: specification.consents,
      timeoutMillis: specification.timeoutMillis,
      idempotency: specification.idempotency,
      availability: specification.availability
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "platform": "ios",
        "compatibility_source": "AgentHardwareNativeTools",
        "result_policy": "bounded-v1",
        "background_capture": "false",
        "silent_settings_changes": "false"
      ]
    )
  }

  private static func statusSpec(
    _ id: String,
    _ title: String,
    _ description: String,
    _ capabilities: Set<String>,
    inputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema()
  ) -> Specification {
    Specification(
      id: id,
      title: title,
      description: description,
      risk: .low,
      capabilities: capabilities,
      permissions: [
        AgentNativePermissionRequirement(
          id: hardwareStatusPermission,
          title: "App-visible hardware status",
          description: "Limits execution to bounded status fields visible to the iOS app process."
        )
      ],
      consents: [noExtraConsent],
      availability: .available,
      inputSchema: inputSchema
    )
  }

  private static func foregroundLocationSpec(
    _ id: String,
    _ title: String,
    _ description: String
  ) -> Specification {
    Specification(
      id: id,
      title: title,
      description: description,
      risk: .high,
      capabilities: ["location.foreground.single_fix", "location.no_background_tracking"],
      permissions: [
        AgentNativePermissionRequirement(
          id: "NSLocationWhenInUseUsageDescription",
          title: "Foreground location",
          description: "iOS When In Use location permission for one foreground fix."
        )
      ],
      consents: [
        AgentNativeConsentRequirement(
          id: foregroundLocationConsent,
          title: "Read foreground location once",
          description: "Requires confirmation before reading one bounded foreground location fix."
        )
      ],
      availability: .available,
      inputSchema: inputSchema(properties: [
        "timeout_ms": integerSchema(minimum: 1_000, maximum: maxLocationTimeoutMillis)
      ]),
      timeoutMillis: maxLocationTimeoutMillis
    )
  }

  private static func sensorSampleSpec(
    _ id: String,
    _ title: String,
    _ description: String
  ) -> Specification {
    Specification(
      id: id,
      title: title,
      description: description,
      risk: .medium,
      capabilities: [
        "sensors.foreground.single_sample",
        "sensors.non_health_allowlist",
        "sensors.no_background_stream"
      ],
      permissions: [
        AgentNativePermissionRequirement(
          id: sensorSamplePermission,
          title: "Foreground CoreMotion sample",
          description: "Limits execution to one foreground iOS CoreMotion sensor sample; health sensors are outside the allowlist."
        )
      ],
      consents: [
        AgentNativeConsentRequirement(
          id: sensorSampleConsent,
          title: "Read one sensor sample while foreground",
          description: "Requires confirmation before reading one bounded foreground CoreMotion sample."
        )
      ],
      availability: AgentNativeToolAvailability(
        status: .available,
        reason: "iOS CoreMotion provides foreground-only samples for a bounded non-health sensor allowlist."
      ),
      inputSchema: inputSchema(
        properties: [
          "type": stringSchema(enumValues: sensorSampleTypes),
          "timeout_ms": integerSchema(minimum: minSensorTimeoutMillis, maximum: maxSensorTimeoutMillis)
        ],
        required: ["type"]
      ),
      outputSchema: inputSchema(
        properties: [
          "type": stringSchema(enumValues: sensorSampleTypes),
          "android_type": integerSchema(minimum: 1),
          "values": arraySchema(
            itemSchema: numberSchema(),
            minItems: 1,
            maxItems: Int64(maxSensorValues)
          ),
          "accuracy": integerSchema(),
          "observed_at_epoch_ms": integerSchema(minimum: 0),
          "capture_mode": stringSchema(enumValues: ["single_foreground_sample"]),
          "background_capture": boolSchema()
        ],
        required: [
          "type",
          "android_type",
          "values",
          "accuracy",
          "observed_at_epoch_ms",
          "capture_mode",
          "background_capture"
        ]
      ),
      timeoutMillis: maxSensorTimeoutMillis
    )
  }

  private static func handoffSpec(
    _ id: String,
    _ title: String,
    _ description: String
  ) -> Specification {
    Specification(
      id: id,
      title: title,
      description: description,
      risk: .high,
      capabilities: ["bluetooth.no_silent_pairing"],
      permissions: [
        AgentNativePermissionRequirement(
          id: hardwareStatusPermission,
          title: "iOS handoff scope",
          description: "Limits execution to a user-visible Settings handoff request."
        )
      ],
      consents: [
        AgentNativeConsentRequirement(
          id: userVisibleHandoffConsent,
          title: "Open iOS Settings",
          description: "Requires user confirmation before opening a system settings surface."
        )
      ],
      availability: .available
    )
  }

  private static func flashlightSpec(
    _ id: String,
    _ title: String,
    _ description: String
  ) -> Specification {
    Specification(
      id: id,
      title: title,
      description: description,
      risk: .medium,
      capabilities: ["flashlight.explicit_control", "flashlight.no_camera_capture"],
      permissions: [
        AgentNativePermissionRequirement(
          id: "NSCameraUsageDescription",
          title: "Camera hardware access",
          description: "iOS camera hardware scope is used only for torch control; no image is captured."
        )
      ],
      consents: [
        AgentNativeConsentRequirement(
          id: flashlightControlConsent,
          title: "Control flashlight",
          description: "Requires confirmation before changing the iOS torch state."
        )
      ],
      availability: .available,
      inputSchema: inputSchema(
        properties: ["enabled": boolSchema()],
        required: ["enabled"]
      ),
      idempotency: .idempotent
    )
  }

  private static func bluetoothStatusSpec(
    _ id: String,
    _ title: String,
    _ description: String
  ) -> Specification {
    Specification(
      id: id,
      title: title,
      description: description,
      risk: .medium,
      capabilities: ["bluetooth.status.read", "bluetooth.no_device_identifiers", "bluetooth.no_discovery"],
      permissions: [
        AgentNativePermissionRequirement(
          id: "NSBluetoothAlwaysUsageDescription",
          title: "Bluetooth state",
          description: "iOS Bluetooth scope is used only for adapter/status boundary reporting; no discovery is started."
        )
      ],
      consents: [noExtraConsent],
      availability: AgentNativeToolAvailability(
        status: .available,
        reason: "iOS CoreBluetooth state is exposed as a no-discovery status boundary without bonded-device identifiers."
      )
    )
  }

  private static func bluetoothDiscoverySpec(
    _ id: String,
    _ title: String,
    _ description: String
  ) -> Specification {
    Specification(
      id: id,
      title: title,
      description: description,
      risk: .high,
      capabilities: [
        "bluetooth.discovery.foreground_bounded",
        "bluetooth.discovery.no_background_receiver",
        "bluetooth.discovery.ios_app_scoped_identifiers"
      ],
      permissions: [
        AgentNativePermissionRequirement(
          id: "NSBluetoothAlwaysUsageDescription",
          title: "Discover nearby Bluetooth devices",
          description: "iOS CoreBluetooth permission for one bounded foreground LE scan; hardware MAC addresses and bonded inventory are not exposed."
        )
      ],
      consents: [
        AgentNativeConsentRequirement(
          id: bluetoothDiscoveryConsent,
          title: "Discover nearby Bluetooth devices once",
          description: "Requires confirmation before running one bounded foreground Bluetooth scan."
        )
      ],
      availability: AgentNativeToolAvailability(
        status: .available,
        reason: "iOS CoreBluetooth supports foreground LE scans with app-scoped peripheral identifiers and no bonded-device inventory."
      ),
      inputSchema: inputSchema(properties: [
        "timeout_ms": integerSchema(minimum: minBluetoothDiscoveryMillis, maximum: maxBluetoothDiscoveryMillis),
        "limit": integerSchema(minimum: 1, maximum: Int64(maxBluetoothResults))
      ]),
      outputSchema: inputSchema(
        properties: [
          "devices": arraySchema(
            itemSchema: bluetoothDeviceSchema(),
            maxItems: Int64(maxBluetoothResults)
          ),
          "result_count": integerSchema(minimum: 0, maximum: Int64(maxBluetoothResults)),
          "completed": boolSchema(),
          "timed_out": boolSchema(),
          "truncated": boolSchema(),
          "observed_at_epoch_ms": integerSchema(minimum: 0),
          "capture_mode": stringSchema(enumValues: ["single_foreground_discovery"]),
          "background_capture": boolSchema()
        ],
        required: [
          "devices",
          "result_count",
          "completed",
          "timed_out",
          "truncated",
          "observed_at_epoch_ms",
          "capture_mode",
          "background_capture"
        ]
      ),
      timeoutMillis: maxBluetoothDiscoveryMillis
    )
  }

  private static func appVisibilityBoundarySpec(
    _ id: String,
    _ title: String,
    _ description: String,
    _ capabilities: Set<String>,
    _ consents: [String],
    inputSchema: AgentMcpJSONObject
  ) -> Specification {
    Specification(
      id: id,
      title: title,
      description: description,
      risk: .medium,
      capabilities: capabilities,
      permissions: [
        AgentNativePermissionRequirement(
          id: appVisibilityBoundaryPermission,
          title: "iOS app visibility boundary",
          description: "Limits execution to declared app visibility metadata; full installed-app inventory is not exposed."
        )
      ],
      consents: consents.map {
        AgentNativeConsentRequirement(id: $0, title: $0.replacingOccurrences(of: "signalasi.consent.", with: ""))
      },
      availability: AgentNativeToolAvailability(
        status: .available,
        reason: "iOS exposes only declared app visibility; full installed-app inventory and arbitrary package metadata are unavailable."
      ),
      inputSchema: inputSchema
    )
  }

  private static func unavailableSpec(
    _ id: String,
    _ title: String,
    _ description: String,
    _ risk: AgentNativeToolRisk,
    _ capabilities: Set<String>,
    _ permissions: [String],
    _ consents: [String]
  ) -> Specification {
    Specification(
      id: id,
      title: title,
      description: description,
      risk: risk,
      capabilities: capabilities,
      permissions: ([AgentNativePermissionRequirement(
        id: hardwareStatusPermission,
        title: "iOS hardware executor boundary",
        description: "Requires an iOS app-layer hardware executor before this tool can run."
      )] + permissions.map {
        AgentNativePermissionRequirement(id: $0, title: $0)
      }).sorted { $0.id < $1.id },
      consents: (consents.map {
        AgentNativeConsentRequirement(id: $0, title: $0.replacingOccurrences(of: "signalasi.consent.", with: ""))
      } + [noExtraConsent]).sorted { $0.id < $1.id },
      availability: AgentNativeToolAvailability(
        status: .unavailable,
        reason: "This Android hardware native tool needs a dedicated iOS 15+ framework executor before it can run."
      )
    )
  }

  private static func inputSchema(
    properties: [String: AgentMcpJSONObject],
    required: [String] = []
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties.mapValues { .object($0) }),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(false)
    ]
  }

  private static func bluetoothDeviceSchema() -> AgentMcpJSONObject {
    inputSchema(
      properties: [
        "address": stringSchema(maxLength: 64),
        "name": nullable(stringSchema(maxLength: maxBluetoothNameChars)),
        "bond_state": stringSchema(enumValues: ["none", "bonding", "bonded", "unknown"]),
        "device_type": stringSchema(enumValues: ["classic", "low_energy", "dual", "unknown"]),
        "identifier_scope": stringSchema(enumValues: ["ios_app_scoped_uuid"])
      ],
      required: ["address", "name", "bond_state", "device_type", "identifier_scope"]
    )
  }

  private static func nullable(_ schema: AgentMcpJSONObject) -> AgentMcpJSONObject {
    var nullableSchema = schema
    if case .string(let type)? = nullableSchema["type"] {
      nullableSchema["type"] = .array([.string(type), .string("null")])
    } else if case .array(let types)? = nullableSchema["type"] {
      let existing = types.compactMap(\.strictStringValue)
      nullableSchema["type"] = .array((existing + ["null"]).map(AgentMcpJSONValue.string))
    } else {
      nullableSchema["type"] = .array([.string("null")])
    }
    return nullableSchema
  }

  private static func stringSchema(maxLength: Int64? = nil, enumValues: [String] = []) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = [
      "type": .string("string")
    ]
    if let maxLength = maxLength {
      schema["maxLength"] = .int(maxLength)
    }
    if !enumValues.isEmpty {
      schema["enum"] = .array(enumValues.map(AgentMcpJSONValue.string))
    }
    return schema
  }

  private static func numberSchema() -> AgentMcpJSONObject {
    [
      "type": .string("number")
    ]
  }

  private static func integerSchema(minimum: Int64? = nil, maximum: Int64? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = [
      "type": .string("integer")
    ]
    if let minimum = minimum {
      schema["minimum"] = .int(minimum)
    }
    if let maximum = maximum {
      schema["maximum"] = .int(maximum)
    }
    return schema
  }

  private static func arraySchema(
    itemSchema: AgentMcpJSONObject,
    minItems: Int64? = nil,
    maxItems: Int64? = nil
  ) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = [
      "type": .string("array"),
      "items": .object(itemSchema)
    ]
    if let minItems = minItems {
      schema["minItems"] = .int(minItems)
    }
    if let maxItems = maxItems {
      schema["maxItems"] = .int(maxItems)
    }
    return schema
  }

  private static func boolSchema() -> AgentMcpJSONObject {
    ["type": .string("boolean")]
  }

  private static let noExtraConsent = AgentNativeConsentRequirement(
    id: "signalasi.consent.none",
    title: "No additional consent",
    description: "No additional interactive consent is required.",
    required: false
  )
}

struct AgentIOSHardwareNativeToolExecutor {
  var provider: AgentIOSHardwareStatusProviding
  var locationProvider: AgentIOSForegroundLocationProviding
  var sensorSampleProvider: AgentIOSSensorSampleProviding
  var bluetoothDiscoveryProvider: AgentIOSBluetoothDiscoveryProviding
  var nowMillis: () -> Int64

  init(
    provider: AgentIOSHardwareStatusProviding = AgentIOSDefaultHardwareStatusProvider(),
    locationProvider: AgentIOSForegroundLocationProviding = AgentIOSDefaultForegroundLocationProvider(),
    sensorSampleProvider: AgentIOSSensorSampleProviding = AgentIOSCoreMotionSensorSampleProvider(),
    bluetoothDiscoveryProvider: AgentIOSBluetoothDiscoveryProviding = AgentIOSCoreBluetoothDiscoveryProvider(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.provider = provider
    self.locationProvider = locationProvider
    self.sensorSampleProvider = sensorSampleProvider
    self.bluetoothDiscoveryProvider = bluetoothDiscoveryProvider
    self.nowMillis = nowMillis
  }

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = self.execute(invocation)
        try invocation.checkpoint()
        return result
      }
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let now = max(0, nowMillis())
    switch invocation.descriptor.id {
    case AgentIOSHardwareNativeToolCatalog.batteryStatus:
      return status(provider.batteryStatus(nowMillis: now), "Battery status read")
    case AgentIOSHardwareNativeToolCatalog.powerStatus:
      return status(provider.powerStatus(nowMillis: now), "Power status read")
    case AgentIOSHardwareNativeToolCatalog.storageStatus:
      return status(provider.storageStatus(nowMillis: now), "Storage status read")
    case AgentIOSHardwareNativeToolCatalog.networkStatus:
      return status(provider.networkStatus(nowMillis: now), "Network status read")
    case AgentIOSHardwareNativeToolCatalog.locationForegroundRead:
      let timeout = invocation.input["timeout_ms"]?.intValue ?? AgentIOSHardwareNativeToolCatalog.maxLocationTimeoutMillis
      return locationProvider.foregroundLocation(
        timeoutMillis: max(1_000, min(AgentIOSHardwareNativeToolCatalog.maxLocationTimeoutMillis, timeout)),
        nowMillis: now
      )
    case AgentIOSHardwareNativeToolCatalog.sensorsList:
      let limit = Int(invocation.input["limit"]?.intValue ?? Int64(AgentIOSHardwareNativeToolCatalog.maxSensorResults))
      return status(
        provider.sensorsList(limit: limit, nowMillis: now),
        "Device sensor metadata listed"
      )
    case AgentIOSHardwareNativeToolCatalog.sensorSample:
      let type = boundedString(invocation.input["type"]?.stringValue, limit: 64)
      let timeout = invocation.input["timeout_ms"]?.intValue ?? AgentIOSHardwareNativeToolCatalog.maxSensorTimeoutMillis
      return sensorSampleProvider.sampleSensor(
        type: type,
        timeoutMillis: max(
          AgentIOSHardwareNativeToolCatalog.minSensorTimeoutMillis,
          min(AgentIOSHardwareNativeToolCatalog.maxSensorTimeoutMillis, timeout)
        ),
        nowMillis: now
      )
    case AgentIOSHardwareNativeToolCatalog.flashlightSet:
      return provider.setFlashlight(
        enabled: invocation.input["enabled"]?.boolValue == true,
        nowMillis: now
      )
    case AgentIOSHardwareNativeToolCatalog.bluetoothStatus:
      return status(provider.bluetoothStatus(nowMillis: now), "Bluetooth adapter status boundary read")
    case AgentIOSHardwareNativeToolCatalog.bluetoothDiscoveryForeground:
      let limit = Int(invocation.input["limit"]?.intValue ?? Int64(AgentIOSHardwareNativeToolCatalog.maxBluetoothResults))
      let timeout = invocation.input["timeout_ms"]?.intValue ?? AgentIOSHardwareNativeToolCatalog.maxBluetoothDiscoveryMillis
      return bluetoothDiscoveryProvider.discoverBluetooth(
        timeoutMillis: max(
          AgentIOSHardwareNativeToolCatalog.minBluetoothDiscoveryMillis,
          min(AgentIOSHardwareNativeToolCatalog.maxBluetoothDiscoveryMillis, timeout)
        ),
        limit: max(1, min(AgentIOSHardwareNativeToolCatalog.maxBluetoothResults, limit)),
        nowMillis: now
      )
    case AgentIOSHardwareNativeToolCatalog.nfcStatus:
      return status(provider.nfcStatus(nowMillis: now), "NFC capability status read")
    case AgentIOSHardwareNativeToolCatalog.bluetoothPairingHandoff:
      return AgentNativeToolExecutionResult.success(
        output: [
          "handoff_kind": .string("settings"),
          "url": .string("app-settings:"),
          "settings_target": .string("bluetooth"),
          "requires_user_action": .bool(true),
          "completion_untrusted": .bool(true),
          "platform": .string("ios"),
          "tool_id": .string(invocation.descriptor.id)
        ],
        message: "Bluetooth settings handoff prepared; iOS requires user-controlled pairing.",
        metadata: ["handoff_required": .bool(true), "background_capture": .bool(false)]
      )
    case AgentIOSHardwareNativeToolCatalog.installedAppsList:
      return installedAppsBoundary(invocation, nowMillis: now)
    case AgentIOSHardwareNativeToolCatalog.packageDetail:
      return packageDetailBoundary(invocation, nowMillis: now)
    default:
      return AgentNativeToolExecutionResult.failure(
        code: "ios_hardware_tool_unavailable",
        message: "This hardware native tool is not executable on iOS yet."
      )
    }
  }

  private func status(_ output: AgentMcpJSONObject, _ message: String) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: output,
      message: message,
      metadata: ["background_capture": .bool(false), "identifiers_included": .bool(false)]
    )
  }

  private func installedAppsBoundary(
    _ invocation: AgentNativeToolInvocation,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult {
    let query = boundedString(invocation.input["query"]?.stringValue, limit: 160)
    let limit = max(1, min(100, Int(invocation.input["limit"]?.intValue ?? 20)))
    return AgentNativeToolExecutionResult.success(
      output: [
        "apps": .array([]),
        "result_count": .int(0),
        "total_observed": .int(0),
        "query": .string(query),
        "limit": .int(Int64(limit)),
        "scope": .string("ios_declared_app_visibility_only"),
        "full_inventory_available": .bool(false),
        "declared_scheme_probe_required": .bool(true),
        "observed_at_epoch_ms": .int(nowMillis)
      ],
      message: "iOS app visibility boundary returned no full installed-app inventory.",
      metadata: appVisibilityMetadata(invocation)
    )
  }

  private func packageDetailBoundary(
    _ invocation: AgentNativeToolInvocation,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult {
    let packageName = boundedString(invocation.input["package_name"]?.stringValue, limit: 255)
    guard !packageName.isEmpty else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_package_name",
        message: "Package name is required for iOS app visibility boundary lookup."
      )
    }
    return AgentNativeToolExecutionResult.success(
      output: [
        "package_name": .string(packageName),
        "visible": .bool(false),
        "label": .null,
        "version_name": .null,
        "version_code": .null,
        "enabled": .null,
        "system_app": .null,
        "launchable": .null,
        "requested_permissions": .array([]),
        "scope": .string("ios_declared_app_visibility_only"),
        "metadata_available": .bool(false),
        "full_package_metadata_available": .bool(false),
        "observed_at_epoch_ms": .int(nowMillis)
      ],
      message: "iOS app visibility boundary cannot inspect arbitrary package metadata.",
      metadata: appVisibilityMetadata(invocation)
    )
  }

  private func appVisibilityMetadata(_ invocation: AgentNativeToolInvocation) -> AgentMcpJSONObject {
    [
      "background_capture": .bool(false),
      "identifiers_included": .bool(false),
      "package_inventory_exposed": .bool(false),
      "platform_boundary": .string("ios_app_visibility_boundary"),
      "tool_id": .string(invocation.descriptor.id)
    ]
  }

  private func boundedString(_ value: String?, limit: Int) -> String {
    String((value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}
