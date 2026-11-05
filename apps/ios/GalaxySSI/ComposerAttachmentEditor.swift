import AVFoundation
import QuickLook
import SwiftUI
import UIKit

struct ComposerAttachmentEditor: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.dismiss) private var dismiss
  let attachment: GalaxySSIDraftAttachment
  let onReplace: (GalaxySSIDraftAttachment) -> Bool
  let onRemove: () -> Void
  @State private var source: UIImage?
  @State private var preview: UIImage?
  @State private var crop = ComposerAttachmentCrop()
  @State private var editing = false
  @State private var zoomAtStart: CGFloat?
  @State private var retake = false
  @State private var finishAfterRetake = false
  @State private var saveTask: Task<Void, Never>?
  @State private var error = ""

  var body: some View {
    VStack(spacing: 12) {
      GalaxySSITopBar(title: attachment.displayName, sideContentWidth: 44, leading: {
        Button { dismiss() } label: {
          Image(systemName: "xmark").frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text(t("galaxyssi.common.cancel", "Cancel")))
      }, trailing: { Color.clear })
      if attachment.isImage {
        imageViewport
      } else {
        ComposerAttachmentDocumentPreview(attachment: attachment)
      }
      if editing {
        cropControls
      } else {
        previewActions
      }
      if !error.isEmpty {
        Text(error).font(.footnote).foregroundColor(.red)
      }
    }
    .padding(.bottom, 12)
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .onAppear {
      guard attachment.isImage, preview == nil else { return }
      source = ComposerAttachmentCrop.image(from: attachment.composerSourceData, maxPixelSize: 1_024)
      preview = ComposerAttachmentCrop.image(from: attachment.data, maxPixelSize: 1_024)
    }
    .onDisappear {
      saveTask?.cancel()
      saveTask = nil
    }
    .fullScreenCover(isPresented: $retake, onDismiss: {
      if finishAfterRetake { dismiss() }
    }) {
      CameraAttachmentPickerView(onAttachment: { replacement in
        var replacement = replacement
        replacement.id = attachment.id
        finishAfterRetake = onReplace(replacement)
        retake = false
      }, onCancel: { retake = false })
    }
  }

  private var imageViewport: some View {
    GeometryReader { geometry in
      if let image = preview {
        let scale = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ZStack {
          Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
          if editing, let source {
            let canvas = crop.canvas(for: source.size)
            let rect = crop.selection(in: canvas, source: source.size)
            Rectangle()
              .strokeBorder(.white, lineWidth: 2)
              .shadow(color: .black, radius: 2)
              .frame(width: rect.width * scale, height: rect.height * scale)
              .position(x: rect.midX * scale, y: rect.midY * scale)
              .allowsHitTesting(false)
          }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .local).onChanged { value in
          guard editing, crop.aspect == .free, size.width > 0, size.height > 0 else { return }
          crop.zoom = 1
          crop.freeSelection = CGRect(
            x: value.startLocation.x / size.width, y: value.startLocation.y / size.height,
            width: value.translation.width / size.width, height: value.translation.height / size.height
          ).standardized
        })
        .simultaneousGesture(MagnificationGesture().onChanged { value in
          guard editing else { return }
          if zoomAtStart == nil { zoomAtStart = crop.zoom }
          crop.zoom = min(4, max(1, (zoomAtStart ?? 1) * value))
        }.onEnded { _ in zoomAtStart = nil })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text(t("composer_attachment_preview_unavailable", "Preview unavailable"))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private var previewActions: some View {
    let count = 1 + (source != nil ? 1 : 0) + (attachment.composerOriginal != nil ? 1 : 0)
    let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0, alignment: .top), count: count)
    return VStack(spacing: 8) {
      LazyVGrid(columns: columns, spacing: 0) {
        if source != nil {
          Button {
            crop = attachment.composerCrop ?? ComposerAttachmentCrop()
            editing = true
            updatePreview()
          } label: {
            previewActionLabel(t("composer_attachment_crop", "Crop"), icon: "crop")
          }
        }
        Button(role: .destructive) { onRemove(); dismiss() } label: {
          previewActionLabel(t("galaxyssi.common.delete", "Delete"), icon: "trash")
        }
        if attachment.composerOriginal != nil {
          Button {
            if onReplace(attachment.restoringComposerOriginal()) { dismiss() }
          } label: {
            previewActionLabel(t("composer_attachment_original", "Original"), icon: "photo")
          }
        }
      }
      if attachment.sourceDescription == "camera",
         UIImagePickerController.isSourceTypeAvailable(.camera),
         AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
        Button { retake = true } label: {
          previewActionLabel(t("composer_attachment_retake", "Retake"), icon: "camera")
        }
      }
    }
    .font(.subheadline)
    .padding(.horizontal, 12)
  }

  private func previewActionLabel(_ title: String, icon: String) -> some View {
    VStack(spacing: 4) {
      Image(systemName: icon)
        .imageScale(.medium)
        .accessibilityHidden(true)
      Text(title)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 4)
    .frame(maxWidth: .infinity, minHeight: 48)
    .contentShape(Rectangle())
  }

  private var cropControls: some View {
    VStack(spacing: 8) {
      HStack {
        Menu {
          ForEach(ComposerAttachmentCrop.Aspect.allCases) { aspect in
            Button { crop.aspect = aspect; crop.freeSelection = nil } label: {
              if crop.aspect == aspect { Label(aspectTitle(aspect), systemImage: "checkmark") }
              else { Text(aspectTitle(aspect)) }
            }
          }
        } label: {
          Label(aspectTitle(crop.aspect), systemImage: "aspectratio")
        }
        Spacer(minLength: 4)
        Button {
          crop.rotation = (crop.rotation + 90) % 360
          crop.freeSelection = nil
        } label: { Image(systemName: "rotate.right").frame(width: 40, height: 40) }
          .accessibilityLabel(Text(t("composer_attachment_rotate", "Rotate")))
        Button { crop.mirrored.toggle(); crop.freeSelection = nil } label: {
          Image(systemName: "arrow.left.and.right").frame(width: 40, height: 40)
        }
        .accessibilityLabel(Text(t("composer_attachment_flip", "Flip")))
        Button { crop = ComposerAttachmentCrop() } label: {
          Image(systemName: "arrow.counterclockwise").frame(width: 40, height: 40)
        }
        .accessibilityLabel(Text(t("composer_attachment_reset", "Reset")))
      }
      HStack {
        Image(systemName: "rotate.right")
        Slider(value: $crop.fineRotation, in: -45...45, step: 1)
          .accessibilityLabel(Text(t("composer_attachment_fine_rotate", "Fine rotation")))
        Text("\(Int(crop.fineRotation))°").monospacedDigit().frame(width: 40)
      }
      HStack {
        Button(t("galaxyssi.common.cancel", "Cancel")) {
          editing = false
          preview = ComposerAttachmentCrop.image(from: attachment.data, maxPixelSize: 1_024)
        }
        Spacer()
        Button(t("galaxyssi.common.save", "Save"), action: save)
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(.horizontal, 16)
    .disabled(saveTask != nil)
    .onChange(of: crop.rotation) { _ in updatePreview() }
    .onChange(of: crop.fineRotation) { _ in updatePreview() }
    .onChange(of: crop.mirrored) { _ in updatePreview() }
  }

  private func updatePreview() {
    guard let source else { return }
    preview = crop.render(source, crop: false)
  }

  private func save() {
    guard saveTask == nil else { return }
    let requested = crop
    let data = attachment.composerSourceData
    saveTask = Task { @MainActor in
      let rendered = await Task.detached(priority: .userInitiated) { requested.derivative(from: data) }.value
      guard !Task.isCancelled else { return }
      saveTask = nil
      guard let rendered, let replacement = attachment.applyingComposerCrop(requested, derivative: rendered),
            onReplace(replacement) else {
        error = t("composer_attachment_save_failed", "Could not save the crop")
        return
      }
      dismiss()
    }
  }

  private func aspectTitle(_ aspect: ComposerAttachmentCrop.Aspect) -> String {
    switch aspect {
    case .free: return t("composer_attachment_free", "Free")
    case .original: return t("composer_attachment_original", "Original")
    case .square: return "1:1"
    case .fourThree: return "4:3"
    case .sixteenNine: return "16:9"
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

private struct ComposerAttachmentDocumentPreview: UIViewControllerRepresentable {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let attachment: GalaxySSIDraftAttachment

  func makeCoordinator() -> Coordinator { Coordinator(attachment) }

  func makeUIViewController(context: Context) -> UIViewController {
    guard context.coordinator.hasPreview else {
      let title = GalaxySSILocalization.string("composer_attachment_preview_unavailable",
        fallback: "Preview unavailable", language: language)
      return UIHostingController(rootView: Text(title).foregroundColor(.secondary))
    }
    let controller = QLPreviewController()
    controller.dataSource = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: UIViewController, context: Context) {}

  static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
    (controller as? QLPreviewController)?.dataSource = nil
    coordinator.cleanup()
  }

  final class Coordinator: NSObject, QLPreviewControllerDataSource {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var file: URL?
    var hasPreview: Bool { file != nil }

    init(_ attachment: GalaxySSIDraftAttachment) {
      super.init()
      let basename = URL(fileURLWithPath: attachment.displayName).lastPathComponent
      guard !basename.isEmpty, basename != ".", basename != "..", basename != "/" else { return }
      let url = directory.appendingPathComponent(basename)
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
          attributes: [.protectionKey: FileProtectionType.complete])
        try attachment.data.write(to: url, options: [.atomic, .completeFileProtection])
        if QLPreviewController.canPreview(url as NSURL) { file = url }
      } catch {
        cleanup()
      }
    }

    deinit { cleanup() }
    func cleanup() { try? FileManager.default.removeItem(at: directory); file = nil }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { file == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
      (file ?? directory) as NSURL
    }
  }
}
