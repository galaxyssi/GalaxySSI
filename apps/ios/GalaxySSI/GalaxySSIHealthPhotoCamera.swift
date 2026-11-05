import AVFoundation
import SwiftUI
import UIKit

struct GalaxySSIHealthPhotoCamera: UIViewControllerRepresentable {
  let mode: GalaxySSIHealthPhotoDraft.Mode
  let shutterTitle: String
  let torchTitle: String
  let closeTitle: String
  let galleryTitle: String
  let onGallery: () -> Void
  let onClose: () -> Void
  let onPhoto: (Result<Data, Error>) -> Void

  func makeUIViewController(context: Context) -> Controller { Controller(self) }
  func updateUIViewController(_ controller: Controller, context: Context) {}

  @MainActor
  final class Controller: UIViewController, AVCapturePhotoCaptureDelegate {
    private let configuration: GalaxySSIHealthPhotoCamera
    private let hardware = Hardware()
    private lazy var preview = AVCaptureVideoPreviewLayer(session: hardware.session)
    private let guide = UIView()
    private lazy var shutter = button("camera.circle.fill", label: configuration.shutterTitle, action: #selector(capture))
    private lazy var torch = button("flashlight.off.fill", label: configuration.torchTitle, action: #selector(flipTorch))
    private var visible = false
    private var pendingPhoto: Int64?
    private var interruptedPhoto: Int64?
    private var lit = false
    private var generation = UUID()

    init(_ configuration: GalaxySSIHealthPhotoCamera) {
      self.configuration = configuration
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .black
      preview.videoGravity = .resizeAspect
      view.layer.addSublayer(preview)
      guide.isUserInteractionEnabled = false
      guide.layer.borderWidth = 2
      guide.layer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
      guide.layer.cornerRadius = 8
      view.addSubview(guide)
      let close = button("xmark", label: configuration.closeTitle, action: #selector(closeCamera))
      let gallery = button("photo.on.rectangle", label: configuration.galleryTitle, action: #selector(showGallery))
      let bar = UIStackView(arrangedSubviews: [gallery, shutter, torch])
      bar.axis = .horizontal
      bar.distribution = .fillEqually
      bar.translatesAutoresizingMaskIntoConstraints = false
      close.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(bar); view.addSubview(close)
      NSLayoutConstraint.activate([
        bar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        bar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        bar.heightAnchor.constraint(equalToConstant: 64),
        close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
        close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        close.widthAnchor.constraint(equalToConstant: 48), close.heightAnchor.constraint(equalToConstant: 48)
      ])
      shutter.isEnabled = false; torch.isEnabled = false
      NotificationCenter.default.addObserver(self, selector: #selector(suspendCamera),
        name: UIApplication.willResignActiveNotification, object: nil)
      NotificationCenter.default.addObserver(self, selector: #selector(resumeCamera),
        name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      preview.frame = view.bounds
      if preview.connection?.isVideoOrientationSupported == true { preview.connection?.videoOrientation = orientation }
      let box = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 28, dy: 85)
      let width = max(0, min(box.width, box.height * (configuration.mode == .report ? 0.76 : 1.5)))
      let height = max(0, min(box.height, width / (configuration.mode == .report ? 0.76 : 1.5)))
      guide.frame = CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      visible = true
      resumeCamera()
    }

    override func viewWillDisappear(_ animated: Bool) {
      super.viewWillDisappear(animated)
      visible = false
      suspendCamera()
    }

    @objc private func resumeCamera() {
      guard visible, UIApplication.shared.applicationState == .active else { return }
      let current = UUID()
      generation = current
      Task {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard visible, generation == current, UIApplication.shared.applicationState == .active else { return }
        guard granted else { configuration.onPhoto(.failure(CameraFailure.unavailable)); return }
        hardware.start { [weak self] result in
          guard let self, self.visible, self.generation == current else { return }
          switch result {
          case .success(let supportsTorch): self.shutter.isEnabled = true; self.torch.isEnabled = supportsTorch
          case .failure(let error): self.configuration.onPhoto(.failure(error))
          }
        }
      }
    }

    @objc private func suspendCamera() {
      generation = UUID()
      if let pendingPhoto { interruptedPhoto = pendingPhoto }
      pendingPhoto = nil; lit = false
      torch.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
      shutter.isEnabled = false; torch.isEnabled = false
      hardware.stop()
    }

    @objc private func capture() {
      guard visible, pendingPhoto == nil, UIApplication.shared.applicationState == .active else { return }
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      settings.isHighResolutionPhotoEnabled = true
      interruptedPhoto = nil
      pendingPhoto = settings.uniqueID; shutter.isEnabled = false
      let id = settings.uniqueID
      hardware.capture(settings: settings, orientation: orientation, delegate: self) { [weak self] in
        self?.finishPhoto(id, result: .failure(CameraFailure.unavailable))
      }
    }

    @objc private func flipTorch() {
      lit.toggle()
      hardware.setTorch(lit)
      torch.setImage(UIImage(systemName: lit ? "flashlight.on.fill" : "flashlight.off.fill"), for: .normal)
    }

    @objc private func closeCamera() { configuration.onClose() }
    @objc private func showGallery() { configuration.onGallery() }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
      let result: Result<Data, Error>
      if let error { result = .failure(error) }
      else if let bytes = photo.fileDataRepresentation() { result = .success(bytes) }
      else { result = .failure(CameraFailure.unavailable) }
      let captured = photo.resolvedSettings.uniqueID
      Task { @MainActor in
        finishPhoto(captured, result: result)
      }
    }

    private func finishPhoto(_ id: Int64, result: Result<Data, Error>) {
      if pendingPhoto == id, visible, UIApplication.shared.applicationState == .active {
        pendingPhoto = nil
        configuration.onPhoto(result)
      } else if interruptedPhoto == id {
        interruptedPhoto = nil
        if case .failure = result { configuration.onPhoto(result) }
      }
    }

    private var orientation: AVCaptureVideoOrientation {
      switch view.window?.windowScene?.interfaceOrientation {
      case .landscapeLeft?: return .landscapeLeft
      case .landscapeRight?: return .landscapeRight
      case .portraitUpsideDown?: return .portraitUpsideDown
      default: return .portrait
      }
    }

    private func button(_ symbol: String, label: String, action: Selector) -> UIButton {
      let control = UIButton(type: .system)
      control.tintColor = .white
      control.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 29)), for: .normal)
      control.accessibilityLabel = label
      control.addTarget(self, action: action, for: .touchUpInside)
      return control
    }
  }

