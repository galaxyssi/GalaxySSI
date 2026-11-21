import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

@MainActor
struct GalaxySSIHealthImportView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var app: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let store: GalaxySSIHealthOriginalStore
  let records: GalaxySSIHealthRecords
  enum InitialAction { case none, scan, files }
  var initialAction: InitialAction = .none
  @State private var initialActionStarted = false
  @State private var picking = false
  @State private var scanning = false
  @State private var notice: Notice?
  @State private var retentionDefault: Bool?
  @State private var retentionChoice = GalaxySSIHealthImportRetentionChoice.useDefault
  @State private var fileRetention: Bool?
  @State private var scanRetention: Bool?
  @State private var transientReport: GalaxySSIHealthTransientReport?
  @State private var pendingScanReview: GalaxySSIHealthTransientReport?
  @State private var selectedFiles: GalaxySSIHealthSelectedFiles.Selection?
  @State private var pickerApproval: GalaxySSIHealthReportPickerApproval?
  @State private var choosingAnalysis = false
  @State private var selectionTask: Task<Void, Never>?
  @State private var selectionRun: UUID?

  private enum Notice { case saved, failed }

  var body: some View {
    List {
      if selectionTask != nil {
        Section {
          ProgressView(t("preparing_files", "Preparing selected files"))
          Button(t("cancel", "Cancel"), role: .destructive) { stopSelection() }
        }
      }
      Section(t("report", "Report originals")) {
        NavigationLink {
          GalaxySSIHealthPhotoCaptureView(records: records, originals: store)
        } label: {
          Label(t("photo_collection", "Capture or collect photos"), systemImage: "camera")
        }
        GalaxySSIHealthImportRetentionPicker(currentDefault: retentionDefault, choice: $retentionChoice)
        Button {
          requestFiles()
        } label: {
          Label(t("all_files", "Choose files"), systemImage: "folder")
        }
        if VNDocumentCameraViewController.isSupported {
          Button {
            startScan()
          } label: {
            Label(t("scan", "Scan paper report"), systemImage: "doc.viewfinder")
          }
        }
      }
      Section(t("tables", "Measurement tables")) {
        NavigationLink {
          GalaxySSIHealthTableImportView(records: records, sharedRetentionChoice: $retentionChoice)
        } label: {
          Label(t("choose_table", "Choose CSV, JSON or XLSX"), systemImage: "tablecells")
        }
      }
      Section {
        NavigationLink {
          GalaxySSIHealthRecognitionJobsView(records: records, store: store)
        } label: {
          Label(t("recognition", "Local Report Recognition"), systemImage: "text.viewfinder")
        }
        NavigationLink {
          GalaxySSIHealthOriginalsView(store: store)
        } label: {
          Label(t("library", "Health Originals"), systemImage: "doc.on.doc")
        }
        NavigationLink {
          GalaxySSIHealthPDFTextView(store: store, reviewRecords: records)
        } label: {
          Label(t("read_pdf", "Report PDF Text"), systemImage: "doc.text.magnifyingglass")
        }
      }
      if scene == .active, let notice {
        switch notice {
        case .saved:
          Label(t("saved", "Original available in Health Originals"), systemImage: "checkmark.circle")
        case .failed:
          Text(t("failed", "Could not import the original. Check the file or scan fewer pages."))
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(t("title", "Import Health Data"))
    .galaxySSIHealthTheme()
    .onAppear {
      activate()
    }
    .onChange(of: scene) {
      if $0 == .active { activate() }
      else if $0 == .background {
        stopSelection()
        notice = nil; picking = false; scanning = false; fileRetention = nil; scanRetention = nil
        transientReport = nil; pendingScanReview = nil; selectedFiles = nil; pickerApproval = nil; choosingAnalysis = false
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { notification in
      if scene == .active, notification.object as? String == records.owner { reloadRetention() }
    }
    .onChange(of: app.profile.identityFingerprint) { _ in
      stopSelection()
      selectedFiles = nil; pickerApproval = nil; choosingAnalysis = false; picking = false; fileRetention = nil
    }
    .onDisappear { stopSelection() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
      stopSelection(); selectedFiles = nil; pickerApproval = nil; choosingAnalysis = false
    }
    .confirmationDialog(t("all_files", "Choose files"), isPresented: $choosingAnalysis, titleVisibility: .visible) {
      Button(t("select_analyze", "Choose and recognize report images")) { openPicker(analyze: true) }
      Button(t("select_local", "Choose for local processing only")) { openPicker(analyze: false) }
      Button(t("cancel", "Cancel"), role: .cancel) {
        pickerApproval = nil; fileRetention = nil
        if initialAction == .files { dismiss() }
      }
    } message: {
      Text((pickerApproval?.target.title ?? "") + "\n" + t("picker_disclosure", "Selected report images will be sent once to the paired Desktop, without history, tools or provider fallback. Each image is limited to 100 KB. Missing sampling details are confirmed together locally after all results return. PDF and tables stay local."))
    }
    .fileImporter(isPresented: $picking,
      allowedContentTypes: [.pdf, .image, .commaSeparatedText, .json, .plainText, UTType(filenameExtension: "xlsx") ?? .data],
      allowsMultipleSelection: true) { result in
      defer { fileRetention = nil; pickerApproval = nil }
      guard scene != .background, UIApplication.shared.isProtectedDataAvailable,
            app.profile.identityFingerprint == records.owner, let retainOriginal = fileRetention else { return }
      do {
        let urls = try result.get()
        if let approval = pickerApproval {
          guard approval.matches(owner: records.owner, consent: try .init(records.load()),
            target: coordinator.privateHealthReportCodexTarget()) else { throw GalaxySSIHealthRecords.Failure.stale }
        }
        selectFiles(urls, retainOriginal: retainOriginal, approval: pickerApproval)
      }
      catch {
        let failure = error as NSError
        if failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError {
          if initialAction == .files { dismiss() }
        } else { notice = .failed }
      }
    }
    .sheet(isPresented: $scanning, onDismiss: {
      if scene == .active { transientReport = pendingScanReview }
      pendingScanReview = nil
      scanRetention = nil
    }) {
      GalaxySSIHealthDocumentScanner { result in
        scanning = false
        guard scene != .background, let retainOriginal = scanRetention, let result else { return }
        do {
          let pdf = try result.get()
          let name = "Health-Report-" + String(UUID().uuidString.prefix(8)) + ".pdf"
          if retainOriginal { try store.store(pdf, name: name, acquisition: .camera); notice = .saved }
          else {
            pendingScanReview = try GalaxySSIHealthTransientReport(name: name, data: pdf)
          }
        } catch { notice = .failed }
      }
      .ignoresSafeArea()
    }
    .sheet(item: $transientReport) { report in
      NavigationView {
        GalaxySSIHealthPDFTextView(store: store, transientReport: report)
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("close_review", "Close review")) { transientReport = nil }
          } }
      }
      .navigationViewStyle(.stack)
    }
    .sheet(item: $selectedFiles) { selection in
      NavigationView {
        GalaxySSIHealthSelectedFilesView(records: records, originals: store, selection: selection)
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("close_review", "Close review")) { selectedFiles = nil }
          } }
      }.navigationViewStyle(.stack)
    }
  }

  private func activate() {
    guard scene == .active else { return }
    reloadRetention()
    guard !initialActionStarted else { return }
    initialActionStarted = true
    if initialAction == .scan { startScan() }
    if initialAction == .files { requestFiles() }
  }

  private func requestFiles() {
    guard selectionTask == nil else { return }
    guard app.profile.identityFingerprint == records.owner, UIApplication.shared.isProtectedDataAvailable,
          let retain = beginImport() else { return }
    fileRetention = retain
    if let consent = try? GalaxySSIHealthReportVision.Consent(records.load()),
       let target = coordinator.privateHealthReportCodexTarget() {
      pickerApproval = .init(owner: records.owner, consent: consent, target: target, expires: Date().addingTimeInterval(1800))
      choosingAnalysis = true
    } else { pickerApproval = nil; picking = true }
  }

  private func selectFiles(_ urls: [URL], retainOriginal: Bool, approval: GalaxySSIHealthReportPickerApproval?) {
    guard selectionTask == nil else { return }
    let run = UUID(); selectionRun = run
    selectionTask = Task {
      defer { if selectionRun == run { selectionTask = nil; selectionRun = nil } }
      do {
        let selected = try await GalaxySSIHealthSelectedFiles.readAsync(urls, records: records, originals: store,
          retainOriginal: retainOriginal, approval: approval, active: {
            selectionRun == run && scene != .background && UIApplication.shared.isProtectedDataAvailable &&
              app.profile.identityFingerprint == records.owner
          })
        guard selectionRun == run, !Task.isCancelled else { return }
        selectedFiles = selected
      } catch { if selectionRun == run, !Task.isCancelled { notice = .failed } }
    }
  }

  private func stopSelection() { selectionTask?.cancel(); selectionTask = nil; selectionRun = nil }

  private func openPicker(analyze: Bool) {
    guard scene == .active, app.profile.identityFingerprint == records.owner else { return }
    if !analyze { pickerApproval = nil }
    picking = true
  }

  private func reloadRetention() {
    retentionDefault = (try? records.load())?.keepsNewImportOriginals
  }

  private func beginImport() -> Bool? {
    guard scene == .active else { return nil }
    reloadRetention()
    guard let retain = retentionChoice.resolve(default: retentionDefault) else { return nil }
    retentionChoice = .useDefault
    notice = nil
    return retain
  }

  private func startScan() {
    guard VNDocumentCameraViewController.isSupported else { notice = .failed; return }
    guard let retain = beginImport() else { return }
    scanRetention = retain
    scanning = true
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.import." + key, fallback: fallback, language: language)
  }
}

