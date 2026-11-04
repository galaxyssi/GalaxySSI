import ImageIO
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct GalaxySSIHealthOriginalsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let store: GalaxySSIHealthOriginalStore
  @State private var listing: GalaxySSIHealthOriginalStore.Listing?
  @State private var filter = "all"
  @State private var recentDays = 0
  @State private var grid = false
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
    var image: UIImage?
    var pdf: PDFDocument?
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
          Picker(t("date_filter", "Import date"), selection: $recentDays) {
            Text(t("any_date", "Any date")).tag(0)
            Text(t("last_week", "Last 7 days")).tag(7)
            Text(t("last_month", "Last 30 days")).tag(30)
          }
          Picker(t("layout", "Layout"), selection: $grid) {
            Image(systemName: "list.bullet").accessibilityLabel(Text(t("list", "List"))).tag(false)
            Image(systemName: "square.grid.2x2").accessibilityLabel(Text(t("grid", "Thumbnails"))).tag(true)
          }
          .pickerStyle(.segmented)
          if !selection.isEmpty {
            Button {
              pending = listing?.originals.filter { selection.contains($0.id) } ?? []
              confirming = !pending.isEmpty
            } label: { Label(t("export", "Export selected ZIP"), systemImage: "square.and.arrow.up") }
          }
        }
        if let listing {
          let rows = filtered(listing.originals)
          if rows.isEmpty { Text(t("empty", "No originals found")).foregroundColor(.secondary) }
          if listing.unavailable > 0 {
            Text(t("unreadable", "Some encrypted originals could not be opened.")).foregroundColor(.secondary)
          }
          if grid {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 16) {
              ForEach(rows.prefix(shown)) { item in thumbnailTile(item) }
            }
          } else {
            ForEach(rows.prefix(shown)) { item in
              HStack(spacing: 10) {
                selectButton(item)
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
    .onChange(of: recentDays) { _ in shown = 30 }
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
      if scene == .active {
        VStack {
        HStack {
          Text(item.name).font(.headline).lineLimit(2).truncationMode(.middle)
          Spacer()
          Button { preview = nil } label: { Image(systemName: "xmark.circle").font(.title2) }
            .accessibilityLabel(Text(t("close", "Close")))
        }
        if let pdf = item.pdf {
          PDFPages(document: pdf, name: item.name)
        } else if let image = item.image {
          Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(Text(item.name))
        }
        }.padding()
      }
    }
  }

  private func filtered(_ originals: [GalaxySSIHealthOriginalStore.Original]) -> [GalaxySSIHealthOriginalStore.Original] {
    var local = calendar
    local.timeZone = timeZone
    let cutoff = recentDays == 0 ? Date.distantPast :
      (local.date(byAdding: .day, value: 1 - recentDays, to: local.startOfDay(for: Date())) ?? .distantPast)
    return originals.filter { $0.importedAt >= cutoff && (filter == "all" || $0.kind.rawValue == filter) }
  }

  private func selectButton(_ item: GalaxySSIHealthOriginalStore.Original) -> some View {
    Button {
      if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    } label: {
      Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
        .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(Text(selection.contains(item.id) ? t("unselect", "Deselect file") : t("select", "Select file")))
  }

  private func thumbnailTile(_ item: GalaxySSIHealthOriginalStore.Original) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Button { open(item) } label: {
        OriginalThumbnail(store: store, item: item)
          .frame(height: 92).frame(maxWidth: .infinity)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(item.name))
      HStack(spacing: 0) {
        Text(item.name).font(.caption).lineLimit(2).truncationMode(.middle)
        Spacer(minLength: 0)
        selectButton(item)
      }
    }
    .contextMenu {
      Button(role: .destructive) { removal = item } label: { Label(t("remove", "Remove"), systemImage: "trash") }
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
      if item.kind == .pdf {
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { error = true; return }
        preview = Preview(id: item.id, name: item.name, pdf: pdf)
      } else {
        guard let image = Self.thumbnail(data, maximum: 1_200) else { error = true; return }
        preview = Preview(id: item.id, name: item.name, image: image)
      }
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

  private static func thumbnail(_ data: Data, maximum: Int) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                   kCGImageSourceCreateThumbnailWithTransform: true,
                                   kCGImageSourceThumbnailMaxPixelSize: maximum]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
  }

  private struct OriginalThumbnail: View {
    @Environment(\.scenePhase) private var scene
    let store: GalaxySSIHealthOriginalStore
    let item: GalaxySSIHealthOriginalStore.Original
    @State private var image: UIImage?

    var body: some View {
      ZStack {
        Color.secondary.opacity(0.08)
        if let image {
          Image(uiImage: image).resizable().scaledToFit()
        } else {
          Image(systemName: item.kind == .pdf ? "doc.richtext" : "photo")
        }
      }
      .clipped()
      .accessibilityHidden(true)
      .task(id: item.id) { @MainActor in
        guard scene == .active, !Task.isCancelled, let data = try? store.read(item) else { return }
        if item.kind == .pdf {
          image = PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: CGSize(width: 240, height: 240), for: .cropBox)
        } else {
          image = GalaxySSIHealthOriginalsView.thumbnail(data, maximum: 240)
        }
      }
      .onChange(of: scene) { if $0 != .active { image = nil } }
      .onDisappear { image = nil }
    }
  }

  private struct PDFPages: View {
    @Environment(\.galaxySSIInterfaceLanguage) private var language
    let document: PDFDocument
    let name: String
    @State private var index = 0
    @State private var image: UIImage?

    var body: some View {
      VStack {
        if let image {
          Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(Text(name))
        }
        HStack {
          Button { index -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
            .disabled(index == 0)
            .accessibilityLabel(Text(t("previous_page", "Previous page")))
          Text(String(format: t("page", "Page %lld of %lld"), Int64(index + 1), Int64(document.pageCount)))
          Button { index += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
            .disabled(index >= document.pageCount - 1)
            .accessibilityLabel(Text(t("next_page", "Next page")))
        }
      }
      .task(id: index) { @MainActor in
        guard !Task.isCancelled else { return }
        image = document.page(at: index)?.thumbnail(of: CGSize(width: 1_200, height: 1_200), for: .cropBox)
      }
    }

    private func t(_ key: String, _ fallback: String) -> String {
      GalaxySSILocalization.string("galaxyssi.health.originals." + key, fallback: fallback, language: language)
    }
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
