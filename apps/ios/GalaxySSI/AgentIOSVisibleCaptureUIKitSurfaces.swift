import Foundation

#if os(iOS) && canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import UIKit

final class AgentIOSPhotoCaptureCoordinator: NSObject,
  UIImagePickerControllerDelegate,
  UINavigationControllerDelegate,
  AgentIOSVisibleCaptureCancellable
{
  private let requestId: String
  private weak var controller: UIImagePickerController?
  private let artifactStore: AgentIOSVisibleCaptureArtifactStore
  private let capturedAtEpochMillis: Int64
  private let completion: (AgentIOSVisibleCaptureOutcome) -> Void
  private let lock = NSLock()
  private var didFinish = false

  init(
    requestId: String,
    controller: UIImagePickerController,
    artifactStore: AgentIOSVisibleCaptureArtifactStore,
    capturedAtEpochMillis: Int64,
    completion: @escaping (AgentIOSVisibleCaptureOutcome) -> Void
  ) {
    self.requestId = requestId
    self.controller = controller
    self.artifactStore = artifactStore
    self.capturedAtEpochMillis = capturedAtEpochMillis
    self.completion = completion
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    guard let image = info[.originalImage] as? UIImage else {
      finish(failure(
        code: "photo_capture_missing_image",
        message: "The iOS camera capture did not return an image",
        retryable: true
      ))
      return
    }
    do {
      guard let data = image.jpegData(compressionQuality: 0.92) else {
        finish(failure(
          code: "photo_capture_encode_failed",
          message: "The captured iOS photo could not be encoded as JPEG",
          retryable: true
        ))
        return
      }
      let fileURL = try artifactStore.makeArtifactURL(
        kind: .photo,
        fileExtension: "jpg",
        requestId: requestId
      )
      try data.write(to: fileURL, options: [.atomic])
      let sizeBytes = try artifactStore.fileSize(fileURL)
      let pixelWidth = Int((image.size.width * image.scale).rounded())
      let pixelHeight = Int((image.size.height * image.scale).rounded())
      finish(AgentIOSVisibleCaptureOutcome(
        status: .succeeded,
        artifact: AgentIOSVisibleCaptureArtifact(
          kind: .photo,
          contentUri: fileURL.absoluteString,
          mimeType: "image/jpeg",
          sizeBytes: sizeBytes,
          widthPixels: pixelWidth,
          heightPixels: pixelHeight,
          capturedAtEpochMillis: capturedAtEpochMillis,
          completedBy: "ios_camera_capture"
        )
      ))
    } catch {
      finish(failure(
        code: "photo_capture_artifact_failed",
        message: "The captured iOS photo could not be stored: \(error.localizedDescription)",
        retryable: true
      ))
    }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    finish(AgentIOSVisibleCaptureOutcome(
      status: .cancelled,
      code: "capture_cancelled",
      message: "The user cancelled the visible photo capture"
    ))
  }

  func cancelCapture(code: String, message: String) {
    finish(failure(code: code, message: message, retryable: true))
  }

  private func finish(_ outcome: AgentIOSVisibleCaptureOutcome) {
    lock.lock()
    guard !didFinish else {
      lock.unlock()
      return
    }
    didFinish = true
    lock.unlock()

    let finishBlock = { [completion, requestId] in
      AgentIOSVisibleCapturePresentationRetainer.shared.release(requestId: requestId)
      completion(outcome)
    }
    if controller?.presentingViewController != nil {
      controller?.dismiss(animated: true, completion: finishBlock)
    } else {
      finishBlock()
    }
  }
}

