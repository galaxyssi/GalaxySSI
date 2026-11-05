import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

enum GalaxySSIHealthPaperEdges {
  static let fullImage = CGRect(x: 0, y: 0, width: 1, height: 1)

  static func preview(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 1_400,
      kCGImageSourceShouldCacheImmediately: true
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  static func suggestion(_ image: CGImage) throws -> CGRect? {
    try Task.checkCancellation()
    let request = VNDetectRectanglesRequest()
    request.maximumObservations = 4
    request.minimumConfidence = 0.72
    request.minimumAspectRatio = 0.35
    request.minimumSize = 0.30
    request.quadratureTolerance = 23
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    try Task.checkCancellation()
    return (request.results ?? []).sorted {
      $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height
    }.lazy.compactMap { paddedCrop(visionBounds: $0.boundingBox) }.first
  }

  static func paddedCrop(visionBounds: CGRect) -> CGRect? {
    guard visionBounds.minX.isFinite, visionBounds.minY.isFinite,
          visionBounds.width.isFinite, visionBounds.height.isFinite,
          visionBounds.width >= 0.28, visionBounds.height >= 0.28,
          visionBounds.width * visionBounds.height >= 0.20,
          visionBounds.minX >= 0.012, visionBounds.minY >= 0.012,
          visionBounds.maxX <= 0.988, visionBounds.maxY <= 0.988 else { return nil }
    let topOrigin = CGRect(x: visionBounds.minX, y: 1 - visionBounds.maxY,
                           width: visionBounds.width, height: visionBounds.height)
    return topOrigin.insetBy(dx: -0.025, dy: -0.025).intersection(fullImage)
  }
}

enum GalaxySSIHealthCropEncoder {
  struct Output: Sendable {
    let png: Data
    let width: Int
    let height: Int
    let bounds: CGRect
  }

  static func encode(_ data: Data, bounds: CGRect) throws -> Output {
    try Task.checkCancellation()
    guard valid(bounds), let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          (1...12_000).contains(width), (1...12_000).contains(height), width * height <= 24_000_000
    else { throw GalaxySSIHealthOriginalStore.Failure.limit }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(width, height),
      kCGImageSourceShouldCacheImmediately: true
    ]
    guard let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw GalaxySSIHealthOriginalStore.Failure.invalid }
    let w = CGFloat(upright.width), h = CGFloat(upright.height)
    let pixels = CGRect(x: bounds.minX * w, y: bounds.minY * h,
                        width: bounds.width * w, height: bounds.height * h)
      .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
    guard let image = upright.cropping(to: pixels) else { throw GalaxySSIHealthOriginalStore.Failure.invalid }
    try Task.checkCancellation()
    guard let bytes = CFDataCreateMutable(nil, 0),
          let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)
    else { throw GalaxySSIHealthOriginalStore.Failure.invalid }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination), CFDataGetLength(bytes) <= GalaxySSIHealthOriginalStore.maximumFileBytes
    else { throw GalaxySSIHealthOriginalStore.Failure.limit }
    try Task.checkCancellation()
    return Output(png: bytes as Data, width: image.width, height: image.height, bounds: bounds)
  }

  static func valid(_ bounds: CGRect) -> Bool {
    bounds.minX.isFinite && bounds.minY.isFinite && bounds.width.isFinite && bounds.height.isFinite &&
      bounds.width > 0 && bounds.height > 0 && bounds.minX >= 0 && bounds.minY >= 0 &&
      bounds.maxX <= 1.000_001 && bounds.maxY <= 1.000_001
  }
}

