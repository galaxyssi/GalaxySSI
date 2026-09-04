import Foundation

enum AgentIOSHardwareNativeToolCatalog {
  static let deviceStatus = "galaxyssi.hardware.device.status"
  static let batteryStatus = AgentPhoneCapabilityNativeCoverage.batteryStatus
  static let powerStatus = AgentPhoneCapabilityNativeCoverage.powerStatus
  static let memoryStatus = AgentPhoneCapabilityNativeCoverage.memoryStatus
  static let storageStatus = "galaxyssi.hardware.storage.status"
  static let networkStatus = AgentPhoneCapabilityNativeCoverage.networkStatus
  static let locationForegroundRead = AgentPhoneCapabilityNativeCoverage.locationForegroundRead
  static let sensorsList = AgentPhoneCapabilityNativeCoverage.sensorsList
  static let sensorSample = AgentPhoneCapabilityNativeCoverage.sensorSample
  static let flashlightSet = "galaxyssi.hardware.flashlight.set"
  static let bluetoothStatus = AgentPhoneCapabilityNativeCoverage.bluetoothStatus
  static let bluetoothDiscoveryForeground = AgentPhoneCapabilityNativeCoverage.bluetoothDiscoveryForeground
  static let bluetoothPairingHandoff = AgentPhoneCapabilityNativeCoverage.bluetoothPairingHandoff
  static let nfcStatus = AgentPhoneCapabilityNativeCoverage.nfcStatus
  static let installedAppsList = AgentPhoneCapabilityNativeCoverage.installedAppsList
  static let packageDetail = AgentPhoneCapabilityNativeCoverage.packageDetail

  static let executorId = "galaxyssi.ios.hardware_native"
  static let hardwareStatusPermission = "galaxyssi.scope.ios_app_visible_hardware_status"
  static let appVisibilityBoundaryPermission = "galaxyssi.scope.ios_app_visibility_boundary"
  static let sensorSamplePermission = "galaxyssi.scope.ios_coremotion_foreground_sample"
  static let foregroundLocationConsent = "galaxyssi.consent.location.foreground_once"
  static let sensorSampleConsent = "galaxyssi.consent.sensor.foreground_once"
  static let userVisibleHandoffConsent = "galaxyssi.consent.ios_settings_handoff"
  static let flashlightControlConsent = "galaxyssi.consent.flashlight.control"
  static let bluetoothDiscoveryConsent = "galaxyssi.consent.bluetooth.discovery.foreground_once"
  static let installedAppsConsent = "galaxyssi.consent.installed_apps.query_visible"
  static let packageDetailConsent = "galaxyssi.consent.package_detail.query_visible"
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
    deviceStatus,
    batteryStatus,
    powerStatus,
    memoryStatus,
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
    statusSpec(
      deviceStatus,
      "Read device status",
      "Summarizes app-visible iOS battery, power, memory, storage, and network status without changing settings.",
      ["device.status.read", "device.no_identifiers"]
    ),
    statusSpec(batteryStatus, "Read battery status", "Reads app-visible iOS battery status without vendor diagnostics.", ["battery.status"]),
    statusSpec(powerStatus, "Read power status", "Reads app-visible iOS power and thermal status without changing settings.", ["power.status"]),
    memoryStatusSpec(),
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
    inputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema(),
    outputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema()
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
      inputSchema: inputSchema,
      outputSchema: outputSchema
    )
  }

  private static func memoryStatusSpec() -> Specification {
    statusSpec(
      memoryStatus,
      "Read phone memory status",
      "Reads bounded device RAM totals and low-memory status without enumerating processes.",
      ["memory.device_ram.read", "memory.no_process_enumeration"],
      outputSchema: inputSchema(
        properties: [
          "scope": stringSchema(enumValues: ["device_ram"]),
          "total_bytes": integerSchema(minimum: 0),
          "available_bytes": integerSchema(minimum: 0),
          "used_bytes": integerSchema(minimum: 0),
          "used_percent": integerSchema(minimum: 0, maximum: 100),
          "low_memory": boolSchema(),
          "low_memory_threshold_bytes": integerSchema(minimum: 0),
          "memory_pressure": stringSchema(enumValues: ["normal", "fair", "serious", "critical", "unknown"]),
          "available_memory_estimated": boolSchema(),
          "app_available_memory_budget_bytes": integerSchema(minimum: 0),
          "observed_at_epoch_ms": integerSchema(minimum: 0)
        ],
        required: ["scope", "total_bytes", "available_bytes", "used_bytes", "used_percent", "low_memory", "low_memory_threshold_bytes", "memory_pressure", "available_memory_estimated", "observed_at_epoch_ms"]
      )
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
        AgentNativeConsentRequirement(id: $0, title: $0.replacingOccurrences(of: "galaxyssi.consent.", with: ""))
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
        AgentNativeConsentRequirement(id: $0, title: $0.replacingOccurrences(of: "galaxyssi.consent.", with: ""))
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
    id: "galaxyssi.consent.none",
    title: "No additional consent",
    description: "No additional interactive consent is required.",
    required: false
  )
}

