import Foundation

#if canImport(Darwin)
import Darwin
#endif

#if canImport(Metal)
import Metal
#endif

enum LocalModelAcceleratorKind: String, Codable, CaseIterable, Identifiable {
  case cpu = "CPU"
  case gpu = "GPU"
  case coreMLNeuralEngine = "CORE_ML_NEURAL_ENGINE"
  case vendorSDK = "VENDOR_SDK"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> LocalModelAcceleratorKind? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return allCases.first { $0.rawValue == normalized }
  }
}

enum LocalModelAcceleratorState: String, Codable, CaseIterable, Identifiable {
  case ready = "READY"
  case hardwareOnly = "HARDWARE_ONLY"
  case unavailable = "UNAVAILABLE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> LocalModelAcceleratorState {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return allCases.first { $0.rawValue == normalized } ?? .unavailable
  }
}

struct LocalModelAcceleratorCapability: Codable, Equatable, Identifiable {
  var kind: LocalModelAcceleratorKind
  var state: LocalModelAcceleratorState
  var provider: String
  var hardwareEvidence: String
  var runtimeEvidence: String

  var id: String { kind.rawValue }
  var ready: Bool { state == .ready }

  init(
    kind: LocalModelAcceleratorKind,
    state: LocalModelAcceleratorState,
    provider: String,
    hardwareEvidence: String,
    runtimeEvidence: String
  ) {
    self.kind = kind
    self.state = state
    self.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
    self.hardwareEvidence = hardwareEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
    self.runtimeEvidence = runtimeEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func unavailable(
    _ kind: LocalModelAcceleratorKind,
    provider: String? = nil
  ) -> LocalModelAcceleratorCapability {
    LocalModelAcceleratorCapability(
      kind: kind,
      state: .unavailable,
      provider: provider ?? defaultProvider(kind),
      hardwareEvidence: "No hardware signal was reported",
      runtimeEvidence: "No compatible local model runtime was detected"
    )
  }

  private static func defaultProvider(_ kind: LocalModelAcceleratorKind) -> String {
    switch kind {
    case .cpu:
      return "CPU"
    case .gpu:
      return "Metal"
    case .coreMLNeuralEngine:
      return "Core ML Neural Engine"
    case .vendorSDK:
      return "Vendor accelerator"
    }
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case state
    case provider
    case hardwareEvidence = "hardware_evidence"
    case runtimeEvidence = "runtime_evidence"
  }
}

struct LocalModelAcceleratorSnapshot: Codable, Equatable {
  var capabilities: [LocalModelAcceleratorCapability]
  var checkedAtMillis: Int64

  init(
    capabilities: [LocalModelAcceleratorCapability],
    checkedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    var byKind: [LocalModelAcceleratorKind: LocalModelAcceleratorCapability] = [:]
    for capability in capabilities {
      byKind[capability.kind] = capability
    }
    self.capabilities = LocalModelAcceleratorKind.allCases.map {
      byKind[$0] ?? LocalModelAcceleratorCapability.unavailable($0)
    }
    self.checkedAtMillis = max(0, checkedAtMillis)
  }

  subscript(kind: LocalModelAcceleratorKind) -> LocalModelAcceleratorCapability {
    capabilities.first { $0.kind == kind } ?? LocalModelAcceleratorCapability.unavailable(kind)
  }

  var readyKinds: [LocalModelAcceleratorKind] {
    capabilities.filter { $0.ready }.map { $0.kind }
  }

  enum CodingKeys: String, CodingKey {
    case capabilities
    case checkedAtMillis = "checked_at_millis"
  }
}

struct LocalModelAcceleratorProbe: Codable, Equatable {
  var cpuHardwareAvailable: Bool
  var cpuDescription: String
  var cpuRuntimeAvailable: Bool
  var cpuRuntimeDescription: String
  var gpuHardwareAvailable: Bool
  var gpuDescription: String
  var gpuRuntimeAvailable: Bool
  var gpuRuntimeDescription: String
  var neuralEngineHardwareAvailable: Bool
  var neuralEngineRuntimeAvailable: Bool
  var neuralEngineDescription: String
  var vendorFamily: String
  var vendorHardwareEvidence: String
  var vendorSdkAvailable: Bool
  var vendorRuntimeEvidence: String

