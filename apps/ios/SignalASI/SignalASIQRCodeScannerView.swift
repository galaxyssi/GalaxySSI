import AVFoundation
import CoreImage
import PhotosUI
import SwiftUI
import UIKit
import Vision

enum SignalASIQRCodeImageRenderer {
  static func image(from text: String) -> UIImage? {
    let data = Data(text.utf8)
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
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var onCode: (String) -> Void
  var onError: (String) -> Void = { _ in }

  init(
    onCode: @escaping (String) -> Void,
    onError: @escaping (String) -> Void = { _ in }
  ) {
    self.onCode = onCode
    self.onError = onError
  }

  func makeUIViewController(context: Context) -> QRScannerViewController {
    QRScannerViewController(
      onCode: onCode,
      onError: onError,
      messages: QRScannerMessages(
        cameraAccessRequired: t(
          "signalasi.scanner.camera_access_required",
          "Camera access is required to scan SignalASI QR codes."
        ),
        cameraUnavailable: t(
          "signalasi.scanner.camera_unavailable",
          "Camera is unavailable on this device."
        ),
        outputUnavailable: t(
          "signalasi.scanner.output_unavailable",
          "QR scanner output is unavailable."
        ),
        accessUnavailable: t(
          "signalasi.scanner.access_unavailable",
          "Camera access is unavailable on this device."
        ),
        cancelAction: t(
          "signalasi.common.cancel",
          "Cancel"
        ),
        photoAction: t(
          "signalasi.scanner.photo_action",
          "Photo"
        ),
        photoScanFailed: t(
          "signalasi.scanner.photo_scan_failed",
          "No SignalASI QR code was found in that photo."
        )
      )
    )
  }

  func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
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
  private let messages: QRScannerMessages
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "signalasi.qr-scanner.session")
  private var configured = false
  private var didFinish = false
  private var photoButton: UIButton?
  private var statusLabel: UILabel?

  fileprivate init(
    onCode: @escaping (String) -> Void,
    onError: @escaping (String) -> Void,
    messages: QRScannerMessages
  ) {
    self.onCode = onCode
    self.onError = onError
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
    guard configured, !didFinish else { return }
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
    guard !configured else { return }
    guard let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      reportScannerError(messages.cameraUnavailable)
      return
    }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      reportScannerError(messages.outputUnavailable)
      return
    }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
    output.metadataObjectTypes = [.qr]
    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    preview.frame = view.bounds
    view.layer.addSublayer(preview)
    configured = true
    startSession()
  }

  private func installPhotoButton() {
    let button = UIButton(type: .system)
    button.setTitle(messages.photoAction, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    button.backgroundColor = UIColor.black.withAlphaComponent(0.52)
    button.layer.cornerRadius = 8
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
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
    dismiss(animated: true)
  }

  @objc private func openPhotoPicker() {
    guard !didFinish else { return }
    stopSession()
    let configuration = PHPickerConfiguration(photoLibrary: .shared())
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
      if !self.session.isRunning {
        self.session.startRunning()
      }
    }
  }

  private func stopSession() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.session.isRunning {
        self.session.stopRunning()
      }
    }
  }

  private func reportScannerError(_ message: String) {
    guard !didFinish else { return }
    didFinish = true
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
    view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach {
      $0.frame = view.bounds
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
    statusLabel?.removeFromSuperview()
    onCode(value)
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
