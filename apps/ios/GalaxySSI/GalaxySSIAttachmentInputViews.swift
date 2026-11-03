import PhotosUI
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AttachmentPreviewStrip: View {
  var attachments: [GalaxySSIDraftAttachment]
  var onRemove: (GalaxySSIDraftAttachment) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(attachments) { attachment in
            AttachmentPreviewChip(attachment: attachment) {
              onRemove(attachment)
            }
            .id(attachment.id)
          }
        }
        .frame(height: 74, alignment: .center)
        .padding(.top, 8)
      }
      .frame(height: 82, alignment: .top)
      .onAppear {
        scrollToLatest(using: proxy)
      }
      .onChange(of: attachments.map(\.id)) { _ in
        scrollToLatest(using: proxy)
      }
    }
  }

  private func scrollToLatest(using proxy: ScrollViewProxy) {
    guard let latestID = attachments.last?.id else { return }
    DispatchQueue.main.async {
      proxy.scrollTo(latestID, anchor: .trailing)
    }
  }
}

struct AttachmentPreviewChip: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var attachment: GalaxySSIDraftAttachment
  var onRemove: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      if attachment.isImage {
        thumbnail
          .frame(width: 70, height: 66)
      } else {
        HStack(spacing: 8) {
          thumbnail
          VStack(alignment: .leading, spacing: 2) {
            Text(attachment.displayName)
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(.galaxySSITextPrimary)
              .lineLimit(1)
              .truncationMode(.middle)
            Text(attachment.humanSize)
              .font(.system(size: 11))
              .foregroundColor(.galaxySSITextSecondary)
          }
          Spacer(minLength: 22)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(width: 190, height: 66)
      }
      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
          .background(Circle().fill(Color.galaxySSISurface.opacity(0.88)))
      }
      .padding(5)
      .accessibilityLabel(Text(t("agent_attachment_remove", "Remove attachment")))
    }
    .background(Color.galaxySSISearchBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.galaxySSISeparator, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  @ViewBuilder
  private var thumbnail: some View {
    if attachment.isImage,
       let image = UIImage(data: attachment.data) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .clipped()
    } else {
      Image(systemName: "doc")
        .font(.system(size: 22, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
        .frame(width: 34, height: 34)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIAttachmentMenuRow: View {
  var title: String
  var systemImage: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .frame(width: 28)
        Text(title)
          .font(.system(size: 17, weight: .regular))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 22)
      .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }
    .buttonStyle(.plain)
  }
}

struct GalaxySSIAttachmentMenuDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.galaxySSISeparator)
      .frame(height: 1)
      .padding(.leading, 62)
  }
}

struct PhotoLibraryPickerView: UIViewControllerRepresentable {
  var selectionLimit = GalaxySSIAttachmentPayloadBuilder.maximumAttachmentCount
  var dismissOnSelection = true
  var onFailure: () -> Void = {}
  var onCancel: () -> Void = {}
  var onAttachment: (GalaxySSIDraftAttachment) -> Void

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = max(1, min(selectionLimit, GalaxySSIAttachmentPayloadBuilder.maximumAttachmentCount))
    let controller = PHPickerViewController(configuration: configuration)
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(dismissOnSelection: dismissOnSelection, onFailure: onFailure, onCancel: onCancel,
      onAttachment: onAttachment)
  }

  static func dismantleUIViewController(_ controller: PHPickerViewController, coordinator: Coordinator) {
    coordinator.invalidateEmbeddedPicker()
  }

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    private let onAttachment: (GalaxySSIDraftAttachment) -> Void
    private let dismissOnSelection: Bool
    private let onFailure: () -> Void
    private let onCancel: () -> Void
    private var acceptingResults = true

    init(dismissOnSelection: Bool, onFailure: @escaping () -> Void, onCancel: @escaping () -> Void,
         onAttachment: @escaping (GalaxySSIDraftAttachment) -> Void) {
      self.dismissOnSelection = dismissOnSelection
      self.onFailure = onFailure
      self.onCancel = onCancel
      self.onAttachment = onAttachment
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      if results.isEmpty {
        acceptingResults = false
        onCancel()
        if dismissOnSelection { picker.dismiss(animated: true) }
        return
      }
      if dismissOnSelection { picker.dismiss(animated: true) }
      results.forEach { result in
        let provider = result.itemProvider
        let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
          UTType(identifier)?.conforms(to: .image) == true
        } ?? UTType.image.identifier
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
          guard let data, !data.isEmpty, data.count <= 64 * 1024 * 1024 else {
            DispatchQueue.main.async { if self.acceptingResults { self.onFailure() } }
            return
          }
          let name = provider.suggestedName.map { "\($0).jpg" } ?? "photo.jpg"
          let attachment = GalaxySSIAttachmentPayloadBuilder.makePhotoAttachment(
            data: data,
            suggestedName: name
          )
          DispatchQueue.main.async {
            if self.acceptingResults { self.onAttachment(attachment) }
          }
        }
      }
    }

    func invalidateEmbeddedPicker() {
      // Ordinary pickers finish loading after their automatic dismissal.
      if !dismissOnSelection { acceptingResults = false }
    }
  }
}

