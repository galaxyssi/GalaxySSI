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
    return [
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
    return [
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
