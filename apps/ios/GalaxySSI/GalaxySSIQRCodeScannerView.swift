import AVFoundation
import CoreImage
import PhotosUI
import SwiftUI
import UIKit
import Vision

enum GalaxySSIQRCodeImageRenderer {
  private static let maximumMediumCorrectionPayloadBytes = 2_300

  static func image(from text: String) -> UIImage? {
    let data = Data(text.utf8)
    guard !data.isEmpty, data.count <= maximumMediumCorrectionPayloadBytes else { return nil }
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cgImage)
  }
}

struct QRCodeScannerView: UIViewControllerRepresentable {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var onCode: (String) -> Void
  var onError: (String) -> Void = { _ in }
  var onCancel: () -> Void = {}

  init(
    onCode: @escaping (String) -> Void,
    onError: @escaping (String) -> Void = { _ in },
    onCancel: @escaping () -> Void = {}
  ) {
    self.onCode = onCode
    self.onError = onError
    self.onCancel = onCancel
  }

  func makeUIViewController(context: Context) -> QRScannerViewController {
    QRScannerViewController(
      onCode: onCode,
      onError: onError,
      onCancel: onCancel,
      messages: QRScannerMessages(
        cameraAccessRequired: t(
          "galaxyssi.scanner.camera_access_required",
          "Camera access is required to scan GalaxySSI QR codes."
        ),
        cameraUnavailable: t(
          "galaxyssi.scanner.camera_unavailable",
          "Camera is unavailable on this device."
        ),
        outputUnavailable: t(
          "galaxyssi.scanner.output_unavailable",
          "QR scanner output is unavailable."
        ),
        accessUnavailable: t(
          "galaxyssi.scanner.access_unavailable",
          "Camera access is unavailable on this device."
        ),
        cancelAction: t(
          "galaxyssi.common.cancel",
          "Cancel"
        ),
        photoAction: t(
          "galaxyssi.scanner.photo_action",
          "Photo"
        ),
        photoScanFailed: t(
          "galaxyssi.scanner.photo_scan_failed",
          "No GalaxySSI QR code was found in that photo."
        )
      )
    )
  }

