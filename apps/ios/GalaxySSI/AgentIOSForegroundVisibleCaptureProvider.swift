import Foundation

#if os(iOS) && canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import UIKit
#endif

struct AgentIOSForegroundVisibleCaptureProvider: AgentIOSVisibleCaptureToolProviding {
  var implementationId: String = "galaxyssi.ios.visible_capture.uikit_avfoundation"
  var artifactStore: AgentIOSVisibleCaptureArtifactStore
  var nowMillis: () -> Int64

  init(
    artifactStore: AgentIOSVisibleCaptureArtifactStore = AgentIOSVisibleCaptureArtifactStore(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.artifactStore = artifactStore
    self.nowMillis = nowMillis
  }

  func availability(kind: AgentIOSVisibleCaptureKind) -> AgentNativeToolAvailability {
    #if os(iOS) && canImport(AVFoundation) && canImport(UIKit)
    return AgentIOSUIKitVisibleCaptureRuntime(
      artifactStore: artifactStore,
      nowMillis: nowMillis
    ).availability(kind: kind)
    #else
    return AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "iOS UIKit and AVFoundation visible capture surfaces are not available in this runtime"
    )
    #endif
  }

  func capturePhoto(
    facing: String,
    invocation: AgentNativeToolInvocation
  ) -> AgentIOSVisibleCaptureOutcome {
    #if os(iOS) && canImport(AVFoundation) && canImport(UIKit)
    return AgentIOSUIKitVisibleCaptureRuntime(
      artifactStore: artifactStore,
      nowMillis: nowMillis
    ).capturePhoto(facing: facing, invocation: invocation)
    #else
    return AgentIOSVisibleCaptureOutcome(
      status: .failed,
      code: "visible_capture_runtime_unavailable",
      message: "iOS UIKit and AVFoundation visible photo capture are not available in this runtime",
      retryable: false
    )
    #endif
  }

  func recordAudio(
    maxDurationSeconds: Int,
    invocation: AgentNativeToolInvocation
  ) -> AgentIOSVisibleCaptureOutcome {
    #if os(iOS) && canImport(AVFoundation) && canImport(UIKit)
    return AgentIOSUIKitVisibleCaptureRuntime(
      artifactStore: artifactStore,
      nowMillis: nowMillis
    ).recordAudio(maxDurationSeconds: maxDurationSeconds, invocation: invocation)
    #else
    return AgentIOSVisibleCaptureOutcome(
      status: .failed,
      code: "visible_capture_runtime_unavailable",
      message: "iOS UIKit and AVFoundation visible audio capture are not available in this runtime",
      retryable: false
    )
    #endif
  }
}

#if os(iOS) && canImport(AVFoundation) && canImport(UIKit)
private struct AgentIOSUIKitVisibleCaptureRuntime {
  private static let defaultPhotoTimeoutSeconds = 120
  private static let permissionTimeoutSeconds = 60

  var artifactStore: AgentIOSVisibleCaptureArtifactStore
  var nowMillis: () -> Int64

  func availability(kind: AgentIOSVisibleCaptureKind) -> AgentNativeToolAvailability {
    guard !AgentIOSVisibleCaptureBusyCoordinator.shared.isBusy else {
      return AgentNativeToolAvailability(
        status: .unavailable,
        reason: "Another user-visible capture is already active"
      )
    }
    return Self.onMain {
      switch kind {
      case .photo:
        return photoAvailability()
      case .audio:
        return audioAvailability()
      }
    }
  }

