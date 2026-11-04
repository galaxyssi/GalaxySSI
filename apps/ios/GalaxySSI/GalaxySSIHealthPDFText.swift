import PDFKit
import SwiftUI
import Vision

enum GalaxySSIHealthPDFText {
  enum Failure: Error { case invalid, locked, unavailable }
  enum Method: Equatable, Sendable { case native, ocr }
  struct Region: Identifiable, Sendable {
    let id: Int
    let text: String
    let bounds: CGRect
  }

  struct Result: Sendable {
    let method: Method
    let regions: [Region]
    let crop: CGRect
    let rotation: Int
  }

  static func pageCount(_ data: Data) throws -> Int {
    let document = try open(data)
    return document.pageCount
  }

  static func read(_ data: Data, page index: Int) throws -> Result {
    let document = try open(data)
    guard index >= 0, index < document.pageCount, let page = document.page(at: index) else { throw Failure.invalid }
    let crop = page.bounds(for: .cropBox)
    guard !crop.isEmpty, crop.width.isFinite, crop.height.isFinite else { throw Failure.invalid }
    let native = page.selection(for: crop)?.selectionsByLine().prefix(1_000).enumerated().compactMap { index, line -> Region? in
      guard let text = usable(line.string) else { return nil }
      let bounds = line.bounds(for: page).intersection(crop)
      guard !bounds.isEmpty, !bounds.isNull, bounds.width.isFinite, bounds.height.isFinite else { return nil }
      return Region(id: index, text: text, bounds: bounds)
    } ?? []
    if native.reduce(0, { $0 + $1.text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count }) >= 12 {
      return Result(method: .native, regions: native, crop: crop, rotation: page.rotation)
    }

    try Task.checkCancellation()
    guard let image = page.thumbnail(of: CGSize(width: 1_800, height: 1_800), for: .cropBox).cgImage
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
      return Region(id: index, text: text, bounds: observation.boundingBox)
    }
    // Native bounds are PDF page points; OCR bounds are normalized in the rendered crop.
    return Result(method: .ocr, regions: regions, crop: crop, rotation: page.rotation)
  }

  private static func open(_ data: Data) throws -> PDFDocument {
    guard !data.isEmpty, let document = PDFDocument(data: data) else { throw Failure.invalid }
    guard !document.isLocked else { throw Failure.locked }
    guard document.pageCount > 0 else { throw Failure.invalid }
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

@MainActor
struct GalaxySSIHealthPDFTextView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let store: GalaxySSIHealthOriginalStore
  @State private var files: [GalaxySSIHealthOriginalStore.Original] = []
  @State private var selected: GalaxySSIHealthOriginalStore.Original?
  @State private var page = 0
  @State private var count = 0
  @State private var result: GalaxySSIHealthPDFText.Result?
  @State private var task: Task<Void, Never>?
  @State private var requestID: UUID?
  @State private var status = Status.idle
  @State private var showLimit = 50

  private enum Status { case idle, working, unavailable, locked }

  var body: some View {
    List {
      if scene == .active {
        if let selected {
          Section(selected.name) {
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
            Button(t("back", "Choose another PDF")) { cancel(); self.selected = nil }
          }
          if let result {
            Section(result.method == .native ? t("native", "PDF text layer") : t("ocr", "On-device OCR")) {
              if result.regions.isEmpty { Text(t("no_text", "No usable text found on this page.")) }
              ForEach(result.regions.prefix(showLimit)) { Text($0.text) }
              if result.regions.count > showLimit { Button(t("more", "Show more")) { showLimit += 50 } }
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
        case .unavailable: Text(t("failed", "The PDF page could not be read."))
        case .locked: Text(t("locked", "This PDF is password protected."))
        }
      }
    }
    .navigationTitle(t("title", "Report PDF Text"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear { cancel(); selected = nil; files = [] }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else { cancel(); selected = nil; files = [] }
    }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      files = try store.list().originals.filter { $0.kind == .pdf }
      status = .idle
    } catch { files = []; status = .unavailable }
  }

  private func recognize() {
    cancel()
    guard scene == .active, let selected else { return }
    showLimit = 50
    let data: Data
    do { data = try store.read(selected) }
    catch { status = .unavailable; return }
    let token = UUID(), index = page
    requestID = token
    status = .working
    task = Task {
      let worker = Task.detached(priority: .userInitiated) {
        let pages = try GalaxySSIHealthPDFText.pageCount(data)
        return (pages, try GalaxySSIHealthPDFText.read(data, page: index))
      }
      do {
        let (pages, pageResult) = try await withTaskCancellationHandler(operation: {
          try await worker.value
        }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, requestID == token, scene == .active else { return }
        count = pages
        result = pageResult
        status = .idle
      } catch {
        guard !Task.isCancelled, requestID == token, scene == .active else { return }
        if case GalaxySSIHealthPDFText.Failure.locked = error { status = .locked }
        else { status = .unavailable }
      }
    }
  }

  private func cancel() {
    requestID = nil
    task?.cancel()
    task = nil
    result = nil
    status = .idle
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.pdf_text." + key, fallback: fallback, language: language)
  }
}