  func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

fileprivate struct QRScannerMessages {
  var cameraAccessRequired: String
  var cameraUnavailable: String
  var outputUnavailable: String
  var accessUnavailable: String
  var cancelAction: String
  var photoAction: String
  var photoScanFailed: String
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, PHPickerViewControllerDelegate {
  private let onCode: (String) -> Void
  private let onError: (String) -> Void
  private let onCancel: () -> Void
  private let messages: QRScannerMessages
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "galaxyssi.qr-scanner.session")
  // AVCaptureSession configuration and run state must stay on one queue. Camera
  // scans can otherwise race a SwiftUI sheet dismissal or photo-picker return.
  private var sessionConfigured = false
  private var sessionConfiguring = false
  private var sessionShouldRun = false
  private var didFinish = false
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var photoButton: UIButton?
  private var statusLabel: UILabel?

  fileprivate init(
    onCode: @escaping (String) -> Void,
    onError: @escaping (String) -> Void,
    onCancel: @escaping () -> Void,
    messages: QRScannerMessages
  ) {
    self.onCode = onCode
    self.onError = onError
    self.onCancel = onCancel
    self.messages = messages
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    installCancelButton()
    installPhotoButton()
    prepareCamera()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopSession()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    guard !didFinish else { return }
    startSession()
  }

  deinit {
    let session = session
    sessionQueue.async {
      if session.isRunning {
        session.stopRunning()
      }
    }
  }

  private func prepareCamera() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
        DispatchQueue.main.async {
          guard let self else { return }
          if allowed {
            self.configureSession()
          } else {
            self.reportScannerError(self.messages.cameraAccessRequired)
          }
        }
      }
    case .denied, .restricted:
      reportScannerError(messages.cameraAccessRequired)
    @unknown default:
      reportScannerError(messages.accessUnavailable)
    }
  }

  private func configureSession() {
    sessionQueue.async { [weak self] in
      self?.configureSessionOnQueue()
    }
  }

  private func configureSessionOnQueue() {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    guard !sessionConfigured, !sessionConfiguring else { return }
    sessionConfiguring = true
    defer { sessionConfiguring = false }
    guard let device = AVCaptureDevice.default(
      .builtInWideAngleCamera,
      for: .video,
      position: .back
    ) ?? AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      reportScannerErrorOnMain(messages.cameraUnavailable)
      return
    }

    session.beginConfiguration()
    configureCamera(device)
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      session.commitConfiguration()
      reportScannerErrorOnMain(messages.outputUnavailable)
      return
    }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
    output.metadataObjectTypes = [.qr]
    sessionConfigured = true
    session.commitConfiguration()
    DispatchQueue.main.async { [weak self] in
      self?.installPreviewLayer()
    }
    startSessionOnQueue()
  }

  private func installPreviewLayer() {
    guard previewLayer == nil, !didFinish else { return }
    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    // Keep camera pixels behind the scanner actions installed as UIKit subviews.
    view.layer.insertSublayer(preview, at: 0)
    previewLayer = preview
    updatePreviewLayout()
  }

  private func configureCamera(_ device: AVCaptureDevice) {
    guard device.lockForConfigurationIfAvailable() else { return }
    defer { device.unlockForConfiguration() }
    if device.isFocusModeSupported(.continuousAutoFocus) {
      device.focusMode = .continuousAutoFocus
    }
    if device.isExposureModeSupported(.continuousAutoExposure) {
      device.exposureMode = .continuousAutoExposure
    }
  }

  private func installPhotoButton() {
    let button = UIButton(type: .system)
    button.setTitle(messages.photoAction, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    button.backgroundColor = UIColor.black.withAlphaComponent(0.52)
    button.layer.cornerRadius = 8
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    button.accessibilityIdentifier = "ios.agent.qr-scanner.photo-library"
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(openPhotoPicker), for: .touchUpInside)
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
    ])
    photoButton = button
  }

  private func installCancelButton() {
    let button = UIButton(type: .system)
    button.setTitle(messages.cancelAction, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    button.backgroundColor = UIColor.black.withAlphaComponent(0.52)
    button.layer.cornerRadius = 8
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    button.accessibilityIdentifier = "ios.agent.qr-scanner.cancel"
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(cancelScanner), for: .touchUpInside)
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
    ])
  }

  @objc private func cancelScanner() {
    guard !didFinish else { return }
    didFinish = true
    stopSession()
    onCancel()
    dismiss(animated: true)
  }

  @objc private func openPhotoPicker() {
    guard !didFinish else { return }
    stopSession()
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    present(picker, animated: true)
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true) { [weak self] in
      guard let self, !self.didFinish else { return }
      self.startSession()
    }
    guard let provider = results.first?.itemProvider else { return }
    guard provider.canLoadObject(ofClass: UIImage.self) else {
      showPhotoScanFailure()
      return
    }
    provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
      guard let self else { return }
      DispatchQueue.main.async {
        guard let image = object as? UIImage else {
          self.showPhotoScanFailure()
          return
        }
        self.detectQRCode(in: image)
      }
    }
  }

  private func detectQRCode(in image: UIImage) {
    let request = VNDetectBarcodesRequest { [weak self] request, _ in
      let value = (request.results as? [VNBarcodeObservation])?
        .first(where: { $0.symbology == .QR })?.payloadStringValue
      DispatchQueue.main.async {
        guard let self else { return }
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          self.finish(with: value)
        } else {
          self.showPhotoScanFailure()
        }
      }
    }
    request.symbologies = [.QR]
    do {
      if let cgImage = image.cgImage {
        try VNImageRequestHandler(
          cgImage: cgImage,
          orientation: image.cgImagePropertyOrientation,
          options: [:]
        ).perform([request])
      } else if let ciImage = image.ciImage ?? CIImage(image: image) {
        try VNImageRequestHandler(
          ciImage: ciImage,
          orientation: image.cgImagePropertyOrientation,
          options: [:]
        ).perform([request])
      } else {
        showPhotoScanFailure()
      }
    } catch {
      showPhotoScanFailure()
    }
  }

  private func startSession() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.sessionShouldRun = true
      self.startSessionOnQueue()
    }
  }

  private func startSessionOnQueue() {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    guard sessionConfigured, sessionShouldRun, !session.isRunning else { return }
    session.startRunning()
  }

  private func stopSession() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.sessionShouldRun = false
      if self.session.isRunning {
        self.session.stopRunning()
      }
    }
  }

  private func reportScannerErrorOnMain(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.reportScannerError(message)
    }
  }

  private func reportScannerError(_ message: String) {
    guard !didFinish else { return }
    didFinish = true
    stopSession()
    onError(message)
    let label = UILabel()
    label.text = message
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
  }

  private func showPhotoScanFailure() {
    guard !didFinish else { return }
    if let statusLabel {
      statusLabel.text = messages.photoScanFailed
      return
    }
    let label = UILabel()
    label.text = messages.photoScanFailed
    label.textColor = .white
    label.backgroundColor = UIColor.black.withAlphaComponent(0.68)
    label.textAlignment = .center
    label.numberOfLines = 0
    label.layer.cornerRadius = 8
    label.layer.masksToBounds = true
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      label.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
    ])
    statusLabel = label
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updatePreviewLayout()
  }

  private func updatePreviewLayout() {
    previewLayer?.frame = view.bounds
    guard let orientation = captureVideoOrientation else { return }
    if let previewConnection = previewLayer?.connection,
       previewConnection.isVideoOrientationSupported {
      previewConnection.videoOrientation = orientation
    }
    if let metadataConnection = session.outputs
      .compactMap({ $0 as? AVCaptureMetadataOutput })
      .first?.connection(with: .video),
       metadataConnection.isVideoOrientationSupported {
      metadataConnection.videoOrientation = orientation
    }
  }

  private var captureVideoOrientation: AVCaptureVideoOrientation? {
    switch view.window?.windowScene?.interfaceOrientation {
    case .portrait: return .portrait
    case .portraitUpsideDown: return .portraitUpsideDown
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    default: return nil
    }
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !didFinish,
          let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
          let value = readable.stringValue else {
      return
    }
    stopSession()
    finish(with: value)
  }

  private func finish(with value: String) {
    guard !didFinish else { return }
    didFinish = true
    stopSession()
    statusLabel?.removeFromSuperview()
    onCode(value)
  }
}

private extension AVCaptureDevice {
  func lockForConfigurationIfAvailable() -> Bool {
    (try? lockForConfiguration()) != nil
  }
}

private extension UIImage {
  var cgImagePropertyOrientation: CGImagePropertyOrientation {
    switch imageOrientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
