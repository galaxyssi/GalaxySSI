import Foundation
#if canImport(CoreBluetooth) && os(iOS)
import CoreBluetooth
#endif

protocol AgentIOSBluetoothDiscoveryProviding {
  func discoverBluetooth(timeoutMillis: Int64, limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSCoreBluetoothDiscoveryProvider: AgentIOSBluetoothDiscoveryProviding {
  func discoverBluetooth(timeoutMillis: Int64, limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    #if canImport(CoreBluetooth) && os(iOS)
    guard !Thread.isMainThread else {
      return bluetoothDiscoveryFailure(
        code: "bluetooth_background_executor_required",
        message: "Foreground CoreBluetooth discovery requires a native executor thread that does not block the main run loop.",
        retryable: true,
        nowMillis: nowMillis
      )
    }
    switch CBCentralManager.authorization {
    case .allowedAlways, .notDetermined:
      break
    case .denied, .restricted:
      return bluetoothDiscoveryFailure(
        code: "bluetooth_permission_denied",
        message: "iOS Bluetooth permission is not granted for foreground discovery.",
        retryable: true,
        nowMillis: nowMillis,
        authorization: bluetoothAuthorization(CBCentralManager.authorization)
      )
    @unknown default:
      return bluetoothDiscoveryFailure(
        code: "bluetooth_authorization_unknown",
        message: "iOS returned an unknown Bluetooth authorization state.",
        retryable: true,
        nowMillis: nowMillis,
        authorization: "unknown"
      )
    }

    let boundedTimeout = max(
      AgentIOSHardwareNativeToolCatalog.minBluetoothDiscoveryMillis,
      min(AgentIOSHardwareNativeToolCatalog.maxBluetoothDiscoveryMillis, timeoutMillis)
    )
    let boundedLimit = max(1, min(AgentIOSHardwareNativeToolCatalog.maxBluetoothResults, limit))
    let session = AgentIOSCoreBluetoothDiscoverySession(
      timeoutMillis: boundedTimeout,
      limit: boundedLimit,
      nowMillis: nowMillis
    )
    session.start()
    if session.wait(timeoutMillis: boundedTimeout + 1_000) == false {
      session.cancel()
      return bluetoothDiscoveryFailure(
        code: "bluetooth_discovery_timeout",
        message: "Timed out while waiting for iOS CoreBluetooth discovery to finish.",
        retryable: true,
        nowMillis: nowMillis
      )
    }
    return session.result ?? bluetoothDiscoveryFailure(
      code: "bluetooth_discovery_unavailable",
      message: "iOS CoreBluetooth discovery did not return a bounded result.",
      retryable: true,
      nowMillis: nowMillis
    )
    #else
    return bluetoothDiscoveryFailure(
      code: "bluetooth_framework_unavailable",
      message: "CoreBluetooth is unavailable on this platform.",
      nowMillis: nowMillis,
      framework: "unavailable"
    )
    #endif
  }
}

#if canImport(CoreBluetooth) && os(iOS)
private final class AgentIOSCoreBluetoothDiscoverySession: NSObject, CBCentralManagerDelegate {
  private let timeoutMillis: Int64
  private let limit: Int
  private let nowMillis: Int64
  private let queue = DispatchQueue(label: "galaxyssi.ios.corebluetooth.discovery")
  private let semaphore = DispatchSemaphore(value: 0)
  private let lock = NSLock()

  private var central: CBCentralManager?
  private var completed = false
  private var scanStarted = false
  private var orderedIdentifiers: [String] = []
  private var devicesByIdentifier: [String: AgentMcpJSONObject] = [:]
  private var stateName = "unknown"

  private(set) var result: AgentNativeToolExecutionResult?

  init(timeoutMillis: Int64, limit: Int, nowMillis: Int64) {
    self.timeoutMillis = timeoutMillis
    self.limit = limit
    self.nowMillis = nowMillis
  }

  func start() {
    queue.async {
      self.central = CBCentralManager(
        delegate: self,
        queue: self.queue,
        options: [CBCentralManagerOptionShowPowerAlertKey: false]
      )
      self.queue.asyncAfter(deadline: .now() + .milliseconds(Int(self.timeoutMillis))) { [weak self] in
        self?.finishScanWindow()
      }
    }
  }

  func wait(timeoutMillis: Int64) -> Bool {
    semaphore.wait(timeout: .now() + .milliseconds(Int(timeoutMillis))) == .success
  }

  func cancel() {
    lock.lock()
    completed = true
    lock.unlock()
    stop()
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    stateName = bluetoothState(central.state)
    switch central.state {
    case .poweredOn:
      startScanning(central)
    case .poweredOff:
      finish(bluetoothDiscoveryFailure(
        code: "bluetooth_disabled",
        message: "Bluetooth is disabled; GalaxySSI will not change that setting.",
        retryable: true,
        nowMillis: nowMillis,
        state: stateName
      ))
    case .unauthorized:
      finish(bluetoothDiscoveryFailure(
        code: "bluetooth_permission_denied",
        message: "iOS denied foreground Bluetooth discovery.",
        retryable: true,
        nowMillis: nowMillis,
        authorization: bluetoothAuthorization(CBCentralManager.authorization),
        state: stateName
      ))
    case .unsupported:
      finish(bluetoothDiscoveryFailure(
        code: "bluetooth_unavailable",
        message: "This iOS device does not expose CoreBluetooth scanning.",
        nowMillis: nowMillis,
        state: stateName
      ))
    case .resetting, .unknown:
      break
    @unknown default:
      finish(bluetoothDiscoveryFailure(
        code: "bluetooth_state_unknown",
        message: "iOS returned an unknown Bluetooth manager state.",
        retryable: true,
        nowMillis: nowMillis,
        state: stateName
      ))
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    let identifier = peripheral.identifier.uuidString.uppercased()
    lock.lock()
    defer { lock.unlock() }
    guard completed == false else { return }
    if devicesByIdentifier[identifier] == nil {
      guard orderedIdentifiers.count < min(limit + 1, AgentIOSHardwareNativeToolCatalog.maxBluetoothResults + 1) else {
        return
      }
      orderedIdentifiers.append(identifier)
    }
    devicesByIdentifier[identifier] = [
      "address": .string(identifier),
      "name": boundedName(
        (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
      ),
      "bond_state": .string("unknown"),
      "device_type": .string("low_energy"),
      "identifier_scope": .string("ios_app_scoped_uuid")
    ]
  }

  private func startScanning(_ central: CBCentralManager) {
    lock.lock()
    let shouldStart = completed == false && scanStarted == false
    if shouldStart {
      scanStarted = true
    }
    lock.unlock()
    guard shouldStart else { return }
    central.scanForPeripherals(
      withServices: nil,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
  }

  private func finishScanWindow() {
    lock.lock()
    let ready = scanStarted
    lock.unlock()
    if ready {
      finish(success(completed: true, timedOut: false))
    } else {
      finish(bluetoothDiscoveryFailure(
        code: "bluetooth_discovery_not_ready",
        message: "CoreBluetooth did not become ready before the bounded discovery window ended.",
        retryable: true,
        nowMillis: nowMillis,
        authorization: bluetoothAuthorization(CBCentralManager.authorization),
        state: stateName
      ))
    }
  }

  private func success(completed: Bool, timedOut: Bool) -> AgentNativeToolExecutionResult {
    lock.lock()
    let ordered = orderedIdentifiers
    let devices = devicesByIdentifier
    lock.unlock()

    let selected = ordered
      .prefix(limit)
      .compactMap { devices[$0] }
    return AgentNativeToolExecutionResult.success(
      output: [
        "devices": .array(selected.map { .object($0) }),
        "result_count": .int(Int64(selected.count)),
        "completed": .bool(completed),
        "timed_out": .bool(timedOut),
        "truncated": .bool(ordered.count > limit),
        "observed_at_epoch_ms": .int(max(0, nowMillis)),
        "capture_mode": .string("single_foreground_discovery"),
        "background_capture": .bool(false)
      ],
      message: "Foreground Bluetooth discovery ended",
      metadata: [
        "receiver_unregistered": .bool(true),
        "discovery_cancelled_after_call": .bool(true),
        "scan_stopped_after_call": .bool(true),
        "hardware_addresses_included": .bool(false),
        "identifier_scope": .string("ios_app_scoped_uuid"),
        "framework": .string("core_bluetooth")
      ]
    )
  }

  private func finish(_ result: AgentNativeToolExecutionResult) {
    lock.lock()
    guard completed == false else {
      lock.unlock()
      return
    }
    completed = true
    self.result = result
    lock.unlock()
    stop()
    semaphore.signal()
  }

  private func stop() {
    central?.stopScan()
    central?.delegate = nil
    central = nil
  }

  private func boundedName(_ value: String?) -> AgentMcpJSONValue {
    let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .null }
    return .string(String(trimmed.prefix(Int(AgentIOSHardwareNativeToolCatalog.maxBluetoothNameChars))))
  }
}

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

private func bluetoothState(_ state: CBManagerState) -> String {
  switch state {
  case .poweredOn:
    return "powered_on"
  case .poweredOff:
    return "powered_off"
  case .resetting:
    return "resetting"
  case .unauthorized:
    return "unauthorized"
  case .unsupported:
    return "unsupported"
  case .unknown:
    return "unknown"
  @unknown default:
    return "unknown"
  }
}
#endif

private func bluetoothDiscoveryFailure(
  code: String,
  message: String,
  retryable: Bool = false,
  nowMillis: Int64,
  framework: String = "core_bluetooth",
  authorization: String = "unknown",
  state: String = "unknown"
) -> AgentNativeToolExecutionResult {
  AgentNativeToolExecutionResult.failure(
    code: code,
    message: message,
    retryable: retryable,
    details: [
      "authorization": .string(authorization),
      "state": .string(state),
      "capture_mode": .string("single_foreground_discovery"),
      "background_capture": .bool(false),
      "receiver_unregistered": .bool(true),
      "discovery_cancelled_after_call": .bool(true),
      "scan_stopped_after_call": .bool(true),
      "framework": .string(framework),
      "observed_at_epoch_ms": .int(max(0, nowMillis))
    ]
  )
}