  enum CodingKeys: String, CodingKey {
    case cpuHardwareAvailable = "cpu_hardware_available"
    case cpuDescription = "cpu_description"
    case cpuRuntimeAvailable = "cpu_runtime_available"
    case cpuRuntimeDescription = "cpu_runtime_description"
    case gpuHardwareAvailable = "gpu_hardware_available"
    case gpuDescription = "gpu_description"
    case gpuRuntimeAvailable = "gpu_runtime_available"
    case gpuRuntimeDescription = "gpu_runtime_description"
    case neuralEngineHardwareAvailable = "neural_engine_hardware_available"
    case neuralEngineRuntimeAvailable = "neural_engine_runtime_available"
    case neuralEngineDescription = "neural_engine_description"
    case vendorFamily = "vendor_family"
    case vendorHardwareEvidence = "vendor_hardware_evidence"
    case vendorSdkAvailable = "vendor_sdk_available"
    case vendorRuntimeEvidence = "vendor_runtime_evidence"
  }
}

enum LocalModelAcceleratorPolicy {
  static func evaluate(
    _ probe: LocalModelAcceleratorProbe,
    checkedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> LocalModelAcceleratorSnapshot {
    LocalModelAcceleratorSnapshot(
      capabilities: [
        capability(
          kind: .cpu,
          hardware: probe.cpuHardwareAvailable,
          runtime: probe.cpuRuntimeAvailable,
          provider: "CPU",
          hardwareEvidence: probe.cpuDescription,
          runtimeEvidence: probe.cpuRuntimeDescription
        ),
        capability(
          kind: .gpu,
          hardware: probe.gpuHardwareAvailable,
          runtime: probe.gpuRuntimeAvailable,
          provider: "Metal / Metal Performance Shaders",
          hardwareEvidence: probe.gpuDescription,
          runtimeEvidence: probe.gpuRuntimeDescription
        ),
        capability(
          kind: .coreMLNeuralEngine,
          hardware: probe.neuralEngineHardwareAvailable,
          runtime: probe.neuralEngineRuntimeAvailable,
          provider: "Core ML Neural Engine",
          hardwareEvidence: probe.neuralEngineDescription,
          runtimeEvidence: ifReady(
            probe.neuralEngineRuntimeAvailable,
            ready: "The local inference runtime exposes a Core ML execution path",
            missing: "The bundled inference runtime does not expose a Core ML execution path"
          )
        ),
        capability(
          kind: .vendorSDK,
          hardware: !probe.vendorFamily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          runtime: probe.vendorSdkAvailable,
          provider: probe.vendorFamily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
            "Vendor accelerator" : probe.vendorFamily,
          hardwareEvidence: probe.vendorHardwareEvidence,
          runtimeEvidence: probe.vendorRuntimeEvidence
        ),
      ],
      checkedAtMillis: checkedAtMillis
    )
  }

  private static func capability(
    kind: LocalModelAcceleratorKind,
    hardware: Bool,
    runtime: Bool,
    provider: String,
    hardwareEvidence: String,
    runtimeEvidence: String
  ) -> LocalModelAcceleratorCapability {
    LocalModelAcceleratorCapability(
      kind: kind,
      state: {
        if hardware && runtime { return .ready }
        if hardware { return .hardwareOnly }
        return .unavailable
      }(),
      provider: provider,
      hardwareEvidence: hardwareEvidence,
      runtimeEvidence: runtimeEvidence
    )
  }

  private static func ifReady(_ ready: Bool, ready readyText: String, missing missingText: String) -> String {
    ready ? readyText : missingText
  }
}

enum LocalModelAcceleratorDetector {
  static func detect(
    bundle: Bundle = .main,
    fileManager: FileManager = .default,
    processInfo: ProcessInfo = .processInfo,
    checkedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> LocalModelAcceleratorSnapshot {
    let metal = metalHardware()
    var runtimeNames = bundledRuntimeNames(bundle: bundle, fileManager: fileManager)
    if LocalModelInferenceRuntime.shared.available {
      runtimeNames.insert("galaxyssi-llama")
      runtimeNames.insert("ggml")
      if metal.available {
        runtimeNames.insert("ggml-metal")
      }
    }
    let machine = machineIdentifier()
    let neural = neuralEngineHardware(machineIdentifier: machine)
    return LocalModelAcceleratorPolicy.evaluate(
      probe(
        runtimeLibraryNames: runtimeNames,
        cpuCoreCount: processInfo.processorCount,
        machineIdentifier: machine,
        metalHardwareAvailable: metal.available,
        metalDescription: metal.evidence,
        neuralEngineHardwareAvailable: neural.available,
        neuralEngineDescription: neural.evidence
      ),
      checkedAtMillis: checkedAtMillis
    )
  }

  static func probe(
    runtimeLibraryNames: Set<String>,
    cpuCoreCount: Int,
    machineIdentifier: String,
    metalHardwareAvailable: Bool,
    metalDescription: String,
    neuralEngineHardwareAvailable: Bool,
    neuralEngineDescription: String
  ) -> LocalModelAcceleratorProbe {
    let normalizedRuntimeNames = Set(runtimeLibraryNames.map { $0.lowercased() })
    let cpuRuntime = containsAny(normalizedRuntimeNames, cpuRuntimeSignals)
    let metalRuntime = containsAny(normalizedRuntimeNames, metalRuntimeSignals)
    let neuralRuntime = containsAny(normalizedRuntimeNames, neuralEngineRuntimeSignals)
    let vendor = vendorHardware(machineIdentifier: machineIdentifier)
    let vendorRuntimeLibraries = normalizedRuntimeNames.filter { library in
      vendorRuntimeSignals.contains { library.contains($0) }
    }.sorted()
    return LocalModelAcceleratorProbe(
      cpuHardwareAvailable: cpuCoreCount > 0,
      cpuDescription: "\(max(1, cpuCoreCount)) cores / \(machineIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown Apple platform" : machineIdentifier)",
      cpuRuntimeAvailable: cpuRuntime,
      cpuRuntimeDescription: cpuRuntime ?
        "Bundled GGML, ONNX Runtime, MLX, or Core ML CPU path detected" :
        "No bundled CPU inference backend detected",
      gpuHardwareAvailable: metalHardwareAvailable,
      gpuDescription: metalDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
        "No Metal compute signal" : metalDescription,
      gpuRuntimeAvailable: metalRuntime,
      gpuRuntimeDescription: metalRuntime ?
        "A bundled Metal or MPS inference backend was detected" :
        "Metal delegate or MLX runtime is not bundled in this build",
      neuralEngineHardwareAvailable: neuralEngineHardwareAvailable,
      neuralEngineRuntimeAvailable: neuralRuntime,
      neuralEngineDescription: neuralEngineDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
        "Apple Neural Engine hardware is not publicly enumerable" : neuralEngineDescription,
      vendorFamily: vendor.family,
      vendorHardwareEvidence: vendor.evidence,
      vendorSdkAvailable: !vendorRuntimeLibraries.isEmpty,
      vendorRuntimeEvidence: vendorRuntimeEvidence(
        family: vendor.family,
        bundledRuntimeLibraries: vendorRuntimeLibraries
      )
    )
  }