struct AgentIOSHardwareNativeToolExecutor {
  var provider: AgentIOSHardwareStatusProviding
  var memoryProvider: AgentIOSDeviceMemoryStatusProviding
  var locationProvider: AgentIOSForegroundLocationProviding
  var sensorSampleProvider: AgentIOSSensorSampleProviding
  var bluetoothDiscoveryProvider: AgentIOSBluetoothDiscoveryProviding
  var nowMillis: () -> Int64

  init(
    provider: AgentIOSHardwareStatusProviding = AgentIOSDefaultHardwareStatusProvider(),
    memoryProvider: AgentIOSDeviceMemoryStatusProviding = AgentIOSDefaultDeviceMemoryStatusProvider(),
    locationProvider: AgentIOSForegroundLocationProviding = AgentIOSDefaultForegroundLocationProvider(),
    sensorSampleProvider: AgentIOSSensorSampleProviding = AgentIOSCoreMotionSensorSampleProvider(),
    bluetoothDiscoveryProvider: AgentIOSBluetoothDiscoveryProviding = AgentIOSCoreBluetoothDiscoveryProvider(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.provider = provider
    self.memoryProvider = memoryProvider
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
    case AgentIOSHardwareNativeToolCatalog.deviceStatus:
      let output = AgentIOSDeviceHealthStatusPresentation.output(
        battery: provider.batteryStatus(nowMillis: now),
        power: provider.powerStatus(nowMillis: now),
        memory: AgentIOSDeviceMemoryStatusPresentation.output(
          snapshot: memoryProvider.snapshot(),
          nowMillis: now
        ),
        storage: provider.storageStatus(nowMillis: now),
        network: provider.networkStatus(nowMillis: now),
        nowMillis: now
      )
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: AgentIOSDeviceHealthStatusPresentation.message(
          output: output,
          language: responseLanguage(invocation)
        ),
        metadata: ["background_capture": .bool(false), "identifiers_included": .bool(false)]
      )
    case AgentIOSHardwareNativeToolCatalog.batteryStatus:
      return status(
        provider.batteryStatus(nowMillis: now),
        english: "Battery status read",
        chinese: "\u{5DF2}\u{8BFB}\u{53D6}\u{7535}\u{6C60}\u{72B6}\u{6001}",
        invocation: invocation
      )
    case AgentIOSHardwareNativeToolCatalog.powerStatus:
      return status(
        provider.powerStatus(nowMillis: now),
        english: "Power status read",
        chinese: "\u{5DF2}\u{8BFB}\u{53D6}\u{7535}\u{6E90}\u{72B6}\u{6001}",
        invocation: invocation
      )
    case AgentIOSHardwareNativeToolCatalog.memoryStatus:
      let output = AgentIOSDeviceMemoryStatusPresentation.output(
        snapshot: memoryProvider.snapshot(),
        nowMillis: now
      )
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: AgentIOSDeviceMemoryStatusPresentation.message(
          output: output,
          language: responseLanguage(invocation)
        ),
        metadata: ["background_capture": .bool(false), "process_enumeration": .bool(false)]
      )
    case AgentIOSHardwareNativeToolCatalog.storageStatus:
      return status(
        provider.storageStatus(nowMillis: now),
        english: "Storage status read",
        chinese: "\u{5DF2}\u{8BFB}\u{53D6}\u{5B58}\u{50A8}\u{72B6}\u{6001}",
        invocation: invocation
      )
    case AgentIOSHardwareNativeToolCatalog.networkStatus:
      return status(
        provider.networkStatus(nowMillis: now),
        english: "Network status read",
        chinese: "\u{5DF2}\u{8BFB}\u{53D6}\u{7F51}\u{7EDC}\u{72B6}\u{6001}",
        invocation: invocation
      )
    case AgentIOSHardwareNativeToolCatalog.locationForegroundRead:
      let timeout = invocation.input["timeout_ms"]?.intValue ?? AgentIOSHardwareNativeToolCatalog.maxLocationTimeoutMillis
      return localizedLocationResult(
        locationProvider.foregroundLocation(
          timeoutMillis: max(1_000, min(AgentIOSHardwareNativeToolCatalog.maxLocationTimeoutMillis, timeout)),
          nowMillis: now
        ),
        invocation: invocation
      )
    case AgentIOSHardwareNativeToolCatalog.sensorsList:
      let limit = Int(invocation.input["limit"]?.intValue ?? Int64(AgentIOSHardwareNativeToolCatalog.maxSensorResults))
      return status(
        provider.sensorsList(limit: limit, nowMillis: now),
        english: "Device sensor metadata listed",
        chinese: "\u{5DF2}\u{5217}\u{51FA}\u{8BBE}\u{5907}\u{4F20}\u{611F}\u{5668}\u{4FE1}\u{606F}",
        invocation: invocation
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
      return status(
        provider.bluetoothStatus(nowMillis: now),
        english: "Bluetooth adapter status boundary read",
        chinese: "\u{5DF2}\u{8BFB}\u{53D6}\u{84DD}\u{7259}\u{9002}\u{914D}\u{5668}\u{72B6}\u{6001}\u{8FB9}\u{754C}",
        invocation: invocation
      )
    case AgentIOSHardwareNativeToolCatalog.bluetoothDiscoveryForeground:
      let limit = Int(invocation.input["limit"]?.intValue ?? Int64(AgentIOSHardwareNativeToolCatalog.maxBluetoothResults))
      let timeout = invocation.input["timeout_ms"]?.intValue ?? AgentIOSHardwareNativeToolCatalog.maxBluetoothDiscoveryMillis
      return localizedBluetoothDiscoveryResult(
        bluetoothDiscoveryProvider.discoverBluetooth(
          timeoutMillis: max(
            AgentIOSHardwareNativeToolCatalog.minBluetoothDiscoveryMillis,
            min(AgentIOSHardwareNativeToolCatalog.maxBluetoothDiscoveryMillis, timeout)
          ),
          limit: max(1, min(AgentIOSHardwareNativeToolCatalog.maxBluetoothResults, limit)),
          nowMillis: now
        ),
        invocation: invocation
      )
    case AgentIOSHardwareNativeToolCatalog.nfcStatus:
      return status(
        provider.nfcStatus(nowMillis: now),
        english: "NFC capability status read",
        chinese: "\u{5DF2}\u{8BFB}\u{53D6} NFC \u{80FD}\u{529B}\u{72B6}\u{6001}",
        invocation: invocation
      )
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
        message: isChinese(invocation)
          ? "\u{5DF2}\u{51C6}\u{5907}\u{84DD}\u{7259}\u{8BBE}\u{7F6E}\u{4EA4}\u{63A5}\u{FF1B}iOS \u{9700}\u{8981}\u{7528}\u{6237}\u{624B}\u{52A8}\u{5B8C}\u{6210}\u{914D}\u{5BF9}\u{3002}"
          : "Bluetooth settings handoff prepared; iOS requires user-controlled pairing.",
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

  private func status(
    _ output: AgentMcpJSONObject,
    english: String,
    chinese: String,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: output,
      message: isChinese(invocation) ? chinese : english,
      metadata: ["background_capture": .bool(false), "identifiers_included": .bool(false)]
    )
  }