extension AgentHomeView {
  @ViewBuilder
  var screenAssistantRestoreControl: some View {
    if screenAssistantLauncherVisible {
      GalaxySSIScreenAssistantBubble(
        restoreLabel: t("galaxyssi.screen_assistant.restore", "Restore screen assistant"),
        closeLabel: t("galaxyssi.screen_assistant.close", "Close screen assistant"),
        stopLabel: t("galaxyssi.screen_assistant.stop", "Stop analysis"),
        phase: screenAssistantConversationID == store.activeAgentConversationId ? screenAssistantBubblePhase : nil,
        statusLabel: screenAssistantConversationID == store.activeAgentConversationId
          ? screenAssistantBubbleStatusLabel : t("galaxyssi.screen_assistant.ready", "Ready"),
        onRestore: restoreScreenAssistantPresentation,
        onClose: {
          store.updateDisplaySettings { $0.screenAssistantEnabled = false }
        },
        onStop: screenAssistantRunID == nil || screenAssistantStopping ||
          screenAssistantConversationID != store.activeAgentConversationId ? nil : { stopScreenAnalysis() }
      )
    }
  }

  var screenAssistantBubbleStatusLabel: String {
    switch screenAssistantBubblePhase {
    case nil: return t("galaxyssi.screen_assistant.ready", "Ready")
    case .completed?: return t("galaxyssi.screen_assistant.completed", "Completed")
    case .observing?, .planning?, .executing?, .verifying?, .waitingResponse?:
      return t("galaxyssi.screen_assistant.processing", "Processing")
    default: return t("galaxyssi.screen_assistant.attention", "Needs attention")
    }
  }

