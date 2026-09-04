import Foundation

enum AgentPhoneCapabilityId: String, Codable, CaseIterable, Identifiable {
  case accessibilityUITree = "ACCESSIBILITY_UI_TREE"
  case accessibilityGestures = "ACCESSIBILITY_GESTURES"
  case ownedAgentInput = "OWNED_AGENT_INPUT"
  case ownedAgentTranscript = "OWNED_AGENT_TRANSCRIPT"
  case ownedAgentControls = "OWNED_AGENT_CONTROLS"
  case ownedAgentLongPress = "OWNED_AGENT_LONG_PRESS"
  case ownedAgentNavigation = "OWNED_AGENT_NAVIGATION"
  case mediaProjectionOCR = "MEDIA_PROJECTION_OCR"
  case notificationRead = "NOTIFICATION_READ"
  case notificationReply = "NOTIFICATION_REPLY"
  case clipboard = "CLIPBOARD"
  case camera = "CAMERA"
  case microphone = "MICROPHONE"
  case location = "LOCATION"
  case sensors = "SENSORS"
  case bluetooth = "BLUETOOTH"
  case nfc = "NFC"
  case battery = "BATTERY"
  case deviceMemory = "DEVICE_MEMORY"
  case network = "NETWORK"
  case installedApps = "INSTALLED_APPS"
  case intentLaunch = "INTENT_LAUNCH"
  case systemSettings = "SYSTEM_SETTINGS"
  case packageInstallHandoff = "PACKAGE_INSTALL_HANDOFF"
  case deviceOwner = "DEVICE_OWNER"
  case shizuku = "SHIZUKU"
  case root = "ROOT"
  case homeAssistant = "HOME_ASSISTANT"
  case mediaPlayback = "MEDIA_PLAYBACK"
  case mediaTranscode = "MEDIA_TRANSCODE"

  var id: String { rawValue }

  var wireId: String {
    "phone.\(rawValue.lowercased().replacingOccurrences(of: "_", with: "."))"
  }