  static func bundledRuntimeNames(
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) -> Set<String> {
    var names = Set<String>()
    let roots = [
      bundle.executableURL,
      bundle.privateFrameworksURL,
      bundle.builtInPlugInsURL,
      bundle.resourceURL,
    ].compactMap { $0 }
    for root in roots {
      collectNames(root, fileManager: fileManager, into: &names)
    }
    return names
  }

  private static func collectNames(_ url: URL, fileManager: FileManager, into names: inout Set<String>) {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
    names.insert(url.lastPathComponent.lowercased())
    guard isDirectory.boolValue else { return }
    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
    guard let enumerator = fileManager.enumerator(
      at: url,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return
    }
    for case let entry as URL in enumerator {
      names.insert(entry.lastPathComponent.lowercased())
      if names.count >= maximumRuntimeNameCount {
        break
      }
    }
  }

  private static func metalHardware() -> (available: Bool, evidence: String) {
    #if canImport(Metal)
    guard let device = MTLCreateSystemDefaultDevice() else {
      return (false, "No Metal device is available")
    }
    return (true, "Metal device: \(device.name)")
    #else
    return (false, "Metal framework is not available")
    #endif
  }

  private static func neuralEngineHardware(machineIdentifier: String) -> (available: Bool, evidence: String) {
    #if targetEnvironment(simulator)
    return (false, "iOS Simulator does not expose Apple Neural Engine")
    #else
    let machine = machineIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !machine.isEmpty else {
      return (false, "Apple Neural Engine hardware is not publicly enumerable")
    }
    return (
      true,
      "\(machine) can use Core ML Neural Engine scheduling when the SoC includes ANE"
    )
    #endif
  }

