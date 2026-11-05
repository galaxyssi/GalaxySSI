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
  @State private var removedLimit = 30
  @State private var selection: Set<UUID> = []
  @State private var preview: Preview?
  @State private var importing = false
  @State private var confirming = false
  @State private var exporting = false
  @State private var zip: OriginalZIP?
  @State private var exportAttempt: GalaxySSIHealthOriginalStore.ExportAttempt?
  @State private var verifying = false
  @State private var receiptFailed = false
  @State private var preparedForShare = false
  @State private var pending: [GalaxySSIHealthOriginalStore.Original] = []
  @State private var removal: GalaxySSIHealthOriginalStore.Removal?
  @State private var removalNotice: RemovalNotice?
  private enum RemovalNotice { case removed, changed }
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
            Button(action: prepareForSharing) {
              Label(t("prepare_zip", "Prepare selected ZIP"), systemImage: "archivebox")
            }
            .disabled(verifying)
            Button {
              pending = listing?.originals.filter { selection.contains($0.id) } ?? []
              confirming = !pending.isEmpty
            } label: { Label(t("export", "Export selected ZIP"), systemImage: "square.and.arrow.up") }
            .disabled(verifying)
          }
          if verifying { ProgressView(t("verifying", "Verifying saved ZIP")) }
          if preparedForShare { Text(t("ready_to_share", "ZIP ready in export history.")).foregroundColor(.secondary) }
          if receiptFailed { Text(t("verify_failed", "The destination could not be verified.")).foregroundColor(.secondary) }
        }
        if let listing {
          let rows = filtered(listing.originals)
          let removed = filtered(listing.removed)
          if rows.isEmpty && removed.isEmpty { Text(t("empty", "No originals found")).foregroundColor(.secondary) }
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
                Button(role: .destructive) { prepareRemoval(item) } label: {
                  Label(t("remove", "Remove"), systemImage: "trash")
                }
              }
            }
          }
          if rows.count > shown { Button(t("more", "Show more")) { shown += 30 } }
          if !removed.isEmpty {
            Section(t("removed_files", "Removed original files")) {
              ForEach(removed.prefix(removedLimit)) { original in
                NavigationLink {
                  GalaxySSIHealthReportEvidenceView(records: store.indexRecords, store: store,
                    original: original, originalRemoved: true)
                } label: { Text(original.name) }
              }
              if removed.count > removedLimit { Button(t("more", "Show more")) { removedLimit += 30 } }
            }
          }
        }
        if let removalNotice {
          Text(removalNotice == .removed
               ? t("remove_success", "Original file removed.")
               : t("remove_changed", "The file or its linked measurements changed. Review it again."))
            .foregroundColor(.secondary)
        }
        if error {
          Text(t("error", "Could not complete the operation. Check the file or select fewer originals."))
            .foregroundColor(.secondary)
          Button(t("retry", "Reload originals"), action: reload)
        }
      }
      NavigationLink {
        OriginalExportHistory(store: store)
      } label: {
        Label(t("export_history", "ZIP export history"), systemImage: "clock.arrow.circlepath")
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
        removalNotice = nil
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
      Alert(title: Text(t("remove_confirm", "Remove this original?")),
            message: Text(item.original.name + "\n" + ByteCountFormatter.string(fromByteCount: Int64(item.original.bytes),
              countStyle: .file) + "\n" + String(format: t("remove_links",
                "%lld linked measurements will be kept"), Int64(item.count))),
            primaryButton: .destructive(Text(t("remove", "Remove"))) {
              guard scene == .active else { return }
              do {
                try store.remove(item)
                reload()
                removalNotice = .removed
              } catch GalaxySSIHealthOriginalStore.Failure.stale {
                reload()
                removalNotice = .changed
              } catch { error = true }
            }, secondaryButton: .cancel())
    }
    .fileExporter(isPresented: $exporting, document: zip, contentType: .zip,
                  defaultFilename: "GalaxySSI-Health-Originals") { result in
      zip = nil
      guard let attempt = exportAttempt else { return }
      exportAttempt = nil
      switch result {
      case .success(let url): verify(url, attempt: attempt)
      case .failure:
        do { try store.finishExport(id: attempt.id, verified: false) } catch {}
        receiptFailed = true
      }
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
          GalaxySSIHealthOriginalPDFPreview(document: pdf, name: item.name)
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
      Button(role: .destructive) { prepareRemoval(item) } label: {
        Label(t("remove", "Remove"), systemImage: "trash")
      }
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

  private func prepareRemoval(_ item: GalaxySSIHealthOriginalStore.Original) {
    guard scene == .active else { return }
    removalNotice = nil
    do { removal = try store.previewRemoval(item) }
    catch GalaxySSIHealthOriginalStore.Failure.stale { reload(); removalNotice = .changed }
    catch { error = true }
  }

  private func open(_ item: GalaxySSIHealthOriginalStore.Original) {
    guard scene == .active else { return }
    do {
      let data = try store.read(item)
      if item.kind == .pdf {
        guard let pdf = PDFDocument(data: data), pdf.isLocked || pdf.pageCount > 0 else { error = true; return }
        preview = Preview(id: item.id, name: item.name, pdf: pdf)
      } else {
        guard let image = Self.thumbnail(data, maximum: 1_200) else { error = true; return }
        preview = Preview(id: item.id, name: item.name, image: image)
      }
    } catch { error = true }
  }

  private func export() {
    guard scene == .active, !verifying else { return }
    let selected = pending
    pending = []
    receiptFailed = false
    do {
      let (data, attempt) = try store.prepareExport(selected)
      exportAttempt = attempt
      zip = OriginalZIP(data: data)
      exporting = true
    }
    catch { error = true }
  }

  private func prepareForSharing() {
    guard scene == .active, !verifying, let listing else { return }
    preparedForShare = false
    do {
      _ = try store.prepareExport(listing.originals.filter { selection.contains($0.id) })
      preparedForShare = true
      error = false
    } catch { error = true }
  }

  private func verify(_ url: URL, attempt: GalaxySSIHealthOriginalStore.ExportAttempt) {
    verifying = true
    Task {
      let verified = await Task.detached(priority: .utility) {
        (try? GalaxySSIHealthOriginalStore.verifyDestination(url, for: attempt)) == true
      }.value
      do {
        try store.finishExport(id: attempt.id, verified: verified)
        receiptFailed = !verified
      } catch { receiptFailed = true }
      verifying = false
    }
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

@MainActor
private struct GalaxySSIHealthOriginalPDFPreview: View {
  let document: PDFDocument
  let name: String
  @State private var unlocked = false
  @State private var failed = false

  var body: some View {
    if unlocked || !document.isLocked {
      PDFPages(document: document, name: name)
    } else {
      GalaxySSIHealthPDFPasswordForm(failed: failed) { password in
        unlocked = document.unlock(withPassword: password) && !document.isLocked && document.pageCount > 0
        failed = !unlocked
      }
    }
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

@MainActor
private struct OriginalExportHistory: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let store: GalaxySSIHealthOriginalStore
  @State private var history: [GalaxySSIHealthOriginalStore.ExportAttempt] = []
  @State private var selected: GalaxySSIHealthOriginalStore.ExportAttempt?
  @State private var limit = 20
  @State private var scopeLimit = 30
  @State private var unavailable = false
  @State private var confirmShare = false
  @State private var shareFailure = false
  @State private var sharing: SharePayload?

  private struct SharePayload: Identifiable {
    let id: UUID
    let data: Data
  }

  var body: some View {
    List {
      if scene == .active {
        if unavailable {
          Text(t("history_unavailable", "Export history unavailable"))
          Button(t("retry_history", "Reload history"), action: reload)
        } else if history.isEmpty {
          Text(t("history_empty", "No ZIP export attempts")).foregroundColor(.secondary)
        } else {
          ForEach(history.prefix(limit)) { entry in
            Button { scopeLimit = 30; shareFailure = false; selected = entry } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(outcome(entry)).foregroundColor(.primary)
                Text(entry.at.formatted(date: .abbreviated, time: .shortened)).foregroundColor(.secondary)
                Text(String(format: t("selected_count", "%lld selected originals"), Int64(entry.originals.count)))
                  .foregroundColor(.secondary)
              }
            }
          }
          if history.count > limit { Button(t("more", "Show more")) { limit += 20 } }
        }
      }
    }
    .navigationTitle(t("export_history", "ZIP export history"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else { selected = nil; history = []; confirmShare = false; sharing = nil }
    }
    .sheet(item: $selected) { entry in
      NavigationView {
        List {
          if scene == .active {
            Section(outcome(entry)) {
              Text(entry.sha256).font(.footnote.monospaced())
              Text(ByteCountFormatter.string(fromByteCount: Int64(entry.bytes), countStyle: .file))
            }
            Section(t("export_scope", "Originals in this export")) {
              ForEach(entry.originals.prefix(scopeLimit)) { item in Text(item.name) }
              if entry.originals.count > scopeLimit { Button(t("more", "Show more")) { scopeLimit += 30 } }
            }
            if store.hasShareArtifact(entry) {
              Button { confirmShare = true } label: {
                Label(t("share_zip", "Share ZIP"), systemImage: "square.and.arrow.up")
              }
            } else {
              Text(t("artifact_unavailable", "The private ZIP is no longer available.")).foregroundColor(.secondary)
            }
            if shareFailure { Text(t("share_failed", "Could not open the verified ZIP bytes.")).foregroundColor(.secondary) }
          }
        }
        .navigationTitle(t("export_history", "ZIP export history"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
          Button(t("close", "Close")) { selected = nil }
        } }
        .confirmationDialog(t("share_plain_zip", "Share this unencrypted ZIP?"), isPresented: $confirmShare,
                            titleVisibility: .visible) {
          Button(t("share_zip", "Share ZIP")) { share(entry) }
        }
        .sheet(item: $sharing) { payload in
          if scene == .active {
            OriginalZIPShareSheet(data: payload.data)
          }
        }
      }
      .navigationViewStyle(.stack)
    }
  }

  private func share(_ attempt: GalaxySSIHealthOriginalStore.ExportAttempt) {
    guard scene == .active, selected?.id == attempt.id else { return }
    do {
      sharing = SharePayload(id: attempt.id, data: try store.readShareArtifact(attempt))
      shareFailure = false
    } catch { shareFailure = true }
  }

  private func reload() {
    guard scene == .active else { return }
    do { history = try store.exportHistory(); unavailable = false }
    catch { history = []; unavailable = true }
  }

  private func outcome(_ entry: GalaxySSIHealthOriginalStore.ExportAttempt) -> String {
    switch entry.outcome {
    case .prepared: return t("prepared", "Prepared, save not verified")
    case .verified: return t("verified", "Save verified")
    case .unverified: return t("not_verified", "Save could not be verified")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.originals." + key, fallback: fallback, language: language)
  }
}

private struct OriginalZIPShareSheet: UIViewControllerRepresentable {
  let data: Data

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let provider = NSItemProvider()
    provider.suggestedName = "GalaxySSI-Health-Originals.zip"
    provider.registerDataRepresentation(forTypeIdentifier: UTType.zip.identifier, visibility: .all) { completion in
      completion(data, nil)
      return nil
    }
    let configuration = UIActivityItemsConfiguration(itemProviders: [provider])
    return UIActivityViewController(activityItemsConfiguration: configuration)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
