import PDFKit
import SwiftUI
import UIKit
import Vision

enum GalaxySSIHealthPDFText {
  enum Failure: Error { case invalid, locked, incorrectPassword, extractionRestricted, unavailable }
  enum Method: Equatable, Sendable { case native, ocr }
  struct Region: Identifiable, Sendable {
    let id: Int
    let text: String
    let bounds: CGRect
    let highlight: CGRect?
  }

  struct Result: Sendable {
    let method: Method
    let regions: [Region]
    let crop: CGRect
    let rotation: Int
    let preview: CGImage?
  }

  static func pageCount(_ data: Data, password: String? = nil) throws -> Int {
    let document = try open(data, password: password)
    return document.pageCount
  }

  static func read(_ data: Data, page index: Int, forceOCR: Bool = false, password: String? = nil) throws -> Result {
    try Task.checkCancellation()
    let document = try open(data, password: password, extracting: true)
    guard index >= 0, index < document.pageCount, let page = document.page(at: index) else { throw Failure.invalid }
    let crop = page.bounds(for: .cropBox)
    guard !crop.isEmpty, crop.width.isFinite, crop.height.isFinite else { throw Failure.invalid }
    let rendered = page.pageRef.flatMap(render)
    let native = page.selection(for: crop)?.selectionsByLine().prefix(1_000).enumerated().compactMap { index, line -> Region? in
      guard let text = usable(line.string) else { return nil }
      let bounds = line.bounds(for: page).intersection(crop)
      guard !bounds.isEmpty, !bounds.isNull, bounds.width.isFinite, bounds.height.isFinite else { return nil }
      let highlight = rendered.flatMap {
        normalizedTopOrigin(bounds.applying($0.transform), in: $0.viewport)
      }
      return Region(id: index, text: text, bounds: bounds, highlight: highlight)
    } ?? []
    if !forceOCR,
       native.reduce(0, { $0 + $1.text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count }) >= 12 {
      return Result(method: .native, regions: native, crop: crop, rotation: page.rotation, preview: rendered?.image)
    }

    try Task.checkCancellation()
    guard let image = rendered?.image
    else { throw Failure.unavailable }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    let available = try? request.supportedRecognitionLanguages()
    let languages = ["zh-Hans", "en-US"].filter { available?.contains($0) == true }
    if !languages.isEmpty { request.recognitionLanguages = languages }
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    try Task.checkCancellation()
    let regions = (request.results ?? []).prefix(1_000).enumerated().compactMap { index, observation -> Region? in
      guard let text = usable(observation.topCandidates(1).first?.string) else { return nil }
      let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
      return Region(id: index, text: text, bounds: observation.boundingBox,
                    highlight: normalizedTopOrigin(observation.boundingBox, in: unit))
    }
    // Native bounds are PDF page points; OCR bounds are normalized in the rendered crop.
    return Result(method: .ocr, regions: regions, crop: crop, rotation: page.rotation, preview: image)
  }

  static func normalizedTopOrigin(_ bounds: CGRect, in viewport: CGRect) -> CGRect? {
    guard viewport.width > 0, viewport.height > 0, bounds.minX.isFinite, bounds.minY.isFinite,
          bounds.width.isFinite, bounds.height.isFinite else { return nil }
    let visible = bounds.intersection(viewport)
    guard !visible.isEmpty, !visible.isNull else { return nil }
    return CGRect(x: (visible.minX - viewport.minX) / viewport.width,
                  y: (viewport.maxY - visible.maxY) / viewport.height,
                  width: visible.width / viewport.width, height: visible.height / viewport.height)
  }

  private struct Rendered {
    let image: CGImage
    let viewport: CGRect
    let transform: CGAffineTransform
  }

  private static func render(_ page: CGPDFPage) -> Rendered? {
    let box = page.getBoxRect(.cropBox)
    guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { return nil }
    let rotated = abs(page.rotationAngle % 180) == 90
    let sourceWidth = rotated ? box.height : box.width
    let sourceHeight = rotated ? box.width : box.height
    let longest = max(sourceWidth, sourceHeight)
    let width = max(1, Int((sourceWidth / longest * 1_600).rounded()))
    let height = max(1, Int((sourceHeight / longest * 1_600).rounded()))
    let viewport = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    let transform = page.getDrawingTransform(.cropBox, rect: viewport, rotate: 0, preserveAspectRatio: true)
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(viewport)
    context.concatenate(transform)
    context.drawPDFPage(page)
    guard let image = context.makeImage() else { return nil }
    return Rendered(image: image, viewport: viewport, transform: transform)
  }