  var screenAssistantControls: some View {
    HStack(spacing: 12) {
      Label(t("galaxyssi.screen_assistant.title", "Screen assistant"), systemImage: "viewfinder")
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
      Spacer(minLength: 0)
      if screenAssistantRunID != nil || screenAssistantStopping {
        Button(action: stopScreenAnalysis) {
          Image(systemName: "stop.circle").frame(width: 44, height: 44)
        }
        .disabled(screenAssistantStopping)
        .accessibilityLabel(t("galaxyssi.screen_assistant.stop", "Stop analysis"))
        .accessibilityIdentifier("ios.screen-assistant.stop")
      }
      Button {
        screenAssistantCompact.toggle()
      } label: {
        Image(systemName: screenAssistantCompact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel(screenAssistantCompact
        ? t("galaxyssi.screen_assistant.expand", "Expand result")
        : t("galaxyssi.screen_assistant.compact", "Compact result"))
      .accessibilityIdentifier("ios.screen-assistant.resize")
      Button {
        screenAssistantCollapsed = true
      } label: {
        Image(systemName: "minus").frame(width: 44, height: 44)
      }
      .accessibilityLabel(t("galaxyssi.screen_assistant.collapse", "Collapse screen assistant"))
      .accessibilityIdentifier("ios.screen-assistant.close")
    }
    .buttonStyle(.plain)
    .padding(.leading, 16)
    .padding(.trailing, 4)
    .foregroundColor(.galaxySSITextPrimary)
    .background(Color.galaxySSIPageBackground)
  }
}

struct GalaxySSIScreenAssistantBubble: View {
  static let visibleDiameter: CGFloat = 46.4
  static let touchDiameter: CGFloat = 48
  @SceneStorage("galaxyssi.screenAssistant.bubble.x") private var positionX = 0.9
  @SceneStorage("galaxyssi.screenAssistant.bubble.y") private var positionY = 0.7
  @GestureState private var translation = CGSize.zero
  @State private var menuPresented = false
  @State private var screenCaptured = UIScreen.main.isCaptured
  var restoreLabel: String
  var closeLabel: String
  var stopLabel: String
  var phase: AgentPhase?
  var statusLabel: String
  var onRestore: () -> Void
  var onClose: () -> Void
  var onStop: (() -> Void)? = nil

  var body: some View {
    Group {
      if !screenCaptured { bubbleLayer }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
      screenCaptured = UIScreen.main.isCaptured
      if screenCaptured { menuPresented = false }
    }
  }

  private var bubbleLayer: some View {
    GeometryReader { geometry in
      let anchor = Self.center(x: positionX, y: positionY, in: geometry.size)
      let current = Self.clamp(CGPoint(x: anchor.x + translation.width,
        y: anchor.y + translation.height), in: geometry.size)
      ZStack(alignment: .topLeading) {
        if menuPresented {
          Color.clear.contentShape(Rectangle())
            .onTapGesture { menuPresented = false }
          let rect = Self.menuRect(near: current, in: geometry.size, rows: onStop == nil ? 2 : 3)
          ScrollView {
            VStack(spacing: 0) {
              menuAction(restoreLabel, symbol: "arrow.up.left.and.arrow.down.right", action: onRestore)
              if let onStop { menuAction(stopLabel, symbol: "stop.circle", action: onStop) }
              menuAction(closeLabel, symbol: "xmark", action: onClose)
            }
          }
          .frame(width: rect.width, height: rect.height)
          .background(Color.galaxySSISurface)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.galaxySSITextSecondary.opacity(0.2)))
          .position(x: rect.midX, y: rect.midY)
          .accessibilityIdentifier("ios.screen-assistant.menu")
        }
      Button {
        menuPresented = false
        onRestore()
      } label: {
        ZStack {
          Circle().fill(Color(red: 85 / 255, green: 89 / 255, blue: 94 / 255))
            .overlay(Circle().stroke(Color(red: 133 / 255, green: 137 / 255, blue: 141 / 255), lineWidth: 0.696))
            .frame(width: 45.472, height: 45.472)
          Circle().fill(Color(red: 128 / 255, green: 132 / 255, blue: 135 / 255))
            .frame(width: 32.48, height: 32.48)
          Circle().fill(Color(red: 173 / 255, green: 176 / 255, blue: 179 / 255))
            .frame(width: 25.984, height: 25.984)
          Circle().fill(Color(red: 250 / 255, green: 251 / 255, blue: 252 / 255))
            .frame(width: 19.488, height: 19.488)
        }
        .frame(width: Self.visibleDiameter, height: Self.visibleDiameter)
        .frame(width: Self.touchDiameter, height: Self.touchDiameter)
        .overlay(alignment: .topTrailing) {
          if let rgb = Self.badgeRGB(for: phase) {
            Circle().fill(Color(red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255))
              .overlay(Circle().stroke(Color.white, lineWidth: 1))
              .frame(width: 9.6, height: 9.6)
              .padding(2)
          }
        }
        .opacity(0.5)
        .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(restoreLabel)
      .accessibilityValue(statusLabel)
      .accessibilityIdentifier("ios.screen-assistant.bubble")
      .help(restoreLabel)
      .onLongPressGesture { menuPresented.toggle() }
      .accessibilityAction(named: Text(closeLabel)) { menuPresented = false; onClose() }
      .accessibilityAction(named: Text(stopLabel)) { menuPresented = false; onStop?() }
      .highPriorityGesture(DragGesture(minimumDistance: 4)
        .updating($translation) { value, state, _ in state = value.translation }
        .onEnded { value in
          let end = Self.clamp(CGPoint(x: anchor.x + value.translation.width,
            y: anchor.y + value.translation.height), in: geometry.size)
          positionX = Double(end.x / max(geometry.size.width, 1))
          positionY = Double(end.y / max(geometry.size.height, 1))
        })
      .position(current)
      .zIndex(1)
      }
      .onChange(of: geometry.size) { _ in menuPresented = false }
    }
  }

  private func menuAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button {
      menuPresented = false
      action()
    } label: {
      Label(title, systemImage: symbol)
        .font(.system(size: 14))
        .foregroundColor(.galaxySSITextPrimary)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 12)
    }
    .buttonStyle(.plain)
  }

  static func menuRect(near point: CGPoint, in size: CGSize, rows: Int) -> CGRect {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return .zero }
    let center = clamp(point, in: size)
    let half = touchDiameter / 2
    let gap: CGFloat = 8
    let width = min(CGFloat(235), size.width)
    var height = min(CGFloat(max(1, rows)) * 48, size.height)
    let left = center.x - half - gap - width
    let right = center.x + half + gap
    let x: CGFloat
    let y: CGFloat
    if left >= 0 {
      x = left
      y = min(max(0, center.y - height / 2), size.height - height)
    } else if right + width <= size.width {
      x = right
      y = min(max(0, center.y - height / 2), size.height - height)
    } else {
      x = min(max(0, center.x - width / 2), size.width - width)
      let above = max(0, center.y - half - gap)
      let below = max(0, size.height - center.y - half - gap)
      if above >= height || above >= below {
        height = min(height, above)
        y = above - height
      } else {
        height = min(height, below)
        y = size.height - below
      }
    }
    return CGRect(x: x, y: y, width: width, height: height)
  }

  static func center(x: Double, y: Double, in size: CGSize) -> CGPoint {
    clamp(CGPoint(x: (x.isFinite ? x : 0.9) * Double(size.width),
      y: (y.isFinite ? y : 0.7) * Double(size.height)), in: size)
  }

  static func badgeRGB(for phase: AgentPhase?) -> UInt32? {
    guard let phase else { return nil }
    switch phase {
    case .completed: return 0x169F75
    case .observing, .planning, .executing, .verifying, .waitingResponse: return 0xE2A430
    case .waitingConfirmation, .paused, .blocked, .cancelled, .failed: return 0xD95353
    }
  }

  static func clamp(_ point: CGPoint, in size: CGSize) -> CGPoint {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return .zero }
    let halfWidth = min(touchDiameter / 2, size.width / 2)
    let halfHeight = min(touchDiameter / 2, size.height / 2)
    return CGPoint(x: min(max(point.x.isFinite ? point.x : halfWidth, halfWidth), size.width - halfWidth),
      y: min(max(point.y.isFinite ? point.y : halfHeight, halfHeight), size.height - halfHeight))
  }
}

