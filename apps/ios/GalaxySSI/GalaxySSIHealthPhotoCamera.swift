import AVFoundation
import SwiftUI
import UIKit

struct GalaxySSIHealthPhotoCamera: View {
  let title: String
  let t: (String, String) -> String
  let onPhoto: (Data) -> Void
  @Environment(\.scenePhase) private var scene
  @Environment(\.dismiss) private var dismiss
  @StateObject private var camera = GalaxySSIHealthCameraSession()

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
          .accessibilityLabel(t("close", "Close"))
        Spacer()
        Text(title).font(.headline)
        Spacer()
        if camera.canLight {
          Button(action: camera.toggleLight) {
            Image(systemName: camera.lit ? "flashlight.on.fill" : "flashlight.off.fill").frame(width: 44, height: 44)
          }
          .accessibilityLabel(t("light", "Fill light"))
        } else { Color.clear.frame(width: 44, height: 44) }
      }
      if scene == .active && camera.ready {
        GalaxySSIHealthCameraPreview(session: camera.session)
          .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.6), style: StrokeStyle(dash: [8, 8]))
              .padding(.horizontal, 24).padding(.vertical, 32).allowsHitTesting(false)
          }
          .privacySensitive()
      } else {
        ZStack {
          Color.black
          if camera.failed {
            Text(t("camera_failed", "Camera unavailable. Check camera access in Settings."))
              .multilineTextAlignment(.center).foregroundColor(.white).padding()
          } else if scene == .active { ProgressView().tint(.white) }
        }
      }
      Button {
        let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
          .first { $0.activationState == .foregroundActive }?.interfaceOrientation ?? .portrait
        camera.capture(orientation: orientation) { bytes in
          guard scene == .active else { return }
          onPhoto(bytes)
          dismiss()
        }
      } label: {
        Image(systemName: "circle.inset.filled").font(.system(size: 52)).frame(width: 76, height: 68)
      }
      .accessibilityLabel(t("shutter", "Take photo"))
      .disabled(scene != .active || !camera.ready || camera.busy)
    }
    .buttonStyle(.plain)
    .background(Color.galaxySSIPageBackground)
    .onAppear { if scene == .active { camera.start() } }
    .onDisappear(perform: camera.stop)
    .onChange(of: scene) { if $0 == .active { camera.start() } else { camera.stop() } }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in camera.stop() }
  }
}

private struct GalaxySSIHealthCameraPreview: UIViewRepresentable {
  let session: AVCaptureSession

  func makeUIView(context: Context) -> Preview {
    let view = Preview()
    view.previewLayer.videoGravity = .resizeAspect
    view.previewLayer.session = session
    return view
  }

  func updateUIView(_ view: Preview, context: Context) { view.setNeedsLayout() }

  final class Preview: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
      super.layoutSubviews()
      if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
        connection.videoOrientation = GalaxySSIHealthCameraSession.orientation(window?.windowScene?.interfaceOrientation)
      }
    }
  }
}

private final class GalaxySSIHealthCameraSession: ObservableObject {
  @Published private(set) var ready = false
  @Published private(set) var failed = false
  @Published private(set) var canLight = false
  @Published private(set) var lit = false
  @Published private(set) var busy = false
  let session = AVCaptureSession()
  private let output = AVCapturePhotoOutput()
  private let queue = DispatchQueue(label: "com.galaxyssi.health.photo-camera")
  private var device: AVCaptureDevice?
  private var delegate: PhotoDelegate?
  private var generation = UUID()
  private var active = false

  func start() {
    guard !active else { return }
    active = true
    failed = false
    let token = generation
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: configure(token)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self, self.active, self.generation == token else { return }
          if granted { self.configure(token) } else { self.failed = true }
        }
      }
    default: failed = true
    }
  }

  private func configure(_ token: UUID) {
    queue.async { [self] in
      if device == nil, let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
         let input = try? AVCaptureDeviceInput(device: camera) {
        session.beginConfiguration()
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        if session.canAddInput(input), session.canAddOutput(output) {
          session.addInput(input)
          session.addOutput(output)
          output.isHighResolutionCaptureEnabled = true
          device = camera
        }
        session.commitConfiguration()
      }
      if device != nil, !session.isRunning { session.startRunning() }
      let running = session.isRunning
      let torch = device?.hasTorch == true
      DispatchQueue.main.async { [weak self] in
        guard let self, self.active, self.generation == token else { return }
        self.ready = running
        self.failed = !running
        self.canLight = torch
      }
    }
  }

  func stop() {
    generation = UUID()
    active = false
    ready = false; busy = false; canLight = false; lit = false
    queue.async { [self] in
      if let device, device.hasTorch, (try? device.lockForConfiguration()) != nil {
        device.torchMode = .off
        device.unlockForConfiguration()
      }
      if session.isRunning { session.stopRunning() }
    }
  }

  func toggleLight() {
    let token = generation
    queue.async { [self] in
      guard session.isRunning, let device, device.isTorchAvailable,
            (try? device.lockForConfiguration()) != nil else { return }
      defer { device.unlockForConfiguration() }
      let mode: AVCaptureDevice.TorchMode = device.torchMode == .on ? .off : .on
      guard device.isTorchModeSupported(mode) else { return }
      device.torchMode = mode
      DispatchQueue.main.async { [weak self] in
        if self?.generation == token { self?.lit = mode == .on }
      }
    }
  }

  func capture(orientation: UIInterfaceOrientation, onPhoto: @escaping (Data) -> Void) {
    guard ready, !busy else { return }
    busy = true
    let token = generation
    let videoOrientation = Self.orientation(orientation)
    queue.async { [self] in
      guard session.isRunning, delegate == nil, let connection = output.connection(with: .video),
            output.availablePhotoCodecTypes.contains(.jpeg) else {
        DispatchQueue.main.async { [weak self] in
          if self?.generation == token { self?.busy = false }
        }
        return
      }
      if connection.isVideoOrientationSupported { connection.videoOrientation = videoOrientation }
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      settings.isHighResolutionPhotoEnabled = true
      let callback = PhotoDelegate { [weak self] data in
        guard let self else { return }
        self.queue.async { self.delegate = nil }
        DispatchQueue.main.async {
          guard self.active, self.generation == token else { return }
          self.busy = false
          guard let data, !data.isEmpty, data.count <= GalaxySSIHealthOriginalStore.maximumFileBytes else {
            self.failed = true; self.ready = false
            return
          }
          onPhoto(data)
        }
      }
      delegate = callback
      output.capturePhoto(with: settings, delegate: callback)
    }
  }

  static func orientation(_ orientation: UIInterfaceOrientation?) -> AVCaptureVideoOrientation {
    switch orientation {
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    case .portraitUpsideDown: return .portraitUpsideDown
    default: return .portrait
    }
  }

  private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    var bytes: Data?
    let completed: (Data?) -> Void
    init(_ completed: @escaping (Data?) -> Void) { self.completed = completed }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
      if error == nil { bytes = photo.fileDataRepresentation() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
      completed(error == nil ? bytes : nil)
      bytes = nil
    }
  }
}
