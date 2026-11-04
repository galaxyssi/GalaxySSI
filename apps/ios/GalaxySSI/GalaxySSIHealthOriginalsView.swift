import ImageIO
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct GalaxySSIHealthOriginalsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let store: GalaxySSIHealthOriginalStore
  @State private var listing: GalaxySSIHealthOriginalStore.Listing?
  @State private var filter = "all"
  @State private var shown = 30
  @State private var selection: Set<UUID> = []
  @State private var preview: Preview?
  @State private var importing = false
  @State private var confirming = false
  @State private var exporting = false
  @State private var zip: OriginalZIP?
  @State private var pending: [GalaxySSIHealthOriginalStore.Original] = []
  @State private var removal: GalaxySSIHealthOriginalStore.Original?
  @State private var error = false

  private struct Preview: Identifiable {
    let id: UUID
    let name: String
    let image: UIImage
  }

  var body: some View {
    List {
      if scene == .active && !exporting {
        Section {
          Button { importing = true } label: { Label(t("import", "Import original"), systemImage: "plus") }
          Picker(t("type", "File type"), selection: $filter) {
            Text(t("all", "All files")).tag("all")
            Text(t("image", "Images")).tag("image")
            Text("PDF").tag("pdf")
          }
          if !selection.isEmpty {
            Button {
              pending = listing?.originals.filter { selection.contains($0.id) } ?? []
              confirming = !pending.isEmpty
            } label: { Label(t("export", "Export selected ZIP"), systemImage: "square.and.arrow.up") }
          }
        }
        if let listing {
          let rows = listing.originals.filter { filter == "all" || $0.kind.rawValue == filter }
          if rows.isEmpty { Text(t("empty", "No originals found")).foregroundColor(.secondary) }
          if listing.unavailable > 0 {
            Text(t("unreadable", "Some encrypted originals could not be opened.")).foregroundColor(.secondary)
          }
          ForEach(rows.prefix(shown)) { item in
            HStack(spacing: 10) {
              Button {
                if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
              } label: {
                Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                  .frame(minWidth: 44, minHeight: 44)
              }
              .accessibilityLabel(Text(selection.contains(item.id) ? t("unselect", "Deselect file") : t("select", "Select file")))
              Button { open(item) } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(item.name).foregroundColor(.primary)
                  Text(item.importedAt, style: .date).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            .buttonStyle(.borderless)
            .swipeActions {
              Button(role: .destructive) { removal = item } label: {
                Label(t("remove", "Remove"), systemImage: "trash")
              }
            }
          }
          if rows.count > shown { Button(t("more", "Show more")) { shown += 30 } }
        }
        if error {
          Text(t("error", "Could not complete the operation. Check the file or select fewer originals."))
            .foregroundColor(.secondary)
          Button(t("retry", "Reload originals"), action: reload)
        }
      }
    }
    .navigationTitle(t("title", "Health Originals"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: filter) { _ in shown = 30 }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else {
        listing = nil
        preview = nil
        removal = nil
        pending = []
        confirming = false
        if !exporting { zip = nil }
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf]) { result in
      guard scene == .active else { return }
      do { try store.importFile(result.get()); reload() }
      catch { error = true }
    }
    .confirmationDialog(t("plain_zip", "Save an unencrypted ZIP of these originals?"),
                        isPresented: $confirming, titleVisibility: .visible) {
      Button(t("save", "Choose save location"), action: export)
    } message: {
      Text(String(format: t("selected_count", "%lld selected originals"), Int64(pending.count)))
    }
    .alert(item: $removal) { item in
      Alert(title: Text(t("remove_confirm", "Remove this original?")), message: Text(item.name),
            primaryButton: .destructive(Text(t("remove", "Remove"))) {
              guard scene == .active else { return }
              do { try store.remove(item); reload() } catch { error = true }
            }, secondaryButton: .cancel())
    }
    .fileExporter(isPresented: $exporting, document: zip, contentType: .zip,
                  defaultFilename: "GalaxySSI-Health-Originals") { result in
      zip = nil
      if case .failure = result { error = true }
    }
    .onChange(of: exporting) { if !$0 { zip = nil } }
    .sheet(item: $preview) { item in
      VStack {
        HStack {
          Text(item.name).font(.headline)
          Spacer()
          Button { preview = nil } label: { Image(systemName: "xmark.circle").font(.title2) }
            .accessibilityLabel(Text(t("close", "Close")))
        }
        Image(uiImage: item.image).resizable().scaledToFit().accessibilityLabel(Text(item.name))
      }.padding()
    }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      let current = try store.list()
      listing = current
      selection.formIntersection(current.originals.map(\.id))
      error = false
    } catch { listing = nil; error = true }
  }

  private func open(_ item: GalaxySSIHealthOriginalStore.Original) {
    guard scene == .active else { return }
    do {
      let data = try store.read(item)
      let image: UIImage?
      if item.kind == .pdf {
        image = PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: CGSize(width: 1_200, height: 1_200), for: .cropBox)
      } else if let source = CGImageSourceCreateWithData(data as CFData, nil) {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: 1_200]
        image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
      } else { image = nil }
      guard let image else { error = true; return }
      preview = Preview(id: item.id, name: item.name, image: image)
    } catch { error = true }
  }

  private func export() {
    guard scene == .active else { return }
    let selected = pending
    pending = []
    do { zip = OriginalZIP(data: try store.makeZIP(selected)); exporting = true }
    catch { error = true }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.originals." + key, fallback: fallback, language: language)
  }
}

private struct OriginalZIP: FileDocument {
  static var readableContentTypes: [UTType] { [.zip] }
  let data: Data

  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    self.data = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