  static func fromWireValue(_ value: String?) -> AgentPhoneCapabilityId? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self)) ?? .network
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentPhoneExecutionLocation: String, Codable, CaseIterable, Identifiable {
  case appProcess = "APP_PROCESS"
  case accessibilityService = "ACCESSIBILITY_SERVICE"
  case screenCaptureService = "SCREEN_CAPTURE_SERVICE"
  case notificationListenerService = "NOTIFICATION_LISTENER_SERVICE"
  case androidSystemService = "ANDROID_SYSTEM_SERVICE"
  case systemUIHandoff = "SYSTEM_UI_HANDOFF"
  case onDeviceLinuxRuntime = "ON_DEVICE_LINUX_RUNTIME"
  case privilegedBridge = "PRIVILEGED_BRIDGE"
  case homeAssistantServer = "HOME_ASSISTANT_SERVER"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPhoneExecutionLocation {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .appProcess
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentPhoneCapabilityAvailability: String, Codable, CaseIterable, Identifiable {
  case ready = "READY"
  case limited = "LIMITED"
  case needsRuntimePermission = "NEEDS_RUNTIME_PERMISSION"
  case needsSpecialAccess = "NEEDS_SPECIAL_ACCESS"
  case needsUserConsent = "NEEDS_USER_CONSENT"
  case needsConfiguration = "NEEDS_CONFIGURATION"
  case notImplemented = "NOT_IMPLEMENTED"
  case privilegedOnly = "PRIVILEGED_ONLY"
  case unsupported = "UNSUPPORTED"
  case blockedByPolicy = "BLOCKED_BY_POLICY"
  case unknown = "UNKNOWN"

  var id: String { rawValue }

  var nativeAvailabilityStatus: AgentNativeToolAvailabilityStatus {
    switch self {
    case .ready, .limited:
      return .available
    case .needsRuntimePermission, .needsSpecialAccess, .needsUserConsent, .needsConfiguration:
      return .requiresSetup
    case .notImplemented, .privilegedOnly, .unsupported, .blockedByPolicy, .unknown:
      return .unavailable
    }
  }

  static func fromWireValue(_ value: String?) -> AgentPhoneCapabilityAvailability {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .unknown
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentPhoneSpecialAccess: String, Codable, CaseIterable, Identifiable {
  case accessibilityService = "ACCESSIBILITY_SERVICE"
  case mediaProjectionSession = "MEDIA_PROJECTION_SESSION"
  case notificationListener = "NOTIFICATION_LISTENER"
  case packageVisibilityDeclarations = "PACKAGE_VISIBILITY_DECLARATIONS"
  case installUnknownApps = "INSTALL_UNKNOWN_APPS"
  case deviceOwnerRole = "DEVICE_OWNER_ROLE"
  case shizukuService = "SHIZUKU_SERVICE"
  case rootGrant = "ROOT_GRANT"

  var id: String { rawValue }
}

enum AgentPhoneUserConsent: String, Codable, CaseIterable, Identifiable {
  case none = "NONE"
  case runtimePermissionDialog = "RUNTIME_PERMISSION_DIALOG"
  case enableInSystemSettings = "ENABLE_IN_SYSTEM_SETTINGS"
  case perSessionScreenCapture = "PER_SESSION_SCREEN_CAPTURE"
  case sensitiveActionConfirmation = "SENSITIVE_ACTION_CONFIRMATION"
  case userVisibleCapture = "USER_VISIBLE_CAPTURE"
  case physicalProximity = "PHYSICAL_PROXIMITY"
  case packageInstallerConfirmation = "PACKAGE_INSTALLER_CONFIRMATION"
  case deviceProvisioning = "DEVICE_PROVISIONING"
  case privilegedBridgeAuthorization = "PRIVILEGED_BRIDGE_AUTHORIZATION"
  case superuserPrompt = "SUPERUSER_PROMPT"
  case externalServiceCredentials = "EXTERNAL_SERVICE_CREDENTIALS"

  var id: String { rawValue }
}

struct AgentPhoneCapabilityBoundary: Codable, Equatable, Identifiable {
  var id: AgentPhoneCapabilityId
  var executionLocation: AgentPhoneExecutionLocation
  var availability: AgentPhoneCapabilityAvailability
  var platformPermissions: Set<String>
  var specialAccess: Set<AgentPhoneSpecialAccess>
  var userConsent: Set<AgentPhoneUserConsent>
  var risk: AgentRisk
  var normalAppCanExecute: Bool
  var limitation: String

  init(
    id: AgentPhoneCapabilityId,
    executionLocation: AgentPhoneExecutionLocation,
    availability: AgentPhoneCapabilityAvailability,
    platformPermissions: Set<String> = [],
    specialAccess: Set<AgentPhoneSpecialAccess> = [],
    userConsent: Set<AgentPhoneUserConsent> = [.none],
    risk: AgentRisk,
    normalAppCanExecute: Bool,
    limitation: String
  ) {
    self.id = id
    self.executionLocation = executionLocation
    self.availability = availability
    self.platformPermissions = platformPermissions
    self.specialAccess = specialAccess
    self.userConsent = userConsent.isEmpty ? [.none] : userConsent
    self.risk = risk
    self.normalAppCanExecute = normalAppCanExecute
    self.limitation = limitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "Platform boundary must be checked before this capability is used."
      : limitation
  }

  enum CodingKeys: String, CodingKey {
    case id
    case executionLocation = "execution_location"
    case availability
    case platformPermissions = "platform_permissions"
    case specialAccess = "special_access"
    case userConsent = "user_consent"
    case risk
    case normalAppCanExecute = "normal_app_can_execute"
    case limitation
  }
}

struct AgentPhoneCapabilityObservation: Codable, Equatable {
  var probeSucceeded: Bool
  var platformSupported: Bool
  var implementationPresent: Bool
  var permissionsGranted: Bool
  var specialAccessGranted: Bool
  var userConsentGranted: Bool
  var configured: Bool
  var limited: Bool
  var evidence: String

  init(
    probeSucceeded: Bool = true,
    platformSupported: Bool = true,
    implementationPresent: Bool = true,
    permissionsGranted: Bool = true,
    specialAccessGranted: Bool = true,
    userConsentGranted: Bool = true,
    configured: Bool = true,
    limited: Bool = false,
    evidence: String = ""
  ) {
    self.probeSucceeded = probeSucceeded
    self.platformSupported = platformSupported
    self.implementationPresent = implementationPresent
    self.permissionsGranted = permissionsGranted
    self.specialAccessGranted = specialAccessGranted
    self.userConsentGranted = userConsentGranted
    self.configured = configured
    self.limited = limited
    self.evidence = evidence
  }

  enum CodingKeys: String, CodingKey {
    case probeSucceeded = "probe_succeeded"
    case platformSupported = "platform_supported"
    case implementationPresent = "implementation_present"
    case permissionsGranted = "permissions_granted"
    case specialAccessGranted = "special_access_granted"
    case userConsentGranted = "user_consent_granted"
    case configured
    case limited
    case evidence
  }
}

struct AgentPhoneCapabilityStatus: Codable, Equatable {
  var boundary: AgentPhoneCapabilityBoundary
  var availability: AgentPhoneCapabilityAvailability
  var evidence: String

  var advertisedAsReady: Bool {
    availability == .ready && boundary.normalAppCanExecute
  }
}

enum AgentPhoneCapabilityNativeCoverage {
  static let toolIdsByCapability: [AgentPhoneCapabilityId: Set<String>] = [
    .notificationRead: [notificationsList],
    .notificationReply: [notificationReply],
    .camera: [cameraCaptureVisible],
    .microphone: [microphoneRecordVisible],
    .location: [locationForegroundRead],
    .sensors: [sensorsList, sensorSample],
    .bluetooth: [bluetoothStatus, bluetoothDiscoveryForeground, bluetoothPairingHandoff],
    .nfc: [nfcStatus],
    .battery: [batteryStatus, powerStatus],
    .deviceMemory: [memoryStatus],
    .network: [networkStatus, wifiStatus, wifiScanResults],
    .installedApps: [installedAppsList, packageDetail],
    .mediaPlayback: [mediaPlaybackHandoff],
    .mediaTranscode: [mediaFFmpegTranscode]
  ]

  static var coveredToolIds: Set<String> {
    toolIdsByCapability.values.reduce(into: Set<String>()) { result, ids in
      result.formUnion(ids)
    }
  }

  static func isImplemented(_ id: AgentPhoneCapabilityId) -> Bool {
    if id == .ownedAgentInput { return true }
    if id == .ownedAgentTranscript { return true }
    if id == .ownedAgentControls { return true }
    if id == .ownedAgentLongPress { return true }
    if id == .ownedAgentNavigation { return true }
    return !toolIdsByCapability[id, default: []].isEmpty
  }

  static let notificationsList = "galaxyssi.notifications.list"
  static let notificationReply = "galaxyssi.notifications.reply"
  static let cameraCaptureVisible = "galaxyssi.camera.capture.visible"
  static let microphoneRecordVisible = "galaxyssi.microphone.record.visible"
  static let locationForegroundRead = "galaxyssi.hardware.location.foreground.read"
  static let sensorsList = "galaxyssi.hardware.sensors.list"
  static let sensorSample = "galaxyssi.hardware.sensor.sample"
  static let bluetoothStatus = "galaxyssi.hardware.bluetooth.status"
  static let bluetoothDiscoveryForeground = "galaxyssi.hardware.bluetooth.discovery.foreground"
  static let bluetoothPairingHandoff = "galaxyssi.hardware.bluetooth.pairing.handoff"
  static let nfcStatus = "galaxyssi.hardware.nfc.status"
  static let batteryStatus = "galaxyssi.hardware.battery.status"
  static let powerStatus = "galaxyssi.hardware.power.status"
  static let memoryStatus = "galaxyssi.hardware.memory.status"
  static let networkStatus = "galaxyssi.hardware.network.status"
  static let wifiStatus = "galaxyssi.android.wifi.status"
  static let wifiScanResults = "galaxyssi.android.wifi.scan_results"
  static let installedAppsList = "galaxyssi.hardware.apps.installed.list"
  static let packageDetail = "galaxyssi.hardware.apps.package.detail"
  static let mediaPlaybackHandoff = "galaxyssi.media.playback.handoff"
  static let mediaFFmpegTranscode = "galaxyssi.media.ffmpeg.transcode"
}

enum AgentPhoneCapabilityPolicy {
  static func resolve(
    _ boundary: AgentPhoneCapabilityBoundary,
    observation: AgentPhoneCapabilityObservation
  ) -> AgentPhoneCapabilityAvailability {
    switch boundary.availability {
    case .blockedByPolicy, .privilegedOnly, .notImplemented, .unsupported, .unknown:
      return boundary.availability
    case .ready, .limited, .needsRuntimePermission, .needsSpecialAccess, .needsUserConsent, .needsConfiguration:
      break
    }
    if !boundary.normalAppCanExecute { return .privilegedOnly }
    if !observation.probeSucceeded { return .unknown }
    if !observation.platformSupported { return .unsupported }
    if !observation.implementationPresent { return .notImplemented }
    if !observation.permissionsGranted { return .needsRuntimePermission }
    if !observation.specialAccessGranted { return .needsSpecialAccess }
    if !observation.userConsentGranted { return .needsUserConsent }
    if !observation.configured { return .needsConfiguration }
    if boundary.availability == .limited || observation.limited { return .limited }
    return .ready
  }
}

enum AgentPhoneCapabilityCatalog {
  static let capabilities: [AgentPhoneCapabilityBoundary] = [
    boundary(
      .ownedAgentControls,
      location: .appProcess,
      availability: .ready,
      risk: .low,
      normalAppCanExecute: true,
      limitation: "Tap actions are limited to visible GalaxySSI-owned Agent home controls and cannot inject gestures into other apps or protected system surfaces."
    ),
    boundary(
      .ownedAgentLongPress,
      location: .appProcess,
      availability: .ready,
      risk: .low,
      normalAppCanExecute: true,
      limitation: "Long-press actions are limited to visible GalaxySSI-owned Agent home controls and cannot inject gestures into other apps or protected system surfaces."
    ),
    boundary(
      .ownedAgentNavigation,
      location: .appProcess,
      availability: .ready,
      risk: .low,
      normalAppCanExecute: true,
      limitation: "Back actions only dismiss an open GalaxySSI Agent home tray or sheet; they cannot navigate other apps or protected system surfaces."
    ),
    boundary(
      .ownedAgentInput,
      location: .appProcess,
      availability: .ready,
      risk: .low,
      normalAppCanExecute: true,
      limitation: "Text actions are limited to the GalaxySSI-owned Agent composer and cannot edit other apps or protected system surfaces."
    ),
    boundary(
      .ownedAgentTranscript,
      location: .appProcess,
      availability: .ready,
      risk: .low,
      normalAppCanExecute: true,
      limitation: "Swipe actions are limited to vertical navigation in the visible GalaxySSI-owned Agent transcript and cannot inject gestures into other apps or protected system surfaces."
    ),
    boundary(
      .accessibilityUITree,
      location: .accessibilityService,
      availability: .unsupported,
      specialAccess: [.accessibilityService],
      userConsent: [.enableInSystemSettings],
      risk: .high,
      normalAppCanExecute: false,
      limitation: "iOS apps cannot inspect other apps' accessibility trees; only GalaxySSI-owned views or explicit user-shared content can be analyzed."
    ),
    boundary(
      .accessibilityGestures,
      location: .accessibilityService,
      availability: .unsupported,
      specialAccess: [.accessibilityService],
      userConsent: [.enableInSystemSettings, .sensitiveActionConfirmation],
      risk: .blocked,
      normalAppCanExecute: false,
      limitation: "An ordinary iOS app cannot inject gestures into other apps, bypass lock screens, or operate protected system surfaces."
    ),
    boundary(
      .mediaProjectionOCR,
      location: .screenCaptureService,
      availability: .needsUserConsent,
      userConsent: [.perSessionScreenCapture, .userVisibleCapture],
      risk: .high,
      normalAppCanExecute: true,
      limitation: "Screen capture on iOS must be user-visible and session-scoped; protected content can be hidden and OCR remains lossy."
    ),
    boundary(
      .notificationRead,
      location: .notificationListenerService,
      availability: .limited,
      userConsent: [.enableInSystemSettings],
      risk: .high,
      normalAppCanExecute: true,
      limitation: "iOS exposes only notifications delivered to GalaxySSI or explicit notification actions; it cannot read arbitrary third-party notification contents."
    ),
    boundary(
      .notificationReply,
      location: .notificationListenerService,
      availability: .limited,
      userConsent: [.enableInSystemSettings, .sensitiveActionConfirmation],
      risk: .high,
      normalAppCanExecute: true,
      limitation: "Replies are limited to GalaxySSI-owned notification actions and require user-visible confirmation; other apps' notification replies remain unavailable."
    ),
    boundary(
      .clipboard,
      location: .appProcess,
      availability: .limited,
      risk: .high,
      normalAppCanExecute: true,
      limitation: "iOS pasteboard access can trigger privacy prompts and does not prove that a later paste target accepted the value."
    ),
    boundary(
      .camera,
      location: .appProcess,
      availability: .needsRuntimePermission,
      platformPermissions: ["NSCameraUsageDescription"],
      userConsent: [.runtimePermissionDialog, .userVisibleCapture],
      risk: .high,
      normalAppCanExecute: true,
      limitation: "Camera use must stay in a foreground, user-visible capture flow; silent or unattended background capture is excluded."
    ),
    boundary(
      .microphone,
      location: .appProcess,
      availability: .needsRuntimePermission,
      platformPermissions: ["NSMicrophoneUsageDescription"],
      userConsent: [.runtimePermissionDialog, .userVisibleCapture],
      risk: .high,
      normalAppCanExecute: true,
      limitation: "Recording is subject to foreground privacy indicators, audio session routing, interruptions, and other apps holding the microphone."
    ),
    boundary(
      .location,
      location: .androidSystemService,
      availability: .needsRuntimePermission,
      platformPermissions: ["NSLocationWhenInUseUsageDescription"],
      userConsent: [.runtimePermissionDialog],
      risk: .high,
      normalAppCanExecute: true,
      limitation: "GalaxySSI may request one bounded foreground location fix; approximate, stale, disabled, or unavailable location remains possible."
    ),
    boundary(
      .sensors,
      location: .androidSystemService,
      availability: .limited,
      userConsent: [.sensitiveActionConfirmation],
      risk: .medium,
      normalAppCanExecute: true,
      limitation: "iOS exposes a limited foreground sensor surface; continuous, background, health, and privileged motion streams are excluded."
    ),
    boundary(
      .bluetooth,
      location: .appProcess,
      availability: .limited,
      platformPermissions: ["NSBluetoothAlwaysUsageDescription"],
      userConsent: [.runtimePermissionDialog, .sensitiveActionConfirmation],
      risk: .high,
      normalAppCanExecute: true,
      limitation: "Bluetooth is limited to user-authorized CoreBluetooth flows; silent pairing, arbitrary protocol traffic, and background discovery are excluded."
    ),
    boundary(
      .nfc,
      location: .appProcess,
      availability: .limited,
      platformPermissions: ["NFCReaderUsageDescription"],
      userConsent: [.physicalProximity],
      risk: .high,
      normalAppCanExecute: true,
      limitation: "NFC requires a foreground reader session and physical proximity; secure element, payment, and background tag operations are excluded."
    ),
    boundary(
      .battery,
      location: .androidSystemService,
      availability: .ready,
      risk: .low,
      normalAppCanExecute: true,
      limitation: "Only app-visible battery and charging signals are available; health, per-app attribution, and vendor diagnostics may be absent or privileged."
    ),
    boundary(
      .deviceMemory,
      location: .appProcess,
      availability: .ready,
      risk: .low,
      normalAppCanExecute: true,
      limitation: "Reports device-wide RAM totals and an iOS app-visible estimate of available memory; process enumeration and private per-app attribution are excluded."
    ),
    boundary(
      .network,
      location: .appProcess,
      availability: .ready,
      platformPermissions: ["NSLocalNetworkUsageDescription"],
      risk: .medium,
      normalAppCanExecute: true,
      limitation: "Network availability does not guarantee internet reachability; VPN, captive portal, metering, TLS, server policy, and background limits still apply."
    ),
    boundary(
      .installedApps,
      location: .appProcess,
      availability: .limited,
      specialAccess: [.packageVisibilityDeclarations],
      risk: .medium,
      normalAppCanExecute: true,
      limitation: "iOS cannot enumerate all installed apps; only declared URL schemes, document handoffs, and user-selected integrations are visible."
    ),
    boundary(
      .intentLaunch,
      location: .systemUIHandoff,
      availability: .ready,
      userConsent: [.sensitiveActionConfirmation],
      risk: .medium,
      normalAppCanExecute: true,
      limitation: "URL and activity handoffs can open matching apps or system UI, but target availability, chooser UI, and completion cannot be assumed."
    ),
    boundary(
      .systemSettings,
      location: .systemUIHandoff,
      availability: .ready,
      userConsent: [.enableInSystemSettings, .sensitiveActionConfirmation],
      risk: .medium,
      normalAppCanExecute: true,
      limitation: "The app can open allowed Settings screens but cannot silently change protected settings or know that the user completed the change."
    ),
    boundary(
      .packageInstallHandoff,
      location: .systemUIHandoff,
      availability: .unsupported,
      userConsent: [.packageInstallerConfirmation],
      risk: .high,
      normalAppCanExecute: false,
      limitation: "iOS apps cannot install arbitrary packages; distribution is limited to App Store, TestFlight, MDM, or user-managed profiles."
    ),
    boundary(
      .deviceOwner,
      location: .privilegedBridge,
      availability: .privilegedOnly,
      specialAccess: [.deviceOwnerRole],
      userConsent: [.deviceProvisioning],
      risk: .blocked,
      normalAppCanExecute: false,
      limitation: "Device-owner style management requires supervised MDM authority and cannot be self-elevated by the app."
    ),
    boundary(
      .shizuku,
      location: .privilegedBridge,
      availability: .privilegedOnly,
      specialAccess: [.shizukuService],
      userConsent: [.privilegedBridgeAuthorization],
      risk: .blocked,
      normalAppCanExecute: false,
      limitation: "Shizuku is Android-specific and has no iOS runtime bridge in GalaxySSI."
    ),
    boundary(
      .root,
      location: .privilegedBridge,
      availability: .blockedByPolicy,
      specialAccess: [.rootGrant],
      userConsent: [.superuserPrompt],
      risk: .blocked,
      normalAppCanExecute: false,
      limitation: "GalaxySSI does not execute privileged shell commands; jailbreak or root presence is intentionally never advertised as ready."
    ),
    boundary(
      .homeAssistant,
      location: .homeAssistantServer,
      availability: .needsConfiguration,
      userConsent: [.externalServiceCredentials, .sensitiveActionConfirmation],
      risk: .high,
      normalAppCanExecute: true,
      limitation: "Only configured Home Assistant entities and services are reachable; server permissions, entity state, network reachability, and physical outcome remain external."
    ),
    boundary(
      .mediaPlayback,
      location: .appProcess,
      availability: .ready,
      risk: .low,
      normalAppCanExecute: true,
      limitation: "Playback depends on a supported codec and valid source and remains subject to audio focus, output routing, volume, and other app controls."
    ),
    boundary(
      .mediaTranscode,
      location: .onDeviceLinuxRuntime,
      availability: .needsConfiguration,
      risk: .medium,
      normalAppCanExecute: true,
      limitation: "Typed preset conversion is confined to the current workspace and requires a signed local media runtime; arbitrary FFmpeg arguments and network access are excluded."
    )
  ]

  static func find(_ id: AgentPhoneCapabilityId) -> AgentPhoneCapabilityBoundary {
    capabilities.first { $0.id == id }!
  }

  static func declaredStatuses(evidence: String = "Declared iOS capability boundary") -> [AgentPhoneCapabilityStatus] {
    capabilities.map { boundary in
      AgentPhoneCapabilityStatus(
        boundary: boundary,
        availability: boundary.availability,
        evidence: evidence
      )
    }
  }

  static func resolveStatuses(
    observations: [AgentPhoneCapabilityId: AgentPhoneCapabilityObservation],
    defaultEvidence: String = "No live iOS probe supplied"
  ) -> [AgentPhoneCapabilityStatus] {
    capabilities.map { boundary in
      let observation = observations[boundary.id] ?? AgentPhoneCapabilityObservation(
        implementationPresent: AgentPhoneCapabilityNativeCoverage.isImplemented(boundary.id),
        evidence: defaultEvidence
      )
      return AgentPhoneCapabilityStatus(
        boundary: boundary,
        availability: AgentPhoneCapabilityPolicy.resolve(boundary, observation: observation),
        evidence: observation.evidence
      )
    }
  }

  private static func boundary(
    _ id: AgentPhoneCapabilityId,
    location: AgentPhoneExecutionLocation,
    availability: AgentPhoneCapabilityAvailability,
    platformPermissions: Set<String> = [],
    specialAccess: Set<AgentPhoneSpecialAccess> = [],
    userConsent: Set<AgentPhoneUserConsent> = [.none],
    risk: AgentRisk,
    normalAppCanExecute: Bool,
    limitation: String
  ) -> AgentPhoneCapabilityBoundary {
    AgentPhoneCapabilityBoundary(
      id: id,
      executionLocation: location,
      availability: availability,
      platformPermissions: platformPermissions,
      specialAccess: specialAccess,
      userConsent: userConsent,
      risk: risk,
      normalAppCanExecute: normalAppCanExecute,
      limitation: limitation
    )
  }
}