  func capturePhoto(
    facing: String,
    invocation: AgentNativeToolInvocation
  ) -> AgentIOSVisibleCaptureOutcome {
    guard !Thread.isMainThread else {
      return failure(
        code: "visible_capture_main_thread",
        message: "Visible capture must be launched from a background native tool executor",
        retryable: true
      )
    }
    let currentAvailability = availability(kind: .photo)
    guard currentAvailability.status == .available else {
      return failure(
        code: "camera_unavailable",
        message: currentAvailability.reason.ifBlank("The iOS camera capture surface is not available"),
        retryable: currentAvailability.status != .requiresSetup
      )
    }
    guard Self.onMain({ UIApplication.shared.applicationState == .active }) else {
      return failure(
        code: "visible_capture_not_foreground",
        message: "User-visible photo capture requires GalaxySSI to be in the foreground",
        retryable: true
      )
    }
    guard requestCameraAccess() else {
      return failure(
        code: "camera_permission_denied",
        message: "The iOS camera permission was not granted",
        retryable: false
      )
    }
    let requestId = invocation.context.invocationId
    guard AgentIOSVisibleCaptureBusyCoordinator.shared.begin(requestId) else {
      return failure(
        code: "capture_busy",
        message: "Another user-visible capture is already active",
        retryable: true
      )
    }
    defer {
      AgentIOSVisibleCaptureBusyCoordinator.shared.release(requestId)
    }

    try? invocation.reportProgress(
      stage: "waiting_for_capture",
      message: "Waiting for the foreground photo capture result",
      percent: 35
    )
    return waitForCapture(
      requestId: requestId,
      timeoutSeconds: timeoutSeconds(
        invocation: invocation,
        fallbackSeconds: Self.defaultPhotoTimeoutSeconds
      )
    ) { completion in
      guard let presenter = Self.topMostPresenter() else {
        completion(failure(
          code: "visible_capture_no_presenter",
          message: "No foreground iOS view controller is available for camera capture",
          retryable: true
        ))
        return
      }
      guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
        completion(failure(
          code: "camera_unavailable",
          message: "This iOS device does not expose a camera capture surface",
          retryable: true
        ))
        return
      }

      let controller = UIImagePickerController()
      controller.sourceType = .camera
      controller.cameraCaptureMode = .photo
      if let cameraDevice = Self.cameraDevice(for: facing),
         UIImagePickerController.isCameraDeviceAvailable(cameraDevice) {
        controller.cameraDevice = cameraDevice
      }
      controller.modalPresentationStyle = .fullScreen

      let coordinator = AgentIOSPhotoCaptureCoordinator(
        requestId: requestId,
        controller: controller,
        artifactStore: artifactStore,
        capturedAtEpochMillis: nowMillis(),
        completion: completion
      )
      controller.delegate = coordinator
      AgentIOSVisibleCapturePresentationRetainer.shared.retain(coordinator, requestId: requestId)
      presenter.present(controller, animated: true)
    }
  }

  func recordAudio(
    maxDurationSeconds: Int,
    invocation: AgentNativeToolInvocation
  ) -> AgentIOSVisibleCaptureOutcome {
    guard !Thread.isMainThread else {
      return failure(
        code: "visible_capture_main_thread",
        message: "Visible capture must be launched from a background native tool executor",
        retryable: true
      )
    }
    let durationSeconds = max(1, min(maxDurationSeconds, AgentIOSVisibleCaptureNativeToolCatalog.maxAudioDurationSeconds))
    let currentAvailability = availability(kind: .audio)
    guard currentAvailability.status == .available else {
      return failure(
        code: "microphone_unavailable",
        message: currentAvailability.reason.ifBlank("The iOS microphone capture surface is not available"),
        retryable: currentAvailability.status != .requiresSetup
      )
    }
    guard Self.onMain({ UIApplication.shared.applicationState == .active }) else {
      return failure(
        code: "visible_capture_not_foreground",
        message: "User-visible audio capture requires GalaxySSI to be in the foreground",
        retryable: true
      )
    }
    guard requestAudioAccess() else {
      return failure(
        code: "microphone_permission_denied",
        message: "The iOS microphone permission was not granted",
        retryable: false
      )
    }
    let requestId = invocation.context.invocationId
    guard AgentIOSVisibleCaptureBusyCoordinator.shared.begin(requestId) else {
      return failure(
        code: "capture_busy",
        message: "Another user-visible capture is already active",
        retryable: true
      )
    }
    defer {
      AgentIOSVisibleCaptureBusyCoordinator.shared.release(requestId)
    }

    try? invocation.reportProgress(
      stage: "waiting_for_capture",
      message: "Waiting for the foreground audio recording result",
      percent: 35
    )
    return waitForCapture(
      requestId: requestId,
      timeoutSeconds: timeoutSeconds(
        invocation: invocation,
        fallbackSeconds: durationSeconds + 15
      )
    ) { completion in
      guard let presenter = Self.topMostPresenter() else {
        completion(failure(
          code: "visible_capture_no_presenter",
          message: "No foreground iOS view controller is available for audio capture",
          retryable: true
        ))
        return
      }
      do {
        let outputURL = try artifactStore.makeArtifactURL(
          kind: .audio,
          fileExtension: "m4a",
          requestId: requestId
        )
        let controller = AgentIOSAudioCaptureViewController(
          requestId: requestId,
          outputURL: outputURL,
          maxDurationSeconds: durationSeconds,
          artifactStore: artifactStore,
          nowMillis: nowMillis,
          completion: completion
        )
        controller.modalPresentationStyle = .fullScreen
        AgentIOSVisibleCapturePresentationRetainer.shared.retain(controller, requestId: requestId)
        presenter.present(controller, animated: true)
      } catch {
        completion(failure(
          code: "capture_artifact_store_failed",
          message: "Could not prepare the iOS audio artifact file: \(error.localizedDescription)",
          retryable: true
        ))
      }
    }
  }

  private func photoAvailability() -> AgentNativeToolAvailability {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      return AgentNativeToolAvailability(
        status: .unavailable,
        reason: "This iOS device does not expose a camera capture surface"
      )
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized, .notDetermined:
      return .available
    case .denied, .restricted:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "iOS camera permission must be granted in Settings"
      )
    @unknown default:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "iOS camera permission is in an unknown state"
      )
    }
  }

  private func audioAvailability() -> AgentNativeToolAvailability {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted, .undetermined:
      return .available
    case .denied:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "iOS microphone permission must be granted in Settings"
      )
    @unknown default:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "iOS microphone permission is in an unknown state"
      )
    }
  }

  private func requestCameraAccess() -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      return true
    case .notDetermined:
      let semaphore = DispatchSemaphore(value: 0)
      let lock = NSLock()
      var granted = false
      AVCaptureDevice.requestAccess(for: .video) { allowed in
        lock.lock()
        granted = allowed
        lock.unlock()
        semaphore.signal()
      }
      guard semaphore.wait(timeout: .now() + .seconds(Self.permissionTimeoutSeconds)) == .success else {
        return false
      }
      lock.lock()
      let result = granted
      lock.unlock()
      return result
    case .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  private func requestAudioAccess() -> Bool {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted:
      return true
    case .undetermined:
      let semaphore = DispatchSemaphore(value: 0)
      let lock = NSLock()
      var granted = false
      AVAudioSession.sharedInstance().requestRecordPermission { allowed in
        lock.lock()
        granted = allowed
        lock.unlock()
        semaphore.signal()
      }
      guard semaphore.wait(timeout: .now() + .seconds(Self.permissionTimeoutSeconds)) == .success else {
        return false
      }
      lock.lock()
      let result = granted
      lock.unlock()
      return result
    case .denied:
      return false
    @unknown default:
      return false
    }
  }

  private func waitForCapture(
    requestId: String,
    timeoutSeconds: Int,
    start: @escaping (@escaping (AgentIOSVisibleCaptureOutcome) -> Void) -> Void
  ) -> AgentIOSVisibleCaptureOutcome {
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var outcome: AgentIOSVisibleCaptureOutcome?

    DispatchQueue.main.async {
      start { result in
        lock.lock()
        outcome = result
        lock.unlock()
        semaphore.signal()
      }
    }

    if semaphore.wait(timeout: .now() + .seconds(max(1, timeoutSeconds))) == .timedOut {
      DispatchQueue.main.async {
        AgentIOSVisibleCapturePresentationRetainer.shared.cancel(
          requestId: requestId,
          code: "capture_timeout",
          message: "The foreground iOS capture did not finish before the native tool deadline"
        )
      }
      return failure(
        code: "capture_timeout",
        message: "The foreground iOS capture did not finish before the native tool deadline",
        retryable: true
      )
    }

    lock.lock()
    let result = outcome
    lock.unlock()
    return result ?? failure(
      code: "capture_result_missing",
      message: "The foreground iOS capture finished without a result",
      retryable: true
    )
  }

  private func timeoutSeconds(invocation: AgentNativeToolInvocation, fallbackSeconds: Int) -> Int {
    let remainingSeconds = Int((max(0, invocation.remainingTimeMillis) + 999) / 1_000)
    return max(1, min(max(1, fallbackSeconds), remainingSeconds == 0 ? fallbackSeconds : remainingSeconds))
  }

  private func failure(code: String, message: String, retryable: Bool = false) -> AgentIOSVisibleCaptureOutcome {
    AgentIOSVisibleCaptureOutcome(
      status: .failed,
      code: code,
      message: message,
      retryable: retryable
    )
  }

  private static func cameraDevice(for value: String) -> UIImagePickerController.CameraDevice? {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "front":
      return .front
    case "back":
      return .rear
    default:
      return nil
    }
  }

  private static func topMostPresenter() -> UIViewController? {
    let activeScenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
    let windows = activeScenes.flatMap(\.windows)
    let root = windows.first(where: \.isKeyWindow)?.rootViewController
      ?? windows.first?.rootViewController
    return topMostViewController(from: root)
  }

  private static func topMostViewController(from root: UIViewController?) -> UIViewController? {
    if let navigation = root as? UINavigationController {
      return topMostViewController(from: navigation.visibleViewController)
    }
    if let tab = root as? UITabBarController {
      return topMostViewController(from: tab.selectedViewController)
    }
    if let presented = root?.presentedViewController {
      return topMostViewController(from: presented)
    }
    return root
  }

  private static func onMain<T>(_ body: () -> T) -> T {
    if Thread.isMainThread {
      return body()
    }
    return DispatchQueue.main.sync(execute: body)
  }
}