  private static func machineIdentifier() -> String {
    #if canImport(Darwin)
    var systemInfo = utsname()
    uname(&systemInfo)
    let mirror = Mirror(reflecting: systemInfo.machine)
    return mirror.children.reduce(into: "") { identifier, element in
      guard let value = element.value as? Int8, value != 0 else { return }
      identifier.append(String(UnicodeScalar(UInt8(bitPattern: value))))
    }
    #else
    return "unknown"
    #endif
  }

  private static func vendorHardware(machineIdentifier: String) -> (family: String, evidence: String) {
    let machine = machineIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = machine.lowercased()
    let family: String
    if normalized.hasPrefix("iphone") || normalized.hasPrefix("ipad") ||
        normalized.hasPrefix("ipod") || normalized.hasPrefix("appletv") ||
        normalized.contains("arm64") {
      family = "Apple Silicon"
    } else {
      family = ""
    }
    return (
      family,
      machine.isEmpty ? "Unknown Apple platform" : machine
    )
  }

  private static func vendorRuntimeEvidence(
    family: String,
    bundledRuntimeLibraries: [String]
  ) -> String {
    if !bundledRuntimeLibraries.isEmpty {
      return "Bundled runtime: \(bundledRuntimeLibraries.joined(separator: ", "))"
    }
    if !family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Compatible Apple SoC family detected, but no app SDK adapter is bundled"
    }
    return "No supported vendor accelerator family was identified"
  }

  private static func containsAny(_ values: Set<String>, _ needles: Set<String>) -> Bool {
    values.contains { value in
      needles.contains { value.contains($0) }
    }
  }

  private static let cpuRuntimeSignals: Set<String> = [
    "ggml",
    "llama",
    "whisper",
    "onnxruntime",
    "mlx",
    "coreml",
  ]
  private static let metalRuntimeSignals: Set<String> = [
    "ggml-metal",
    "metal",
    "mps",
    "mlx",
  ]
  private static let neuralEngineRuntimeSignals: Set<String> = [
    "coreml",
    "core-ml",
    "ane",
    "onnxruntime-coreml",
  ]
  private static let vendorRuntimeSignals: Set<String> = [
    "accelerate",
    "bnns",
    "ane",
    "apple-neural-engine",
    "coreml",
  ]
  private static let maximumRuntimeNameCount = 2_000
}