@MainActor
struct GalaxySSIHealthReportCropView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let store: GalaxySSIHealthOriginalStore
  @State private var files: [GalaxySSIHealthOriginalStore.Original] = []
  @State private var selected: GalaxySSIHealthOriginalStore.Original?
  @State private var image: CGImage?
  @State private var crop = GalaxySSIHealthPaperEdges.fullImage
  @State private var suggested: CGRect?
  @State private var running = false
  @State private var finished = false
  @State private var error = false
  @State private var modified = false
  @State private var limit = 30
  @State private var task: Task<Void, Never>?
  @State private var token: UUID?
  @State private var saved: GalaxySSIHealthOriginalStore.CropMetadata?
  @State private var saving = false
  @State private var saveFailed = false
  @State private var saveTask: Task<Void, Never>?

  private enum Edge { case left, top, right, bottom }

  var body: some View {
    List {
      if scene == .active {
        if let selected, let image {
          Section(selected.name) {
            picture(image)
            if running { ProgressView(t("searching", "Looking for paper edges")) }
            if finished && suggested == nil {
              Text(t("no_edges", "No clear paper edges found.")).foregroundColor(.secondary)
            }
            if let suggested {
              Button(t("use_edges", "Use suggested bounds")) { modified = true; crop = suggested }
            }
            Button(t("reset", "Reset bounds")) { modified = true; crop = GalaxySSIHealthPaperEdges.fullImage }
          }
          Section(t("bounds", "Crop bounds")) {
            edgeSlider(.left, t("left", "Left"))
            edgeSlider(.top, t("top", "Top"))
            edgeSlider(.right, t("right", "Right"))
            edgeSlider(.bottom, t("bottom", "Bottom"))
          }
          .disabled(saving)
          Button(t("save", "Save encrypted crop"), action: save).disabled(saving || (running && !modified))
          if saving { ProgressView(t("saving", "Saving encrypted crop")) }
          if saveFailed {
            Text(t("save_failed", "Could not save this crop. The original was not changed."))
              .foregroundColor(.secondary)
          } else if let saved, saved.bounds == crop {
            Text(t("saved", "Crop saved on this device") + " · \(saved.width) × \(saved.height)")
              .foregroundColor(.secondary)
          }
          Button(t("choose", "Choose another image")) { clearSelection() }
        } else {
          Section(t("images", "Saved image originals")) {
            if files.isEmpty && !error { Text(t("empty", "No saved image originals.")) }
            ForEach(files.prefix(limit)) { item in Button(item.name) { open(item) } }
            if files.count > limit { Button(t("more", "Show more")) { limit += 30 } }
          }
        }
        if error { Text(t("failed", "The original could not be opened.")).foregroundColor(.secondary) }
      }
    }
    .navigationTitle(t("title", "Report Crop Preview"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear { clearSelection(); files = [] }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else { clearSelection(); files = [] }
    }
  }

  private func picture(_ image: CGImage) -> some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
      let width = CGFloat(image.width) * scale
      let height = CGFloat(image.height) * scale
      ZStack(alignment: .topLeading) {
        Image(uiImage: UIImage(cgImage: image)).resizable().frame(width: width, height: height)
          .accessibilityLabel(Text(selected?.name ?? t("title", "Report Crop Preview")))
        Rectangle().strokeBorder(Color.white, lineWidth: 4)
          .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 2))
          .frame(width: crop.width * width, height: crop.height * height)
          .offset(x: crop.minX * width, y: crop.minY * height)
          .accessibilityHidden(true)
      }
      .frame(width: width, height: height)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(height: 280)
  }

  private func edgeSlider(_ edge: Edge, _ title: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
      Slider(value: Binding(get: { coordinate(edge) }, set: { update(edge, $0) }), in: 0...1, step: 0.01)
        .accessibilityLabel(Text(title))
    }
  }

  private func coordinate(_ edge: Edge) -> Double {
    switch edge {
    case .left: return Double(crop.minX)
    case .top: return Double(crop.minY)
    case .right: return Double(crop.maxX)
    case .bottom: return Double(crop.maxY)
    }
  }

  private func update(_ edge: Edge, _ input: Double) {
    modified = true
    let value = CGFloat(input)
    let span: CGFloat = 0.08
    switch edge {
    case .left:
      let end = crop.maxX
      crop.origin.x = min(value, max(0, end - span))
      crop.size.width = end - crop.minX
    case .top:
      let end = crop.maxY
      crop.origin.y = min(value, max(0, end - span))
      crop.size.height = end - crop.minY
    case .right: crop.size.width = max(crop.minX + span, value) - crop.minX
    case .bottom: crop.size.height = max(crop.minY + span, value) - crop.minY
    }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      try store.recoverInterruptedCrops()
      files = try store.list().originals.filter { $0.kind == .image }
      error = false
    }
    catch { files = []; error = true }
  }

  private func open(_ item: GalaxySSIHealthOriginalStore.Original) {
    guard scene == .active else { return }
    clearSelection()
    error = false
    guard let data = try? store.read(item), let preview = GalaxySSIHealthPaperEdges.preview(data)
    else { error = true; return }
    selected = item
    image = preview
    do {
      saved = try store.readCrop(for: item)?.metadata
      if let saved { crop = saved.bounds; modified = true }
    } catch { saveFailed = true }
    let generation = UUID()
    token = generation
    running = true
    task = Task {
      let worker = Task.detached(priority: .userInitiated) { try GalaxySSIHealthPaperEdges.suggestion(preview) }
      let detected = try? await withTaskCancellationHandler(operation: {
        try await worker.value
      }, onCancel: { worker.cancel() })
      guard !Task.isCancelled, token == generation, scene == .active else { return }
      suggested = detected
      if !modified, let detected { crop = detected }
      running = false
      finished = true
    }
  }

  private func save() {
    guard scene == .active, !saving, let selected, let generation = token else { return }
    let input: Data
    do { input = try store.read(selected) }
    catch { saveFailed = true; return }
    let bounds = crop, revision = saved?.revision
    saving = true
    saveFailed = false
    saveTask = Task {
      let worker = Task.detached(priority: .userInitiated) { try GalaxySSIHealthCropEncoder.encode(input, bounds: bounds) }
      do {
        let output = try await withTaskCancellationHandler(operation: { try await worker.value },
                                                          onCancel: { worker.cancel() })
        guard !Task.isCancelled, token == generation, scene == .active else { return }
        saved = try store.saveCrop(output, for: selected, replacing: revision)
      } catch {
        guard !Task.isCancelled, token == generation, scene == .active else { return }
        saveFailed = true
      }
      saving = false
    }
  }

  private func clearSelection() {
    token = nil
    task?.cancel()
    task = nil
    saveTask?.cancel()
    saveTask = nil
    selected = nil
    image = nil
    suggested = nil
    crop = GalaxySSIHealthPaperEdges.fullImage
    running = false
    finished = false
    modified = false
    saved = nil
    saving = false
    saveFailed = false
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.report_crop." + key, fallback: fallback, language: language)
  }
}