  private func responseLanguage(_ invocation: AgentNativeToolInvocation) -> String {
    LanguagePolicySettings.resolve(invocation.context.attributes["response_language"] ?? "")
  }

  private func isChinese(_ invocation: AgentNativeToolInvocation) -> Bool {
    responseLanguage(invocation).lowercased().hasPrefix("zh")
  }

  private func localizedLocationResult(
    _ result: AgentNativeToolExecutionResult,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    localizedNativeResult(
      result,
      invocation: invocation,
      success: "\u{5DF2}\u{8BFB}\u{53D6}\u{5355}\u{6B21}\u{524D}\u{53F0}\u{4F4D}\u{7F6E}\u{5B9A}\u{4F4D}\u{7ED3}\u{679C}\u{3002}",
      failures: [
        "location_services_disabled": "iOS \u{5B9A}\u{4F4D}\u{670D}\u{52A1}\u{5DF2}\u{5173}\u{95ED}\u{3002}",
        "location_background_executor_required": "\u{524D}\u{53F0}\u{5B9A}\u{4F4D}\u{9700}\u{8981}\u{5728}\u{4E0D}\u{963B}\u{585E}\u{4E3B}\u{8FD0}\u{884C}\u{5FAA}\u{73AF}\u{7684}\u{539F}\u{751F}\u{6267}\u{884C}\u{7EBF}\u{7A0B}\u{4E0A}\u{8FD0}\u{884C}\u{3002}",
        "location_timeout": "\u{7B49}\u{5F85}\u{5355}\u{6B21} iOS \u{524D}\u{53F0}\u{5B9A}\u{4F4D}\u{8D85}\u{65F6}\u{3002}",
        "location_unavailable": "iOS \u{672A}\u{8FD4}\u{56DE}\u{53EF}\u{7528}\u{7684}\u{524D}\u{53F0}\u{4F4D}\u{7F6E}\u{5B9A}\u{4F4D}\u{7ED3}\u{679C}\u{3002}",
        "location_framework_unavailable": "\u{5F53}\u{524D}\u{5E73}\u{53F0}\u{4E0D}\u{652F}\u{6301} CoreLocation\u{3002}",
        "location_permission_required": "\u{672A}\u{6388}\u{4E88} iOS \u{524D}\u{53F0}\u{5B9A}\u{4F4D}\u{6743}\u{9650}\u{3002}",
        "location_permission_not_determined": "\u{5C1A}\u{672A}\u{6388}\u{4E88} iOS \u{524D}\u{53F0}\u{5B9A}\u{4F4D}\u{6743}\u{9650}\u{3002}",
        "location_authorization_unknown": "iOS \u{8FD4}\u{56DE}\u{4E86}\u{672A}\u{77E5}\u{7684}\u{5B9A}\u{4F4D}\u{6388}\u{6743}\u{72B6}\u{6001}\u{3002}",
        "location_empty_result": "CoreLocation \u{672A}\u{8FD4}\u{56DE}\u{524D}\u{53F0}\u{4F4D}\u{7F6E}\u{5B9A}\u{4F4D}\u{7ED3}\u{679C}\u{3002}",
        "location_fix_failed": "CoreLocation \u{65E0}\u{6CD5}\u{83B7}\u{53D6}\u{524D}\u{53F0}\u{4F4D}\u{7F6E}\u{5B9A}\u{4F4D}\u{3002}"
      ]
    )
  }

