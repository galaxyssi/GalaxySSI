import Foundation
#if canImport(CoreLocation) && os(iOS)
import CoreLocation
#endif

protocol AgentIOSForegroundLocationProviding {
  func foregroundLocation(timeoutMillis: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSDefaultForegroundLocationProvider: AgentIOSForegroundLocationProviding {
  func foregroundLocation(timeoutMillis: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    #if canImport(CoreLocation) && os(iOS)
    guard CLLocationManager.locationServicesEnabled() else {
      return locationFailure(
        code: "location_services_disabled",
        message: "iOS Location Services are disabled.",
        retryable: true,
        authorization: "services_disabled",
        nowMillis: nowMillis
      )
    }
    let timeout = max(1_000, min(AgentIOSHardwareNativeToolCatalog.maxLocationTimeoutMillis, timeoutMillis))
    guard !Thread.isMainThread else {
      return locationFailure(
        code: "location_background_executor_required",
        message: "Foreground location requires a native executor thread that does not block the main run loop.",
        retryable: true,
        authorization: "unknown",
        nowMillis: nowMillis
      )
    }
    let capture = AgentIOSForegroundLocationCapture(nowMillis: nowMillis)
    DispatchQueue.main.async {
      capture.start()
    }
    if capture.wait(timeoutMillis: timeout) == false {
      DispatchQueue.main.async {
        capture.stop()
      }
      return locationFailure(
        code: "location_timeout",
        message: "Timed out waiting for one foreground iOS location fix.",
        retryable: true,
        authorization: capture.authorization,
        nowMillis: nowMillis
      )
    }
    return capture.result ?? locationFailure(
      code: "location_unavailable",
      message: "iOS did not return a foreground location fix.",
      retryable: true,
      authorization: capture.authorization,
      nowMillis: nowMillis
    )
    #else
    return locationFailure(
      code: "location_framework_unavailable",
      message: "CoreLocation is unavailable on this platform.",
      authorization: "unavailable",
      nowMillis: nowMillis
    )
    #endif
  }

  private func locationFailure(
    code: String,
    message: String,
    retryable: Bool = false,
    authorization: String,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: code,
      message: message,
      retryable: retryable,
      details: [
        "authorization": .string(authorization),
        "capture_mode": .string("single_foreground_fix"),
        "background_capture": .bool(false),
        "retained_listener": .bool(false),
        "observed_at_epoch_ms": .int(nowMillis)
      ]
    )
  }
}

#if canImport(CoreLocation) && os(iOS)
private final class AgentIOSForegroundLocationCapture: NSObject, CLLocationManagerDelegate {
  private let semaphore = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private let nowMillis: Int64
  private var manager: CLLocationManager?
  private(set) var authorization: String = "unknown"
  private(set) var result: AgentNativeToolExecutionResult?

  init(nowMillis: Int64) {
    self.nowMillis = nowMillis
  }

  func start() {
    let manager = CLLocationManager()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = kCLDistanceFilterNone
    self.manager = manager
    authorization = authorizationName(manager.authorizationStatus)
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finish(AgentNativeToolExecutionResult.failure(
        code: "location_permission_required",
        message: "iOS foreground location permission is not granted.",
        retryable: true,
        details: failureDetails(authorization: authorization)
      ))
    case .notDetermined:
      finish(AgentNativeToolExecutionResult.failure(
        code: "location_permission_not_determined",
        message: "iOS foreground location permission has not been granted yet.",
        retryable: true,
        details: failureDetails(authorization: authorization)
      ))
    @unknown default:
      finish(AgentNativeToolExecutionResult.failure(
        code: "location_authorization_unknown",
        message: "iOS returned an unknown location authorization state.",
        retryable: true,
        details: failureDetails(authorization: authorization)
      ))
    }
  }

  func stop() {
    manager?.stopUpdatingLocation()
    manager?.delegate = nil
    manager = nil
  }

  func wait(timeoutMillis: Int64) -> Bool {
    semaphore.wait(timeout: .now() + .milliseconds(Int(timeoutMillis))) == .success
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      finish(AgentNativeToolExecutionResult.failure(
        code: "location_empty_result",
        message: "CoreLocation returned no foreground location fix.",
        retryable: true,
        details: failureDetails(authorization: authorization)
      ))
      return
    }
    finish(success(location))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let retryable = (error as? CLError)?.code == .locationUnknown
    finish(AgentNativeToolExecutionResult.failure(
      code: "location_fix_failed",
      message: "CoreLocation failed to return a foreground fix.",
      retryable: retryable,
      details: failureDetails(
        authorization: authorization,
        errorDescription: String(error.localizedDescription.prefix(240))
      )
    ))
  }

  private func success(_ location: CLLocation) -> AgentNativeToolExecutionResult {
    let observedAt = max(0, nowMillis)
    let fixAt = max(0, Int64((location.timestamp.timeIntervalSince1970 * 1_000).rounded()))
    let bearing = location.course >= 0 ? normalizedBearing(location.course) : nil
    let speed = location.speed >= 0 ? max(0, location.speed) : nil
    let altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
    return AgentNativeToolExecutionResult.success(
      output: [
        "latitude": .double(max(-90.0, min(90.0, location.coordinate.latitude))),
        "longitude": .double(max(-180.0, min(180.0, location.coordinate.longitude))),
        "accuracy_meters": .double(max(0, location.horizontalAccuracy)),
        "altitude_meters": altitude.map(AgentMcpJSONValue.double) ?? .null,
        "bearing_degrees": bearing.map(AgentMcpJSONValue.double) ?? .null,
        "speed_meters_per_second": speed.map(AgentMcpJSONValue.double) ?? .null,
        "provider": .string("core_location"),
        "fix_at_epoch_ms": .int(fixAt),
        "observed_at_epoch_ms": .int(observedAt),
        "age_ms": .int(max(0, observedAt - fixAt)),
        "source": .string("core_location"),
        "capture_mode": .string("single_foreground_fix"),
        "background_capture": .bool(false)
      ],
      message: "Single foreground location fix read",
      metadata: [
        "retained_listener": .bool(false),
        "authorization": .string(authorization),
        "desired_accuracy": .string("best")
      ]
    )
  }

  private func finish(_ result: AgentNativeToolExecutionResult) {
    lock.lock()
    defer { lock.unlock() }
    guard self.result == nil else { return }
    self.result = result
    stop()
    semaphore.signal()
  }

  private func failureDetails(
    authorization: String,
    errorDescription: String = ""
  ) -> AgentMcpJSONObject {
    var details: AgentMcpJSONObject = [
      "authorization": .string(authorization),
      "capture_mode": .string("single_foreground_fix"),
      "background_capture": .bool(false),
      "retained_listener": .bool(false),
      "observed_at_epoch_ms": .int(max(0, nowMillis))
    ]
    if !errorDescription.isEmpty {
      details["error_description"] = .string(errorDescription)
    }
    return details
  }

  private func authorizationName(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways:
      return "authorized_always"
    case .authorizedWhenInUse:
      return "authorized_when_in_use"
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

  private func normalizedBearing(_ value: CLLocationDirection) -> Double {
    let mod = value.truncatingRemainder(dividingBy: 360)
    return mod >= 0 ? mod : mod + 360
  }
}
#endif