enum GalaxySSIHealthImportRetentionChoice: Hashable {
  case useDefault, keep, reviewOnly

  func resolve(default currentDefault: Bool?) -> Bool? {
    guard let currentDefault else { return nil }
    switch self {
    case .useDefault: return currentDefault
    case .keep: return true
    case .reviewOnly: return false
    }
  }
}

struct GalaxySSIHealthImportRetentionPicker: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let currentDefault: Bool?
  @Binding var choice: GalaxySSIHealthImportRetentionChoice

  var body: some View {
    if let currentDefault {
      Picker(t("retention_next", "Original for next import"), selection: $choice) {
        Text(currentDefault ? t("default_keep", "Default: keep original")
                            : t("default_review", "Default: do not keep original"))
          .tag(GalaxySSIHealthImportRetentionChoice.useDefault)
        Text(t("keep_once", "Keep this original")).tag(GalaxySSIHealthImportRetentionChoice.keep)
        Text(t("review_once", "Do not keep this original")).tag(GalaxySSIHealthImportRetentionChoice.reviewOnly)
      }
    } else {
      Text(t("retention_unavailable", "Could not read the original retention setting.")).foregroundColor(.secondary)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.import." + key, fallback: fallback, language: language)
  }
}

struct GalaxySSIHealthTransientReport: Identifiable {
  let id = UUID()
  let name: String
  let pdf: Data