final class AgentIOSAudioCaptureViewController: UIViewController,
  AVAudioRecorderDelegate,
  AgentIOSVisibleCaptureCancellable
{
  private let requestId: String
  private let outputURL: URL
  private let maxDurationSeconds: Int
  private let artifactStore: AgentIOSVisibleCaptureArtifactStore
  private let nowMillis: () -> Int64
  private let completion: (AgentIOSVisibleCaptureOutcome) -> Void
  private let stateLock = NSLock()

  private var recorder: AVAudioRecorder?
  private var timer: Timer?
  private var startedAt = Date()
  private var didStart = false
  private var didFinish = false

  private let titleLabel = UILabel()
  private let clockLabel = UILabel()
  private let stopButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)

  init(
    requestId: String,
    outputURL: URL,
    maxDurationSeconds: Int,
    artifactStore: AgentIOSVisibleCaptureArtifactStore,
    nowMillis: @escaping () -> Int64,
    completion: @escaping (AgentIOSVisibleCaptureOutcome) -> Void
  ) {
    self.requestId = requestId
    self.outputURL = outputURL
    self.maxDurationSeconds = max(1, maxDurationSeconds)
    self.artifactStore = artifactStore
    self.nowMillis = nowMillis
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !didStart else {
      return
    }
    didStart = true
    startRecording()
  }

  func cancelCapture(code: String, message: String) {
    finish(failure(code: code, message: message, retryable: true), deleteFile: true)
  }

  func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
    if flag {
      finishSucceeded(completedBy: "max_duration")
    } else {
      finish(failure(
        code: "audio_capture_failed",
        message: "The iOS audio recorder stopped before completing a valid recording",
        retryable: true
      ), deleteFile: true)
    }
  }

  func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
    finish(failure(
      code: "audio_capture_encode_failed",
      message: "The iOS audio recorder could not encode the recording: \(error?.localizedDescription ?? "unknown error")",
      retryable: true
    ), deleteFile: true)
  }

  @objc private func stopTapped() {
    finishSucceeded(completedBy: "manual_stop")
  }

  @objc private func cancelTapped() {
    finish(AgentIOSVisibleCaptureOutcome(
      status: .cancelled,
      code: "capture_cancelled",
      message: "The user cancelled the visible audio recording"
    ), deleteFile: true)
  }

  private func configureView() {
    view.backgroundColor = UIColor.systemBackground

    titleLabel.text = "Recording audio"
    titleLabel.font = UIFont.preferredFont(forTextStyle: .title2)
    titleLabel.textAlignment = .center
    titleLabel.adjustsFontForContentSizeCategory = true

    clockLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .semibold)
    clockLabel.textAlignment = .center
    clockLabel.adjustsFontForContentSizeCategory = true

    stopButton.setTitle("Stop", for: .normal)
    stopButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
    stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)

    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

    let buttonStack = UIStackView(arrangedSubviews: [stopButton, cancelButton])
    buttonStack.axis = .horizontal
    buttonStack.spacing = 16
    buttonStack.distribution = .fillEqually

    let contentStack = UIStackView(arrangedSubviews: [titleLabel, clockLabel, buttonStack])
    contentStack.axis = .vertical
    contentStack.spacing = 24
    contentStack.alignment = .fill
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(contentStack)
    NSLayoutConstraint.activate([
      contentStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      contentStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
      contentStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stopButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
      cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
    ])
    updateClock()
  }

  private func startRecording() {
    do {
      try artifactStore.fileManager.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true)
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
      ]
      let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
      recorder.delegate = self
      recorder.isMeteringEnabled = true
      startedAt = Date()
      self.recorder = recorder
      guard recorder.record(forDuration: TimeInterval(maxDurationSeconds)) else {
        finish(failure(
          code: "audio_capture_start_failed",
          message: "The iOS audio recorder could not start",
          retryable: true
        ), deleteFile: true)
        return
      }
      timer = Timer.scheduledTimer(
        withTimeInterval: 0.25,
        repeats: true
      ) { [weak self] _ in
        self?.updateClock()
      }
      updateClock()
    } catch {
      finish(failure(
        code: "audio_capture_start_failed",
        message: "The iOS audio recorder could not start: \(error.localizedDescription)",
        retryable: true
      ), deleteFile: true)
    }
  }

  private func updateClock() {
    let elapsed = max(0, Date().timeIntervalSince(startedAt))
    let remaining = max(0, Int(ceil(Double(maxDurationSeconds) - elapsed)))
    clockLabel.text = String(format: "00:%02d", min(99, remaining))
  }

  private func finishSucceeded(completedBy: String) {
    let durationMillis = Int64(max(0, Date().timeIntervalSince(startedAt) * 1_000).rounded())
    recorder?.delegate = nil
    recorder?.stop()
    do {
      let sizeBytes = try artifactStore.fileSize(outputURL)
      guard sizeBytes > 0 else {
        finish(failure(
          code: "audio_capture_empty",
          message: "The iOS audio recorder produced an empty artifact",
          retryable: true
        ), deleteFile: true)
        return
      }
      finish(AgentIOSVisibleCaptureOutcome(
        status: .succeeded,
        artifact: AgentIOSVisibleCaptureArtifact(
          kind: .audio,
          contentUri: outputURL.absoluteString,
          mimeType: "audio/mp4",
          sizeBytes: sizeBytes,
          durationMillis: durationMillis,
          capturedAtEpochMillis: nowMillis(),
          completedBy: completedBy
        )
      ), deleteFile: false)
    } catch {
      finish(failure(
        code: "audio_capture_artifact_failed",
        message: "The iOS audio recording could not be stored: \(error.localizedDescription)",
        retryable: true
      ), deleteFile: true)
    }
  }

  private func finish(_ outcome: AgentIOSVisibleCaptureOutcome, deleteFile: Bool) {
    stateLock.lock()
    guard !didFinish else {
      stateLock.unlock()
      return
    }
    didFinish = true
    stateLock.unlock()

    timer?.invalidate()
    timer = nil
    if recorder?.isRecording == true, outcome.status != .succeeded {
      recorder?.stop()
    }
    recorder = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    if deleteFile {
      try? artifactStore.fileManager.removeItem(at: outputURL)
    }

    let finishBlock = { [completion, requestId] in
      AgentIOSVisibleCapturePresentationRetainer.shared.release(requestId: requestId)
      completion(outcome)
    }
    if presentingViewController != nil {
      dismiss(animated: true, completion: finishBlock)
    } else {
      finishBlock()
    }
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