  private func localizedBluetoothDiscoveryResult(
    _ result: AgentNativeToolExecutionResult,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    localizedNativeResult(
      result,
      invocation: invocation,
      success: "\u{524D}\u{53F0}\u{84DD}\u{7259}\u{8BBE}\u{5907}\u{626B}\u{63CF}\u{5DF2}\u{7ED3}\u{675F}\u{3002}",
      failures: [
        "bluetooth_background_executor_required": "\u{524D}\u{53F0} CoreBluetooth \u{626B}\u{63CF}\u{9700}\u{8981}\u{5728}\u{4E0D}\u{963B}\u{585E}\u{4E3B}\u{8FD0}\u{884C}\u{5FAA}\u{73AF}\u{7684}\u{539F}\u{751F}\u{6267}\u{884C}\u{7EBF}\u{7A0B}\u{4E0A}\u{8FD0}\u{884C}\u{3002}",
        "bluetooth_permission_denied": "\u{672A}\u{6388}\u{4E88} iOS \u{524D}\u{53F0}\u{84DD}\u{7259}\u{626B}\u{63CF}\u{6743}\u{9650}\u{3002}",
        "bluetooth_authorization_unknown": "iOS \u{8FD4}\u{56DE}\u{4E86}\u{672A}\u{77E5}\u{7684}\u{84DD}\u{7259}\u{6388}\u{6743}\u{72B6}\u{6001}\u{3002}",
        "bluetooth_discovery_timeout": "\u{7B49}\u{5F85} iOS CoreBluetooth \u{626B}\u{63CF}\u{5B8C}\u{6210}\u{8D85}\u{65F6}\u{3002}",
        "bluetooth_discovery_unavailable": "iOS CoreBluetooth \u{626B}\u{63CF}\u{672A}\u{8FD4}\u{56DE}\u{53D7}\u{9650}\u{7684}\u{7ED3}\u{679C}\u{3002}",
        "bluetooth_framework_unavailable": "\u{5F53}\u{524D}\u{5E73}\u{53F0}\u{4E0D}\u{652F}\u{6301} CoreBluetooth\u{3002}",
        "bluetooth_disabled": "\u{84DD}\u{7259}\u{5DF2}\u{5173}\u{95ED}\u{FF1B}GalaxySSI \u{4E0D}\u{4F1A}\u{66F4}\u{6539}\u{8BE5}\u{8BBE}\u{7F6E}\u{3002}",
        "bluetooth_unavailable": "\u{6B64} iOS \u{8BBE}\u{5907}\u{4E0D}\u{63D0}\u{4F9B} CoreBluetooth \u{626B}\u{63CF}\u{80FD}\u{529B}\u{3002}",
        "bluetooth_state_unknown": "iOS \u{8FD4}\u{56DE}\u{4E86}\u{672A}\u{77E5}\u{7684}\u{84DD}\u{7259}\u{7BA1}\u{7406}\u{5668}\u{72B6}\u{6001}\u{3002}",
        "bluetooth_discovery_not_ready": "\u{53D7}\u{9650}\u{7684}\u{626B}\u{63CF}\u{65F6}\u{95F4}\u{7A97}\u{7ED3}\u{675F}\u{524D}\u{FF0C}CoreBluetooth \u{5C1A}\u{672A}\u{5C31}\u{7EEA}\u{3002}"
      ]
    )
  }