  static func open(_ data: Data, password: String? = nil, extracting: Bool = false) throws -> PDFDocument {
    guard !data.isEmpty, let document = PDFDocument(data: data) else { throw Failure.invalid }
    if document.isLocked {
      guard let password else { throw Failure.locked }
      guard document.unlock(withPassword: password), !document.isLocked else { throw Failure.incorrectPassword }
    } else if document.isEncrypted, extracting, !document.allowsCopying, let password {
      guard document.unlock(withPassword: password) else { throw Failure.incorrectPassword }
    }
    guard document.pageCount > 0 else { throw Failure.invalid }
    if extracting && !document.allowsCopying { throw Failure.extractionRestricted }
    return document
  }

  private static func usable(_ text: String?) -> String? {
    guard let text else { return nil }
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, !clean.contains("\u{FFFD}"),
          clean.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else { return nil }
    return String(clean.prefix(512))
  }
}

private struct GalaxySSIHealthPDFSourceImage: View {
  let image: CGImage
  let highlight: CGRect?

  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
      let width = CGFloat(image.width) * scale
      let height = CGFloat(image.height) * scale
      ZStack(alignment: .topLeading) {
        Image(uiImage: UIImage(cgImage: image)).resizable().frame(width: width, height: height)
        if let highlight {
          Rectangle().fill(Color.yellow.opacity(0.27))
            .overlay(Rectangle().strokeBorder(Color.orange, lineWidth: 2))
            .frame(width: highlight.width * width, height: highlight.height * height)
            .offset(x: highlight.minX * width, y: highlight.minY * height)
        }
      }
      .frame(width: width, height: height)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityHidden(true)
  }
}

