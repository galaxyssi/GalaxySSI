import ImageIO
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct GalaxySSIHealthOriginalRemovalHistoryView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let store: GalaxySSIHealthOriginalStore
  @State private var history: [GalaxySSIHealthOriginalStore.RemovalAudit]?

  var body: some View {
    List {
      if scene == .active {
        if let history {
          if history.isEmpty { Text(t("no_removals", "No original removals.")).foregroundColor(.secondary) }
          ForEach(history) { entry in
            VStack(alignment: .leading, spacing: 4) {
              Text(t("removal_confirmed", "Local original removal confirmed"))
              Text(String(format: t("removal_audit_count", "Linked measurements retained: %lld"),
                          Int64(entry.linkedMeasurements))).foregroundColor(.secondary)
              Text(entry.at, format: .dateTime).foregroundColor(.secondary)
            }
          }
        } else {
          Button(t("removal_history_retry", "Reload removal history"), action: reload)
        }
      }
    }
    .navigationTitle(t("removal_history", "Original removal history"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) { _ in reload() }
  }

  private func reload() {
    guard scene == .active else { history = nil; return }
    history = try? store.removalHistory()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.originals." + key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthOriginalsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let store: GalaxySSIHealthOriginalStore
  var exact: GalaxySSIHealthDataFiles.Reference? = nil
  var pickOnAppear = false
  @State private var didAutoPick = false
  @State private var exactOriginal: GalaxySSIHealthOriginalStore.Original?
  @State private var exactOpened = false
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
  @State private var exportDocument: OriginalExportDocument?
  @State private var exportType: UTType = .zip
  @State private var singleAttempt: GalaxySSIHealthOriginalStore.Original?
  @State private var pendingSingle: GalaxySSIHealthOriginalStore.Original?
  @State private var reviewAfterPreview = false
  @State private var singleVerified = false
  @State private var exportAttempt: GalaxySSIHealthOriginalStore.ExportAttempt?
  @State private var verifying = false
  @State private var receiptFailed = false
  @State private var preparedForShare = false
  @State private var pending: [GalaxySSIHealthOriginalStore.Original] = []
  @State private var removal: GalaxySSIHealthOriginalStore.RemovalPreview?
  @State private var removalAfterPreview: GalaxySSIHealthOriginalStore.Original?
  @State private var evidenceAfterPreview: GalaxySSIHealthOriginalStore.Original?
  @State private var reportEvidenceOriginal: GalaxySSIHealthOriginalStore.Original?
  @State private var removalNotice: String?
  @State private var error = false

  private struct Preview: Identifiable {
    let original: GalaxySSIHealthOriginalStore.Original
    var id: UUID { original.id }
    var name: String { original.name }
    var image: UIImage?
    var pdf: PDFDocument?
  }

  var body: some View {
    destinationActions(List {
      if let exact {
        if scene == .active {
          if let item = exactOriginal {
            Button { open(item) } label: {
              Label(item.name, systemImage: item.kind == .pdf ? "doc.text" : "photo")
            }
          }
          if error {
            Text(GalaxySSILocalization.string("galaxyssi.health.data_files.unavailable",
              fallback: "Original unavailable", language: language)).foregroundColor(.secondary)
            Button(t("retry", "Try again")) { exactOpened = false; loadExact(exact) }
          }
        }
      } else {
        libraryRows
      }
    }
    .navigationTitle(t("title", "Health Originals"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      reload()
      if scene == .active, pickOnAppear, !didAutoPick {
        didAutoPick = true
        importing = true
      }
    }
    .onChange(of: filter) { _ in shown = 30 }
    .onChange(of: recentDays) { _ in shown = 30 }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else {
        exactOriginal = nil
        listing = nil
        preview = nil
        removal = nil
        removalAfterPreview = nil
        evidenceAfterPreview = nil
        reportEvidenceOriginal = nil
        removalNotice = nil
        pending = []
        pendingSingle = nil
        reviewAfterPreview = false
        confirming = false
        singleVerified = false
        if !exporting { exportDocument = nil }
      }
    }
    )
  }

  @ViewBuilder private var libraryRows: some View {
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
              pendingSingle = nil
              pending = listing?.originals.filter { selection.contains($0.id) } ?? []
              confirming = !pending.isEmpty
            } label: { Label(t("export", "Export selected ZIP"), systemImage: "square.and.arrow.up") }
            .disabled(verifying)
          }
          if verifying { ProgressView(t("verifying_destination", "Verifying saved file")) }
          if singleVerified { Text(t("verified", "Save verified")).foregroundColor(.secondary) }
          if preparedForShare { Text(t("ready_to_share", "ZIP ready in export history.")).foregroundColor(.secondary) }
          if receiptFailed { Text(t("verify_failed", "The destination could not be verified.")).foregroundColor(.secondary) }
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
              .contextMenu { singleSaveButton(item) }
              .swipeActions(allowsFullSwipe: false) {
                Button(role: .destructive) { reviewRemoval(item) } label: {
                  Label(t("remove", "Remove"), systemImage: "trash")
                }
              }
            }
          }
          if rows.count > shown { Button(t("more", "Show more")) { shown += 30 } }
          let removed = filtered(listing.removed)
          if !removed.isEmpty {
            Section(t("removed_originals", "Removed originals")) {
              ForEach(removed.prefix(shown)) { item in
                VStack(alignment: .leading, spacing: 4) {
                  Text(item.name)
                  Text(ByteCountFormatter.string(fromByteCount: Int64(item.bytes), countStyle: .file))
                    .foregroundColor(.secondary)
                  if listing.pendingRemovals.contains(item.id) {
                    Text(t("removal_pending", "Local file cleanup is pending.")).foregroundColor(.secondary)
                  }
                }
              }
              if removed.count > shown { Button(t("more", "Show more")) { shown += 30 } }
            }
          }
        }
        if let removalNotice { Text(removalNotice).foregroundColor(.secondary) }
        if error {
          Text(t("error", "Could not complete the operation. Check the file or select fewer originals."))
            .foregroundColor(.secondary)
          Button(t("retry", "Reload originals"), action: reload)
        }
      }
      NavigationLink {
        OriginalExportHistory(store: store)
      } label: {
        Label(t("file_save_history", "File save history"), systemImage: "clock.arrow.circlepath")
      }
  }

  private func destinationActions<Content: View>(_ content: Content) -> some View {
    content
    .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf]) { result in
      guard scene == .active else { return }
      do { try store.importFile(result.get()); reload() }
      catch { error = true }
    }
    .confirmationDialog(pendingSingle == nil ? t("plain_zip", "Save an unencrypted ZIP of these originals?") :
                        t("plain_original", "Save an unencrypted copy of this original?"),
                        isPresented: $confirming, titleVisibility: .visible) {
      Button(t("save", "Choose save location")) {
        if let item = pendingSingle { exportSingle(item) } else { export() }
      }
    } message: {
      if let item = pendingSingle {
        Text(item.name + "\n" + ByteCountFormatter.string(fromByteCount: Int64(item.bytes), countStyle: .file))
      } else {
        Text(String(format: t("selected_count", "%lld selected originals"), Int64(pending.count)))
      }
    }
    .alert(item: $removal) { review in
      Alert(title: Text(t("remove_confirm", "Remove this original?")), message: Text(removalMessage(review)),
            primaryButton: .destructive(Text(t("remove", "Remove"))) { remove(review) }, secondaryButton: .cancel())
    }
    .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportType,
                  defaultFilename: exportType == .zip ? "GalaxySSI-Health-Originals" : "GalaxySSI-Health-Original") { result in
      exportDocument = nil
      if let item = singleAttempt {
        singleAttempt = nil
        verifySingle(result, item: item)
        return
      }
      guard let attempt = exportAttempt else { return }
      exportAttempt = nil
      switch result {
      case .success(let url): verify(url, attempt: attempt)
      case .failure:
        do { try store.finishExport(id: attempt.id, verified: false) } catch {}
        receiptFailed = true
      }
    }
    .onChange(of: exporting) { if !$0 { exportDocument = nil } }
    .sheet(item: $preview, onDismiss: {
      if scene == .active, let item = evidenceAfterPreview { reportEvidenceOriginal = item }
      evidenceAfterPreview = nil
      if let item = removalAfterPreview {
        removalAfterPreview = nil
        reviewRemoval(item)
      }
      if reviewAfterPreview {
        reviewAfterPreview = false
        confirming = scene == .active && pendingSingle != nil
      }
    }) { item in
      if scene == .active {
        VStack {
        HStack {
          Text(item.name).font(.headline).lineLimit(2).truncationMode(.middle)
          Spacer()
          Button { reviewSingle(item.original, fromPreview: true) } label: {
            Image(systemName: "square.and.arrow.down").frame(width: 44, height: 44)
          }
          .disabled(verifying)
          .accessibilityLabel(Text(t("save_original", "Save original")))
          Button(role: .destructive) {
            removalAfterPreview = item.original
            preview = nil
          } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
          .disabled(verifying)
          .accessibilityLabel(Text(t("remove", "Remove")))
          Button { preview = nil } label: { Image(systemName: "xmark.circle").font(.title2) }
            .accessibilityLabel(Text(t("close", "Close")))
        }
        if let pdf = item.pdf {
          Button {
            evidenceAfterPreview = item.original
            preview = nil
          } label: {
            Label(GalaxySSIHealthReportReview.text("evidence", "Linked report evidence", language: language),
                  systemImage: "link")
          }
          GalaxySSIHealthOriginalPDFPreview(document: pdf, name: item.name)
        } else if let image = item.image {
          Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(Text(item.name))
        }
        }.padding()
      }
    }
    .sheet(item: $reportEvidenceOriginal) { original in
      NavigationView {
        GalaxySSIHealthReportEvidenceView(
          records: GalaxySSIHealthRecords(owner: store.owner, secrets: store.secrets, isolatedFile: store.restoreRecordsFile),
          store: store, original: original)
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("close", "Close")) { reportEvidenceOriginal = nil }
          } }
      }
      .navigationViewStyle(.stack)
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
      singleSaveButton(item)
      Button(role: .destructive) { reviewRemoval(item) } label: { Label(t("remove", "Remove"), systemImage: "trash") }
    }
  }

  private func removalMessage(_ review: GalaxySSIHealthOriginalStore.RemovalPreview) -> String {
    let size = ByteCountFormatter.string(fromByteCount: Int64(review.original.bytes), countStyle: .file)
    let count = String(format: t("retained_count", "%lld linked measurements will remain."), Int64(review.links.count))
    return [review.original.name, size, count,
            t("remove_boundary", "Measurement links, drafts, and existing exports and backups are unchanged.")]
      .joined(separator: "\n")
  }

  private func reviewRemoval(_ item: GalaxySSIHealthOriginalStore.Original) {
    guard scene == .active, !exporting, !verifying else { return }
    removalNotice = nil
    do { removal = try store.previewRemoval(item) }
    catch GalaxySSIHealthOriginalStore.Failure.stale { removalChanged() }
    catch { error = true }
  }

  private func remove(_ review: GalaxySSIHealthOriginalStore.RemovalPreview) {
    guard scene == .active else { return }
    do {
      let outcome = try store.remove(review)
      reload()
      if case .pendingCleanup = outcome, listing?.pendingRemovals.contains(review.id) != false {
        removalNotice = t("removal_pending", "Local file cleanup is pending.")
      } else {
        removalNotice = t("removal_done", "Original removed. Measurements were kept.")
      }
    } catch GalaxySSIHealthOriginalStore.Failure.stale { removalChanged() }
    catch { error = true }
  }

  private func removalChanged() {
    reload()
    removalNotice = t("removal_changed", "The file or linked measurements changed. Review the removal again.")
  }

  private func reload() {
    guard scene == .active else { return }
    if let exact { loadExact(exact); return }
    do {
      let current = try store.list()
      listing = current
      selection.formIntersection(current.originals.map(\.id))
      error = false
    } catch { listing = nil; error = true }
  }

  private func loadExact(_ reference: GalaxySSIHealthDataFiles.Reference) {
    do {
      let item = try store.indexedOriginal(id: reference.id, sha256: reference.sha256)
      exactOriginal = item
      error = false
      if !exactOpened {
        exactOpened = true
        open(item)
      }
    } catch {
      exactOriginal = nil
      error = true
    }
  }

  private func open(_ item: GalaxySSIHealthOriginalStore.Original) {
    guard scene == .active else { return }
    do {
      let data = try store.read(item)
      if item.kind == .pdf {
        guard let pdf = PDFDocument(data: data), pdf.isLocked || pdf.pageCount > 0 else { error = true; return }
        preview = Preview(original: item, pdf: pdf)
      } else {
        guard let image = Self.thumbnail(data, maximum: 1_200) else { error = true; return }
        preview = Preview(original: item, image: image)
      }
    } catch { error = true }
  }

  private func singleSaveButton(_ item: GalaxySSIHealthOriginalStore.Original) -> some View {
    Button { reviewSingle(item) } label: {
      Label(t("save_original", "Save original"), systemImage: "square.and.arrow.down")
    }
    .disabled(verifying)
  }

  private func reviewSingle(_ item: GalaxySSIHealthOriginalStore.Original, fromPreview: Bool = false) {
    guard scene == .active, !exporting, !verifying else { return }
    pending = []
    pendingSingle = item
    singleVerified = false
    receiptFailed = false
    if fromPreview {
      reviewAfterPreview = true
      preview = nil
    } else {
      confirming = true
    }
  }

  private func exportSingle(_ item: GalaxySSIHealthOriginalStore.Original) {
    pendingSingle = nil
    guard scene == .active, !verifying else { return }
    do {
      let data = try store.read(item)
      guard let type = UTType(filenameExtension: item.fileExtension),
            (item.kind == .pdf ? type.conforms(to: .pdf) : type.conforms(to: .image))
      else { throw GalaxySSIHealthOriginalStore.Failure.invalid }
      exportAttempt = nil
      singleAttempt = item
      exportType = type
      exportDocument = OriginalExportDocument(data: data)
      exporting = true
    } catch { receiptFailed = true }
  }

  private func verifySingle(_ result: Result<URL, Error>, item: GalaxySSIHealthOriginalStore.Original) {
    if case .failure(let error) = result, (error as? CocoaError)?.code == .userCancelled { return }
    verifying = true
    Task {
      let matched: Bool
      if case .success(let url) = result {
        matched = await Task.detached(priority: .utility) {
          (try? GalaxySSIHealthOriginalStore.verifyDestination(url, bytes: item.bytes, sha256: item.sha256)) == true
        }.value
      } else {
        matched = false
      }
      let verified = (try? store.finishSingleSave(item, destinationVerified: matched)) == true
      if scene == .active {
        singleVerified = verified
        receiptFailed = !verified
      }
      verifying = false
    }
  }

  private func export() {
    guard scene == .active, !verifying else { return }
    let selected = pending
    pending = []
    receiptFailed = false
    do {
      let (data, attempt) = try store.prepareExport(selected)
      singleAttempt = nil
      exportAttempt = attempt
      exportType = .zip
      exportDocument = OriginalExportDocument(data: data)
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
struct OriginalExportHistory: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let store: GalaxySSIHealthOriginalStore
  @State private var history: [GalaxySSIHealthOriginalStore.ExportAttempt] = []
  @State private var singleHistory: [GalaxySSIHealthOriginalStore.SingleSaveReceipt] = []
  @State private var singleHistoryUnavailable = false
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
        } else if history.isEmpty && singleHistory.isEmpty && !singleHistoryUnavailable {
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
        if singleHistoryUnavailable || !singleHistory.isEmpty {
          Section(t("single_save_history", "Single original saves")) {
            if singleHistoryUnavailable {
              Text(t("history_unavailable", "Export history unavailable"))
              Button(t("retry_history", "Reload history"), action: reload)
            } else {
              ForEach(singleHistory.prefix(limit).indices, id: \.self) { index in
                let receipt = singleHistory[index]
                VStack(alignment: .leading, spacing: 4) {
                  Text(receipt.verified ? t("verified", "Save verified") : t("not_verified", "Save could not be verified"))
                  Text(receipt.at.formatted(date: .abbreviated, time: .shortened)).foregroundColor(.secondary)
                  Text(ByteCountFormatter.string(fromByteCount: Int64(receipt.bytes), countStyle: .file))
                    .foregroundColor(.secondary)
                }
              }
              if singleHistory.count > limit { Button(t("more", "Show more")) { limit += 20 } }
            }
          }
        }
      }
    }
    .navigationTitle(t("file_save_history", "File save history"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else { selected = nil; history = []; singleHistory = []; confirmShare = false; sharing = nil }
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
    do { singleHistory = try store.singleSaveHistory(); singleHistoryUnavailable = false }
    catch { singleHistory = []; singleHistoryUnavailable = true }
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

private struct OriginalExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.zip, .pdf, .image] }
  let data: Data

  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    self.data = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
