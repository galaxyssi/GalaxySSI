import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

@MainActor
struct GalaxySSIHealthImportView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let store: GalaxySSIHealthOriginalStore
  let records: GalaxySSIHealthRecords
  enum InitialAction { case none, scan }
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

  private enum Notice { case saved, failed }

  var body: some View {
    List {
      Section(t("report", "Report originals")) {
        GalaxySSIHealthImportRetentionPicker(currentDefault: retentionDefault, choice: $retentionChoice)
        Button {
          guard let retain = beginImport() else { return }
          fileRetention = retain
          picking = true
        } label: {
          Label(t("files", "Choose PDF or image"), systemImage: "folder")
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
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      activate()
    }
    .onChange(of: scene) {
      if $0 == .active { activate() }
      else if $0 == .background {
        notice = nil; picking = false; scanning = false; fileRetention = nil; scanRetention = nil
        transientReport = nil; pendingScanReview = nil
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { notification in
      if scene == .active, notification.object as? String == records.owner { reloadRetention() }
    }
    .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image]) { result in
      defer { fileRetention = nil }
      guard scene != .background, let retainOriginal = fileRetention else { return }
      do {
        let url = try result.get()
        if retainOriginal { try store.importFile(url); notice = .saved }
        else {
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          let handle = try FileHandle(forReadingFrom: url)
          defer { try? handle.close() }
          let data = try handle.read(upToCount: GalaxySSIHealthOriginalStore.maximumFileBytes + 1) ?? Data()
          transientReport = try GalaxySSIHealthTransientReport(name: url.lastPathComponent, data: data)
        }
      }
      catch { notice = .failed }
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
  }

  private func activate() {
    guard scene == .active else { return }
    reloadRetention()
    guard !initialActionStarted else { return }
    initialActionStarted = true
    if initialAction == .scan { startScan() }
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
