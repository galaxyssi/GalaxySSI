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
        available: manager.isGyroAvailable,
        type: "gyroscope",
        androidType: 4,
        name: "iOS Gyroscope"
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
  static let userVisibleHandoffConsent = "signalasi.consent.ios_settings_handoff"
  static let flashlightControlConsent = "signalasi.consent.flashlight.control"
  static let installedAppsConsent = "signalasi.consent.installed_apps.query_visible"
  static let packageDetailConsent = "signalasi.consent.package_detail.query_visible"
  static let maxSensorResults = 64

  static let executableToolIds: Set<String> = [
    batteryStatus,
    powerStatus,
    storageStatus,
    networkStatus,
    sensorsList,
    flashlightSet,
    bluetoothStatus,
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
    var idempotency: AgentNativeToolIdempotency = .nonIdempotent
  }

  private static let specifications: [Specification] = [
    statusSpec(batteryStatus, "Read battery status", "Reads app-visible iOS battery status without vendor diagnostics.", ["battery.status"]),
    statusSpec(powerStatus, "Read power status", "Reads app-visible iOS power and thermal status without changing settings.", ["power.status"]),
    statusSpec(storageStatus, "Read storage status", "Reads bounded app-volume storage capacity signals.", ["storage.status"]),
    statusSpec(networkStatus, "Read network status", "Returns identifier-free app-visible network state from the iOS status provider.", ["network.status"]),
    unavailableSpec(
      locationForegroundRead,
      "Read foreground location",
      "Requires a CoreLocation foreground executor and runtime permission prompt before iOS can return a bounded fix.",
      .high,
      ["location.foreground_once"],
      ["NSLocationWhenInUseUsageDescription"],
      ["signalasi.consent.location.foreground_once"]
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
    unavailableSpec(
      sensorSample,
      "Sample iOS sensor once",
      "Requires a foreground CoreMotion sample executor and per-invocation consent.",
      .medium,
      ["sensors.non_health_allowlist"],
      [],
      ["signalasi.consent.sensor.foreground_once"]
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
    unavailableSpec(
      bluetoothDiscoveryForeground,
      "Discover Bluetooth devices once",
      "Requires a foreground CoreBluetooth scan executor and per-invocation consent.",
      .high,
      ["bluetooth.discovery.foreground"],
      ["NSBluetoothAlwaysUsageDescription"],
      ["signalasi.consent.bluetooth.discovery.foreground_once"]
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
      outputSchema: AgentNativeToolDescriptor.objectSchema(),
      risk: specification.risk,
      capabilities: specification.capabilities,
      requiredPermissions: specification.permissions,
      requiredConsents: specification.consents,
      timeoutMillis: 15_000,
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

  private static func stringSchema(maxLength: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("string"),
      "maxLength": .int(maxLength)
    ]
  }

  private static func integerSchema(minimum: Int64, maximum: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("integer"),
      "minimum": .int(minimum),
      "maximum": .int(maximum)
    ]
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
  var nowMillis: () -> Int64

  init(
    provider: AgentIOSHardwareStatusProviding = AgentIOSDefaultHardwareStatusProvider(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.provider = provider
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
    case AgentIOSHardwareNativeToolCatalog.sensorsList:
      let limit = Int(invocation.input["limit"]?.intValue ?? Int64(AgentIOSHardwareNativeToolCatalog.maxSensorResults))
      return status(
        provider.sensorsList(limit: limit, nowMillis: now),
        "Device sensor metadata listed"
      )
    case AgentIOSHardwareNativeToolCatalog.flashlightSet:
      return provider.setFlashlight(
        enabled: invocation.input["enabled"]?.boolValue == true,
        nowMillis: now
      )
    case AgentIOSHardwareNativeToolCatalog.bluetoothStatus:
      return status(provider.bluetoothStatus(nowMillis: now), "Bluetooth adapter status boundary read")
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