private final class AgentIOSVisibleCaptureBusyCoordinator {
  static let shared = AgentIOSVisibleCaptureBusyCoordinator()

  private let lock = NSLock()
  private var activeRequestId: String?

  var isBusy: Bool {
    lock.lock()
    let busy = activeRequestId != nil
    lock.unlock()
    return busy
  }

  func begin(_ requestId: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard activeRequestId == nil else {
      return false
    }
    activeRequestId = requestId
    return true
  }

  func release(_ requestId: String) {
    lock.lock()
    if activeRequestId == requestId {
      activeRequestId = nil
    }
    lock.unlock()
  }
}

protocol AgentIOSVisibleCaptureCancellable: AnyObject {
  func cancelCapture(code: String, message: String)
}

final class AgentIOSVisibleCapturePresentationRetainer {
  static let shared = AgentIOSVisibleCapturePresentationRetainer()

  private let lock = NSLock()
  private var retained: [String: AgentIOSVisibleCaptureCancellable] = [:]

  func retain(_ object: AgentIOSVisibleCaptureCancellable, requestId: String) {
    lock.lock()
    retained[requestId] = object
    lock.unlock()
  }

  func release(requestId: String) {
    lock.lock()
    retained[requestId] = nil
    lock.unlock()
  }

  func cancel(requestId: String, code: String, message: String) {
    lock.lock()
    let object = retained[requestId]
    lock.unlock()
    object?.cancelCapture(code: code, message: message)
  }
}

private func failure(code: String, message: String, retryable: Bool = false) -> AgentIOSVisibleCaptureOutcome {
  AgentIOSVisibleCaptureOutcome(
    status: .failed,
    code: code,
    message: message,
    retryable: retryable
  )
}
#endif