  private func localizedNativeResult(
    _ result: AgentNativeToolExecutionResult,
    invocation: AgentNativeToolInvocation,
    success: String,
    failures: [String: String]
  ) -> AgentNativeToolExecutionResult {
    guard isChinese(invocation) else { return result }
    let message = result.isSuccess ? success : failures[result.error?.code ?? ""]
    guard let message else { return result }
    var localized = result
    localized.message = message
    if var error = localized.error {
      error.message = message
      localized.error = error
    }
    return localized
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
      message: isChinese(invocation)
        ? "iOS \u{5e94}\u{7528}\u{53ef}\u{89c1}\u{6027}\u{8fb9}\u{754c}\u{65e0}\u{6cd5}\u{8fd4}\u{56de}\u{5b8c}\u{6574}\u{7684}\u{5df2}\u{5b89}\u{88c5}\u{5e94}\u{7528}\u{5217}\u{8868}\u{3002}"
        : "iOS app visibility boundary returned no full installed-app inventory.",
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
        message: isChinese(invocation)
          ? "iOS \u{5e94}\u{7528}\u{53ef}\u{89c1}\u{6027}\u{8fb9}\u{754c}\u{67e5}\u{8be2}\u{9700}\u{8981}\u{5e94}\u{7528}\u{5305}\u{540d}\u{3002}"
          : "Package name is required for iOS app visibility boundary lookup."
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
      message: isChinese(invocation)
        ? "iOS \u{5e94}\u{7528}\u{53ef}\u{89c1}\u{6027}\u{8fb9}\u{754c}\u{4e0d}\u{80fd}\u{68c0}\u{67e5}\u{4efb}\u{610f}\u{5e94}\u{7528}\u{5305}\u{7684}\u{5143}\u{6570}\u{636e}\u{3002}"
        : "iOS app visibility boundary cannot inspect arbitrary package metadata.",
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