  @MainActor
  init(name: String, data: Data) throws {
    guard (1...GalaxySSIHealthOriginalStore.maximumFileBytes).contains(data.count)
    else { throw GalaxySSIHealthOriginalStore.Failure.limit }
    self.name = String(name.prefix(180))
    if data.starts(with: Data("%PDF-".utf8)) { pdf = data; return }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 1_600
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw GalaxySSIHealthOriginalStore.Failure.invalid }
    let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
    pdf = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
      context.beginPage()
      UIImage(cgImage: image).draw(in: bounds)
    }
  }
}

private struct GalaxySSIHealthDocumentScanner: UIViewControllerRepresentable {
  var onResult: (Result<Data, Error>?) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }
  func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let controller = VNDocumentCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }
  func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {
    context.coordinator.onResult = onResult
  }

  @MainActor
  final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    var onResult: (Result<Data, Error>?) -> Void
    init(onResult: @escaping (Result<Data, Error>?) -> Void) { self.onResult = onResult }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onResult(nil) }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
      onResult(.failure(error))
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
      onResult(Result { try makePDF(scan) })
    }

    private func makePDF(_ scan: VNDocumentCameraScan) throws -> Data {
      guard (1...12).contains(scan.pageCount) else { throw GalaxySSIHealthOriginalStore.Failure.limit }
      let page = CGRect(x: 0, y: 0, width: 612, height: 792)
      let renderer = UIGraphicsPDFRenderer(bounds: page)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      var invalid = false
      let data = renderer.pdfData { context in
        for index in 0..<scan.pageCount {
          let image = scan.imageOfPage(at: index)
          guard image.size.width > 0, image.size.height > 0 else { invalid = true; break }
          let downscale = min(1, 1_600 / max(image.size.width, image.size.height))
          let size = CGSize(width: max(1, image.size.width * downscale), height: max(1, image.size.height * downscale))
          let bounded = UIGraphicsImageRenderer(size: size, format: format).image { frame in
            UIColor.white.setFill()
            frame.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
          }
          guard let jpeg = bounded.jpegData(compressionQuality: 0.80), let compressed = UIImage(data: jpeg)
          else { invalid = true; break }
          let fit = min(page.width / size.width, page.height / size.height)
          let target = CGSize(width: size.width * fit, height: size.height * fit)
          context.beginPage()
          compressed.draw(in: CGRect(x: (page.width - target.width) / 2, y: (page.height - target.height) / 2,
                                     width: target.width, height: target.height))
        }
      }
      guard !invalid, !data.isEmpty, data.count <= GalaxySSIHealthOriginalStore.maximumFileBytes
      else { throw GalaxySSIHealthOriginalStore.Failure.limit }
      return data
    }
  }
}