struct GalaxySSIScreenshotInputView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var attachment: GalaxySSIDraftAttachment?
  @State private var preview: UIImage?
  @State private var selection: CGRect?
  @State private var failed = false
  @State private var acceptingResults = false
  var onAttachment: (GalaxySSIDraftAttachment) -> Void

  var body: some View {
    NavigationView {
      Group {
        if let preview {
          GeometryReader { geometry in
            let scale = min(geometry.size.width / preview.size.width, geometry.size.height / preview.size.height)
            let size = CGSize(width: preview.size.width * scale, height: preview.size.height * scale)
            Image(uiImage: preview).resizable().frame(width: size.width, height: size.height)
              .overlay {
                if let selection {
                  Rectangle().fill(Color.black.opacity(0.12))
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: selection.width * size.width, height: selection.height * size.height)
                    .position(x: selection.midX * size.width, y: selection.midY * size.height)
                }
              }
              .contentShape(Rectangle())
              .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                selection = Self.cropSelection(from: value.startLocation, to: value.location, size: size)
              })
              .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
          }
          .padding(12)
        } else {
          PhotoLibraryPickerView(selectionLimit: 1, dismissOnSelection: false,
            onFailure: { if acceptingResults { failed = true } }, onCancel: close) { selected in
            guard acceptingResults else { return }
            guard selected.data.count <= 64 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(selected.data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096
                  ] as CFDictionary) else { failed = true; return }
            attachment = selected
            preview = UIImage(cgImage: image)
          }
        }
      }
      .navigationTitle(t("galaxyssi.screen_assistant.analyze", "Analyze screenshot"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.cancel", "Cancel"), action: close)
        }
        ToolbarItemGroup(placement: .confirmationAction) {
          if preview != nil {
            Button { selection = nil } label: { Image(systemName: "arrow.counterclockwise") }
              .accessibilityLabel(t("galaxyssi.screen_assistant.reset_crop", "Reset crop"))
            Button(action: confirm) { Image(systemName: "checkmark") }
              .accessibilityLabel(t("galaxyssi.screen_assistant.use_image", "Use image"))
          }
        }
      }
      .alert(t("galaxyssi.screen_assistant.image_error", "Image could not be prepared"), isPresented: $failed) {
        Button(t("galaxyssi.common.done", "Done"), role: .cancel) {}
      }
    }
    .navigationViewStyle(.stack)
    .onAppear { acceptingResults = true }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in close() }
    .onDisappear { acceptingResults = false; attachment = nil; preview = nil; selection = nil }
  }

  private func close() {
    acceptingResults = false
    attachment = nil
    preview = nil
    selection = nil
    dismiss()
  }

  static func cropSelection(from start: CGPoint, to end: CGPoint, size: CGSize) -> CGRect? {
    guard size.width > 0, size.height > 0 else { return nil }
    let x1 = min(max(start.x / size.width, 0), 1)
    let x2 = min(max(end.x / size.width, 0), 1)
    let y1 = min(max(start.y / size.height, 0), 1)
    let y2 = min(max(end.y / size.height, 0), 1)
    guard abs(x2 - x1) * size.width >= 4, abs(y2 - y1) * size.height >= 4 else { return nil }
    return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
  }

  private func confirm() {
    guard acceptingResults, let attachment else { return }
    if let selection, let source = preview?.cgImage {
      let rect = CGRect(x: selection.minX * CGFloat(source.width), y: selection.minY * CGFloat(source.height),
        width: selection.width * CGFloat(source.width), height: selection.height * CGFloat(source.height)).integral
      guard let cropped = source.cropping(to: rect), let data = UIImage(cgImage: cropped).pngData() else {
        failed = true; return
      }
      onAttachment(GalaxySSIAttachmentPayloadBuilder.makePhotoAttachment(data: data,
        suggestedName: "screenshot-crop.png", sourceDescription: "screenshot-crop"))
    } else {
      onAttachment(attachment)
    }
    close()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

struct CameraAttachmentPickerView: UIViewControllerRepresentable {
  var onAttachment: (GalaxySSIDraftAttachment) -> Void
  var onCancel: () -> Void = {}

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let controller = UIImagePickerController()
    controller.sourceType = .camera
    controller.cameraCaptureMode = .photo
    controller.modalPresentationStyle = .fullScreen
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onAttachment: onAttachment, onCancel: onCancel)
  }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let onAttachment: (GalaxySSIDraftAttachment) -> Void
    private let onCancel: () -> Void

    init(
      onAttachment: @escaping (GalaxySSIDraftAttachment) -> Void,
      onCancel: @escaping () -> Void
    ) {
      self.onAttachment = onAttachment
      self.onCancel = onCancel
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      defer { picker.dismiss(animated: true) }
      guard let image = info[.originalImage] as? UIImage,
            let data = image.jpegData(compressionQuality: 0.9) else {
        onCancel()
        return
      }
      let attachment = GalaxySSIAttachmentPayloadBuilder.makePhotoAttachment(
        data: data,
        suggestedName: "galaxyssi_\(Int(Date().timeIntervalSince1970)).jpg",
        sourceDescription: "camera"
      )
      onAttachment(attachment)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onCancel()
      picker.dismiss(animated: true)
    }
  }
}
