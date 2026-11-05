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
  @State private var picking = false
  @State private var scanning = false
  @State private var notice: Notice?

  private enum Notice { case saved, failed }

  var body: some View {
    List {
      Section(t("report", "Report originals")) {
        Button {
          notice = nil
          picking = true
        } label: {
          Label(t("files", "Choose PDF or image"), systemImage: "folder")
        }
        if VNDocumentCameraViewController.isSupported {
          Button {
            notice = nil
            scanning = true
          } label: {
            Label(t("scan", "Scan paper report"), systemImage: "doc.viewfinder")
          }
        }
      }
      Section(t("tables", "Measurement tables")) {
        NavigationLink {
          GalaxySSIHealthTableImportView(records: records)
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
    .onChange(of: scene) { if $0 == .background { notice = nil; scanning = false } }
    .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image]) { result in
      guard scene != .background else { return }
      do { try store.importFile(result.get()); notice = .saved }
      catch { notice = .failed }
    }
    .sheet(isPresented: $scanning) {
      GalaxySSIHealthDocumentScanner { result in
        scanning = false
        guard scene != .background, let result else { return }
        do {
          let pdf = try result.get()
          try store.store(pdf, name: "Health-Report-" + String(UUID().uuidString.prefix(8)) + ".pdf")
          notice = .saved
        } catch { notice = .failed }
      }
      .ignoresSafeArea()
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.import." + key, fallback: fallback, language: language)
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
