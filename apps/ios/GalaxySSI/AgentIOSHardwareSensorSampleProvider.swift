import Foundation
#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif

protocol AgentIOSSensorSampleProviding {
  func sampleSensor(type: String, timeoutMillis: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSCoreMotionSensorSampleProvider: AgentIOSSensorSampleProviding {
  func sampleSensor(type: String, timeoutMillis: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let kind = AgentIOSCoreMotionSensorKind(normalizedType) else {
      return sensorFailure(
        code: "invalid_sensor_type",
        message: "Requested sensor type is outside the iOS CoreMotion foreground sample allowlist.",
        type: normalizedType,
        nowMillis: nowMillis,
        extraDetails: [
          "allowed_types": .array(AgentIOSHardwareNativeToolCatalog.sensorSampleTypes.map(AgentMcpJSONValue.string))
        ]
      )
    }

    #if canImport(CoreMotion) && os(iOS)
    guard !Thread.isMainThread else {
      return sensorFailure(
        code: "sensor_background_executor_required",
        message: "Foreground CoreMotion sampling requires a native executor thread that does not block the main run loop.",
        type: kind.id,
        retryable: true,
        nowMillis: nowMillis
      )
    }
    let timeout = max(
      AgentIOSHardwareNativeToolCatalog.minSensorTimeoutMillis,
      min(AgentIOSHardwareNativeToolCatalog.maxSensorTimeoutMillis, timeoutMillis)
    )
    let capture = AgentIOSCoreMotionSensorSampleCapture(
      manager: CMMotionManager(),
      kind: kind,
      nowMillis: nowMillis
    )
    capture.start()
    if capture.wait(timeoutMillis: timeout) == false {
      capture.cancel()
      return sensorFailure(
        code: "sensor_sample_timeout",
        message: "Timed out waiting for one foreground iOS CoreMotion sample.",
        type: kind.id,
        retryable: true,
        nowMillis: nowMillis
      )
    }
    return capture.result ?? sensorFailure(
      code: "sensor_sample_unavailable",
      message: "iOS CoreMotion did not return a foreground sensor sample.",
      type: kind.id,
      retryable: true,
      nowMillis: nowMillis
    )
    #else
    return sensorFailure(
      code: "sensor_framework_unavailable",
      message: "CoreMotion is unavailable on this platform.",
      type: kind.id,
      nowMillis: nowMillis,
      framework: "unavailable"
    )
    #endif
  }
}

private struct AgentIOSCoreMotionSensorKind {
  var id: String
  var androidType: Int64

  init?(_ id: String) {
    switch id {
    case "accelerometer":
      self.id = id
      androidType = 1
    case "game_rotation_vector":
      self.id = id
      androidType = 15
    case "gravity":
      self.id = id
      androidType = 9
    case "gyroscope":
      self.id = id
      androidType = 4
    case "linear_acceleration":
      self.id = id
      androidType = 10
    case "magnetic_field":
      self.id = id
      androidType = 2
    case "rotation_vector":
      self.id = id
      androidType = 11
    default:
      return nil
    }
  }
}

#if canImport(CoreMotion) && os(iOS)
private final class AgentIOSCoreMotionSensorSampleCapture {
  private let manager: CMMotionManager
  private let kind: AgentIOSCoreMotionSensorKind
  private let nowMillis: Int64
  private let semaphore = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private let queue = OperationQueue()
  private var completed = false

  private(set) var result: AgentNativeToolExecutionResult?

  init(manager: CMMotionManager, kind: AgentIOSCoreMotionSensorKind, nowMillis: Int64) {
    self.manager = manager
    self.kind = kind
    self.nowMillis = nowMillis
    queue.maxConcurrentOperationCount = 1
    queue.name = "galaxyssi.ios.coremotion.sensor_sample"
  }

  func start() {
    switch kind.id {
    case "accelerometer":
      startAccelerometer()
    case "gyroscope":
      startGyroscope()
    case "magnetic_field":
      startMagnetometer()
    default:
      startDeviceMotion()
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

  private func startAccelerometer() {
    guard manager.isAccelerometerAvailable else {
      finish(unavailable())
      return
    }
    manager.accelerometerUpdateInterval = updateInterval
    manager.startAccelerometerUpdates(to: queue) { [weak self] data, error in
      guard let self = self else { return }
      if let error = error {
        self.finish(self.frameworkFailure(error))
        return
      }
      guard let acceleration = data?.acceleration else { return }
      self.finish(self.success(values: [
        acceleration.x * Self.standardGravity,
        acceleration.y * Self.standardGravity,
        acceleration.z * Self.standardGravity
      ]))
    }
  }

  private func startGyroscope() {
    guard manager.isGyroAvailable else {
      finish(unavailable())
      return
    }
    manager.gyroUpdateInterval = updateInterval
    manager.startGyroUpdates(to: queue) { [weak self] data, error in
      guard let self = self else { return }
      if let error = error {
        self.finish(self.frameworkFailure(error))
        return
      }
      guard let rotationRate = data?.rotationRate else { return }
      self.finish(self.success(values: [
        rotationRate.x,
        rotationRate.y,
        rotationRate.z
      ]))
    }
  }

  private func startMagnetometer() {
    guard manager.isMagnetometerAvailable else {
      finish(unavailable())
      return
    }
    manager.magnetometerUpdateInterval = updateInterval
    manager.startMagnetometerUpdates(to: queue) { [weak self] data, error in
      guard let self = self else { return }
      if let error = error {
        self.finish(self.frameworkFailure(error))
        return
      }
      guard let magneticField = data?.magneticField else { return }
      self.finish(self.success(values: [
        magneticField.x,
        magneticField.y,
        magneticField.z
      ]))
    }
  }

  private func startDeviceMotion() {
    guard manager.isDeviceMotionAvailable else {
      finish(unavailable())
      return
    }
    manager.deviceMotionUpdateInterval = updateInterval
    manager.startDeviceMotionUpdates(to: queue) { [weak self] data, error in
      guard let self = self else { return }
      if let error = error {
        self.finish(self.frameworkFailure(error))
        return
      }
      guard let motion = data else { return }
      self.finish(self.success(values: self.deviceMotionValues(motion)))
    }
  }

  private func deviceMotionValues(_ motion: CMDeviceMotion) -> [Double] {
    switch kind.id {
    case "gravity":
      return [
        motion.gravity.x * Self.standardGravity,
        motion.gravity.y * Self.standardGravity,
        motion.gravity.z * Self.standardGravity
      ]
    case "linear_acceleration":
      return [
        motion.userAcceleration.x * Self.standardGravity,
        motion.userAcceleration.y * Self.standardGravity,
        motion.userAcceleration.z * Self.standardGravity
      ]
    case "game_rotation_vector", "rotation_vector":
      let quaternion = motion.attitude.quaternion
      return [
        quaternion.x,
        quaternion.y,
        quaternion.z,
        quaternion.w
      ]
    default:
      return []
    }
  }

  private func success(values: [Double]) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: [
        "type": .string(kind.id),
        "android_type": .int(kind.androidType),
        "values": .array(jsonValues(values)),
        "accuracy": .int(3),
        "observed_at_epoch_ms": .int(max(0, nowMillis)),
        "capture_mode": .string("single_foreground_sample"),
        "background_capture": .bool(false)
      ],
      message: "Single foreground sensor sample read",
      metadata: [
        "retained_listener": .bool(false),
        "framework": .string("core_motion")
      ]
    )
  }

  private func unavailable() -> AgentNativeToolExecutionResult {
    sensorFailure(
      code: "sensor_unavailable",
      message: "Requested CoreMotion sensor is unavailable on this iOS device.",
      type: kind.id,
      retryable: true,
      nowMillis: nowMillis
    )
  }

  private func frameworkFailure(_ error: Error) -> AgentNativeToolExecutionResult {
    sensorFailure(
      code: "sensor_sample_failed",
      message: "CoreMotion failed to return a foreground sensor sample.",
      type: kind.id,
      retryable: true,
      nowMillis: nowMillis,
      extraDetails: [
        "error_description": .string(String(error.localizedDescription.prefix(240)))
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
    manager.stopAccelerometerUpdates()
    manager.stopGyroUpdates()
    manager.stopMagnetometerUpdates()
    manager.stopDeviceMotionUpdates()
    queue.cancelAllOperations()
  }

  private var updateInterval: TimeInterval {
    0.05
  }

  private func jsonValues(_ values: [Double]) -> [AgentMcpJSONValue] {
    values
      .prefix(AgentIOSHardwareNativeToolCatalog.maxSensorValues)
      .map { .double($0.isFinite ? $0 : 0) }
  }

  private static let standardGravity = 9.80665
}
#endif

private func sensorFailure(
  code: String,
  message: String,
  type: String,
  retryable: Bool = false,
  nowMillis: Int64,
  framework: String = "core_motion",
  extraDetails: AgentMcpJSONObject = [:]
) -> AgentNativeToolExecutionResult {
  var details: AgentMcpJSONObject = [
    "type": .string(type),
    "capture_mode": .string("single_foreground_sample"),
    "background_capture": .bool(false),
    "retained_listener": .bool(false),
    "framework": .string(framework),
    "observed_at_epoch_ms": .int(max(0, nowMillis))
  ]
  for (key, value) in extraDetails {
    details[key] = value
  }
  return AgentNativeToolExecutionResult.failure(
    code: code,
    message: message,
    retryable: retryable,
    details: details
  )
}