  private enum CameraFailure: Error { case unavailable }

  private final class Hardware: @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "galaxyssi.health.photo.capture")
    private var device: AVCaptureDevice?

    func start(_ complete: @escaping @MainActor (Result<Bool, Error>) -> Void) {
      queue.async {
        do {
          if self.device == nil {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            else { throw CameraFailure.unavailable }
            let input = try AVCaptureDeviceInput(device: device)
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            self.session.sessionPreset = .photo
            guard self.session.canAddInput(input), self.session.canAddOutput(self.output)
            else { throw CameraFailure.unavailable }
            self.session.addInput(input); self.session.addOutput(self.output)
            self.output.isHighResolutionCaptureEnabled = true
            if device.isFocusModeSupported(.continuousAutoFocus), (try? device.lockForConfiguration()) != nil {
              device.focusMode = .continuousAutoFocus
              device.unlockForConfiguration()
            }
            self.device = device
          }
          if !self.session.isRunning { self.session.startRunning() }
          let ready = self.session.isRunning && self.output.availablePhotoCodecTypes.contains(.jpeg)
          let hasTorch = self.device?.hasTorch == true
          Task { @MainActor in complete(ready ? .success(hasTorch) : .failure(CameraFailure.unavailable)) }
        } catch { Task { @MainActor in complete(.failure(error)) } }
      }
    }

    func stop() {
      queue.async {
        self.applyTorch(false)
        if self.session.isRunning { self.session.stopRunning() }
      }
    }

    func setTorch(_ on: Bool) { queue.async { self.applyTorch(on) } }

    private func applyTorch(_ on: Bool) {
      guard let device, device.hasTorch, device.isTorchModeSupported(on ? .on : .off),
            (try? device.lockForConfiguration()) != nil else { return }
      defer { device.unlockForConfiguration() }
      device.torchMode = on ? .on : .off
    }

    func capture(settings: AVCapturePhotoSettings, orientation: AVCaptureVideoOrientation,
                 delegate: AVCapturePhotoCaptureDelegate, rejected: @escaping @MainActor () -> Void) {
      queue.async {
        guard self.session.isRunning else { Task { @MainActor in rejected() }; return }
        if self.output.connection(with: .video)?.isVideoOrientationSupported == true {
          self.output.connection(with: .video)?.videoOrientation = orientation
        }
        self.output.capturePhoto(with: settings, delegate: delegate)
      }
    }
  }
}