private struct GalaxySSIHealthPDFSourceViewport: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let image: CGImage
  let highlight: CGRect?
  @State private var fullPage = false
  @State private var zoom: CGFloat = 1
  @GestureState private var magnification: CGFloat = 1

  var body: some View {
    let content = displayed()
    NavigationView {
      GeometryReader { geometry in
        let scale = min(geometry.size.width / CGFloat(content.image.width),
                        geometry.size.height / CGFloat(content.image.height)) * min(4, max(1, zoom * magnification))
        ScrollView([.horizontal, .vertical]) {
          GalaxySSIHealthPDFSourceImage(image: content.image, highlight: content.highlight)
            .frame(width: CGFloat(content.image.width) * scale, height: CGFloat(content.image.height) * scale)
        }
        .simultaneousGesture(MagnificationGesture()
          .updating($magnification) { value, state, _ in state = value }
          .onEnded { zoom = min(4, max(1, zoom * $0)) })
      }
      .navigationTitle(t("source", "Original page"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("close_source", "Close")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if highlight != nil {
            Button(fullPage ? t("focused_source", "Focus") : t("full_source", "Full page")) {
              fullPage.toggle()
              zoom = 1
            }
          }
        }
      }
    }
    .navigationViewStyle(.stack)
  }

  private func displayed() -> (image: CGImage, highlight: CGRect?) {
    guard !fullPage, let highlight else { return (image, highlight) }
    let width = CGFloat(image.width), height = CGFloat(image.height)
    let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)
    let hit = CGRect(x: highlight.minX * width, y: highlight.minY * height,
                     width: highlight.width * width, height: highlight.height * height)
    let crop = hit.insetBy(dx: -width * 0.08, dy: -height * 0.09).integral.intersection(imageBounds)
    guard let focused = image.cropping(to: crop) else { return (image, highlight) }
    let box = CGRect(x: (hit.minX - crop.minX) / crop.width, y: (hit.minY - crop.minY) / crop.height,
                     width: hit.width / crop.width, height: hit.height / crop.height)
    return (focused, box)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.pdf_text." + key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthPDFTextView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let store: GalaxySSIHealthOriginalStore
  var transientReport: GalaxySSIHealthTransientReport?
  @State private var files: [GalaxySSIHealthOriginalStore.Original] = []
  @State private var selected: GalaxySSIHealthOriginalStore.Original?
  @State private var page = 0
  @State private var count = 0
  @State private var result: GalaxySSIHealthPDFText.Result?
  @State private var task: Task<Void, Never>?
  @State private var requestID: UUID?
  @State private var status = Status.idle
  @State private var showLimit = 50
  @State private var selectedRegion: Int?
  @State private var focused = false
  var reviewRecords: GalaxySSIHealthRecords?
  @State private var password: String?
  @State private var unlocking = false
  @State private var requestedOCR = false

  private enum Status { case idle, working, unavailable, locked, incorrectPassword, extractionRestricted }

  var body: some View {
    List {
      if scene == .active {
        if let name = transientReport?.name ?? selected?.name {
          Section(name) {
            HStack {
              Button { page -= 1; recognize() } label: {
                Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
              }
              .disabled(page == 0 || status == .working)
              .accessibilityLabel(Text(t("previous", "Previous page")))
              Spacer()
              if count > 0 {
                Text(String(format: t("page", "Page %lld of %lld"), Int64(page + 1), Int64(count)))
              }
              Spacer()
              Button { page += 1; recognize() } label: {
                Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
              }
              .disabled(page >= count - 1 || status == .working)
              .accessibilityLabel(Text(t("next", "Next page")))
            }
            .buttonStyle(.borderless)
            if transientReport == nil {
              Button(t("back", "Choose another PDF")) { clearPassword(); cancel(); self.selected = nil }
            }
          }
          if let result {
            Section(t("source", "Original page")) {
              if let image = result.preview {
                let highlight = result.regions.first(where: { $0.id == selectedRegion })?.highlight
                GalaxySSIHealthPDFSourceImage(image: image, highlight: highlight)
                  .frame(height: 260)
                Button(t("focus", "Open source preview")) { focused = true }
                if selectedRegion != nil && highlight == nil {
                  Text(t("no_location", "Source coordinates unavailable.")).foregroundColor(.secondary)
                }
              } else {
                Text(t("no_preview", "Source preview unavailable.")).foregroundColor(.secondary)
              }
            }
            Section(result.method == .native ? t("native", "PDF text layer") : t("ocr", "On-device OCR")) {
              if result.regions.isEmpty { Text(t("no_text", "No usable text found on this page.")) }
              ForEach(result.regions.prefix(showLimit)) { region in
                Button { selectedRegion = region.id } label: {
                  HStack {
                    Text(region.text).foregroundColor(.primary)
                    Spacer(minLength: 8)
                    if selectedRegion == region.id { Image(systemName: "checkmark.circle.fill") }
                  }
                }
                .accessibilityAddTraits(selectedRegion == region.id ? .isSelected : [])
              }
              if result.regions.count > showLimit { Button(t("more", "Show more")) { showLimit += 50 } }
              if result.method == .native {
                Button(t("force_ocr", "Read again with on-device OCR")) { recognize(forceOCR: true) }
              }
              if let reviewRecords, let selected,
                 let region = result.regions.first(where: { $0.id == selectedRegion }) {
                NavigationLink {
                  GalaxySSIHealthReportItemEditor(records: reviewRecords,
                    source: .init(original: selected.id, sha256: selected.sha256, page: page,
                                  region: region.id, fromOCR: result.method == .ocr),
                    excerpt: String(region.text.prefix(500)))
                } label: {
                  Text(GalaxySSIHealthReportReview.text("item", "Review measurement", language: language))
                }
              }
            }
          }
          if let reviewRecords, let selected {
            NavigationLink {
              GalaxySSIHealthReportEvidenceView(records: reviewRecords, store: store, original: selected)
            } label: {
              Text(GalaxySSIHealthReportReview.text("evidence", "Linked report evidence", language: language))
            }
            NavigationLink {
              GalaxySSIHealthReportBatchView(records: reviewRecords, store: store, original: selected)
            } label: {
              Text(GalaxySSIHealthReportReview.text("batch", "Reviewed measurements", language: language))
            }
          }
        } else {
          Section(t("pdfs", "Saved PDF originals")) {
            if files.isEmpty && status == .idle { Text(t("empty", "No saved PDF originals.")) }
            ForEach(files.prefix(showLimit)) { file in
              Button(file.name) { selected = file; page = 0; count = 0; recognize() }
            }
            if files.count > showLimit { Button(t("more", "Show more")) { showLimit += 50 } }
          }
        }
        switch status {
        case .idle: EmptyView()
        case .working: ProgressView(t("working", "Reading page"))
        case .unavailable:
          Text(t("failed", "The PDF page could not be read."))
          if selected != nil || transientReport != nil { Button(t("retry", "Retry this page")) { recognize() } }
        case .locked, .incorrectPassword, .extractionRestricted:
          Text(passwordStatus)
          Button(t("unlock", "Enter PDF password")) { unlocking = true }
        }
      }
    }
    .navigationTitle(t("title", "Report PDF Text"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear { if status == .working { cancel() } }
    .onDisappear(perform: clearPassword)
    .onDisappear { cancel(); selected = nil; files = [] }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else { clearPassword(); cancel(); selected = nil; files = [] }
    }
    .sheet(isPresented: $focused) {
      if scene == .active, let result, let image = result.preview {
        GalaxySSIHealthPDFSourceViewport(image: image,
          highlight: result.regions.first(where: { $0.id == selectedRegion })?.highlight)
      }
    }
    .sheet(isPresented: $unlocking) {
      if scene == .active {
        GalaxySSIHealthPDFPasswordForm { input in
          unlocking = false
          password = input
          recognize(forceOCR: requestedOCR)
        }
      }
    }
  }

  private var passwordStatus: String {
    switch status {
    case .incorrectPassword: return t("incorrect_password", "The PDF password is incorrect.")
    case .extractionRestricted: return t("extraction_restricted", "This PDF does not permit text extraction.")
    default: return t("locked", "This PDF is password protected.")
    }
  }

  private func clearPassword() {
    password = nil
    unlocking = false
    requestedOCR = false
  }

  private func reload() {
    guard scene == .active else { return }
    if transientReport != nil { recognize(); return }
    do {
      files = try store.list().originals.filter { $0.kind == .pdf }
      status = .idle
    } catch { files = []; status = .unavailable }
  }

  private func recognize(forceOCR: Bool = false) {
    cancel()
    guard scene == .active else { return }
    showLimit = 50
    let data: Data
    do {
      if let transientReport { data = transientReport.pdf }
      else if let selected { data = try store.read(selected) }
      else { return }
    }
    catch { status = .unavailable; return }
    requestedOCR = forceOCR
    let token = UUID(), index = page, credential = password
    requestID = token
    status = .working
    task = Task {
      let worker = Task.detached(priority: .userInitiated) {
        let pages = try GalaxySSIHealthPDFText.pageCount(data, password: credential)
        return (pages, try GalaxySSIHealthPDFText.read(data, page: index, forceOCR: forceOCR, password: credential))
      }
      do {
        let (pages, pageResult) = try await withTaskCancellationHandler(operation: {
          try await worker.value
        }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, requestID == token, scene == .active else { return }
        count = pages
        result = pageResult
        selectedRegion = pageResult.regions.first?.id
        status = .idle
      } catch {
        guard !Task.isCancelled, requestID == token, scene == .active else { return }
        switch error {
        case GalaxySSIHealthPDFText.Failure.locked: status = .locked
        case GalaxySSIHealthPDFText.Failure.incorrectPassword: password = nil; status = .incorrectPassword
        case GalaxySSIHealthPDFText.Failure.extractionRestricted: password = nil; status = .extractionRestricted
        default: status = .unavailable
        }
      }
    }
  }

  private func cancel() {
    requestID = nil
    task?.cancel()
    task = nil
    result = nil
    selectedRegion = nil
    focused = false
    status = .idle
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.pdf_text." + key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthPDFPasswordForm: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var password = ""
  var failed = false
  let submit: (String) -> Void

  var body: some View {
    Form {
      SecureField(t("password", "PDF password"), text: $password)
        .textContentType(.none)
        .autocorrectionDisabled()
      if failed { Text(t("incorrect_password", "The PDF password is incorrect.")).foregroundColor(.secondary) }
      Button(t("unlock", "Enter PDF password")) {
        let entered = password
        password = ""
        submit(entered)
      }.disabled(password.isEmpty || password.utf8.count > 1_024)
      Button(t("close_source", "Close"), role: .cancel) { dismiss() }
    }
    .onDisappear { password = "" }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.pdf_text." + key, fallback: fallback, language: language)
  }
}
