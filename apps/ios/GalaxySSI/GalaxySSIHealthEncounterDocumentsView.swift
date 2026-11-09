import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthEncounterDocumentsView: View {
  typealias Documents = GalaxySSIHealthEncounterDocument
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var store: GalaxySSIStore
  let records: GalaxySSIHealthRecords
  let concern: UUID
  let metric: GalaxySSIHealthMetric
  let visit: UUID

  @State private var page: Documents.Page?
  @State private var rows: [Documents.Item] = []
  @State private var library: Documents.LibraryPage?
  @State private var originals: [Documents.Original] = []
  @State private var preview: Documents.Preview?
  @State private var openLink: Documents.Link?
  @State private var pendingUnlink: Documents.Link?
  @State private var confirm = false
  @State private var failed = false
  @State private var reload = UUID()

  var body: some View {
    NavigationView {
      Group {
        if canRead, let preview { previewContent(preview) }
        else if canRead {
          List {
            if library != nil { libraryContent }
            else if page != nil { linksContent }
            if failed {
              Text(t("unavailable", "The original or visit changed, or access is unavailable."))
                .foregroundColor(.secondary)
              Button(t("retry", "Reload"), action: resetAndReload)
            }
          }
          .confirmationDialog(t("document_remove_confirm", "Remove the link and keep the original?"),
            isPresented: Binding(get: { pendingUnlink != nil }, set: { if !$0 { pendingUnlink = nil } }),
            titleVisibility: .visible, presenting: pendingUnlink) { item in
              Button(t("document_remove", "Remove link"), role: .destructive) { unlink(item) }
            }
        } else { Color.clear }
      }
      .navigationTitle(library == nil ? t("documents", "Visit documents") : t("document_library", "Retained originals"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if preview != nil { Button(t("document_back", "Back"), action: clearPreview) }
          else if library != nil { Button(t("document_back", "Back"), action: clearLibrary) }
          else { Button(t("document_done", "Done")) { dismiss() } }
        }
      }
    }
    .navigationViewStyle(.stack)
    .task(id: reload) { if canRead { loadLinks() } }
    .task(id: preview?.operation) {
      guard let expires = preview?.expires, let operation = preview?.operation else { return }
      let seconds = min(Documents.previewLifetime, max(0, expires.timeIntervalSinceNow))
      do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
      if !Task.isCancelled, preview?.operation == operation { clearPreview() }
    }
    .onChange(of: scene) { if $0 == .active { resetAndReload() } else { clear() } }
    .onChange(of: store.profile.identityFingerprint) { _ in resetAndReload() }
    .onDisappear { clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in clear(); failed = true }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in resetAndReload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { update in
      if update.object as? String == records.owner { resetAndReload() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { update in
      if update.object as? String == records.owner { resetAndReload() }
    }
  }

  @ViewBuilder private var linksContent: some View {
    Button { loadLibrary() } label: { Label(t("document_add", "Link retained original"), systemImage: "link.badge.plus") }
    if rows.isEmpty { Text(t("document_empty", "No linked documents")).foregroundColor(.secondary) }
    ForEach(rows) { item in
      HStack {
        Button {
          if let original = item.original { open(original, at: item.link.page ?? 1, link: item.link) }
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(item.original?.name ?? t("document_missing", "Original unavailable")).foregroundColor(.primary)
            Text(item.link.page.map { position($0, item.link.pageCount) } ?? t("document_entire", "Whole document"))
              .font(.footnote).foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .disabled(item.original == nil)
        Button(role: .destructive) { pendingUnlink = item.link } label: { Image(systemName: "link.badge.minus") }
          .buttonStyle(.borderless)
          .accessibilityLabel(t("document_remove", "Remove link"))
      }
    }
    if page?.next != nil { Button(t("more", "Show more")) { loadLinks(append: true) } }
  }

  @ViewBuilder private var libraryContent: some View {
    if originals.isEmpty { Text(t("document_library_empty", "No retained originals")).foregroundColor(.secondary) }
    ForEach(originals) { original in
      Button { open(original, at: 1) } label: {
        Label(original.name, systemImage: original.kind == .pdf ? "doc" : "photo").foregroundColor(.primary)
      }
    }
    if library?.next != nil { Button(t("more", "Show more")) { loadLibrary(append: true) } }
  }

  private func previewContent(_ document: Documents.Preview) -> some View {
    VStack(spacing: 12) {
      Text(document.original.name).font(.headline).lineLimit(2)
      ScrollView {
        Image(uiImage: document.image).resizable().scaledToFit().frame(maxWidth: .infinity)
          .accessibilityLabel(position(document.page, document.count))
      }
      HStack {
        Button { turn(document, by: -1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
          .disabled(document.page <= 1 || openLink?.page != nil)
          .accessibilityLabel(t("document_previous", "Previous page"))
        Spacer()
        Text(position(document.page, document.count)).monospacedDigit()
        Spacer()
        Button { turn(document, by: 1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
          .disabled(document.page >= document.count || openLink?.page != nil)
          .accessibilityLabel(t("document_next", "Next page"))
      }
      if openLink == nil { Button(t("document_select", "Link to visit")) { confirm = true }.buttonStyle(.borderedProminent) }
    }
    .padding()
    .confirmationDialog(t("document_confirm", "Link this original to the visit?"), isPresented: $confirm,
                        titleVisibility: .visible) {
      Button(t("document_whole", "Link whole document")) { link(whole: true) }
      Button(t("document_page", "Link this page")) { link(whole: false) }
    }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthEncounter.text(key, fallback, language) }
  private func position(_ page: Int, _ count: Int) -> String {
    String(format: t("document_position", "Page %lld of %lld"), Int64(page), Int64(count))
  }

  private func clearPreview() { preview = nil; openLink = nil; confirm = false }
  private func clearLibrary() { library = nil; originals = []; clearPreview() }
  private func clear() { clearLibrary(); page = nil; rows = []; pendingUnlink = nil; failed = false }
  private func resetAndReload() { clear(); reload = UUID() }
  private func fail() { clear(); failed = true }

  private func loadLinks(append: Bool = false) {
    guard canRead else { return }
    do {
      let next = try records.visitDocumentPage(concern: concern, metric: metric, visit: visit,
        before: append ? page?.next : nil, expected: append ? page?.scope : nil)
      page = next
      rows = (append ? rows : []) + next.items
      failed = false
    } catch { fail() }
  }

  private func loadLibrary(append: Bool = false) {
    guard canRead, let scope = page?.scope else { return }
    do {
      let next = try records.visitDocumentLibrary(scope, after: append ? library?.next : nil)
      library = next
      originals = (append ? originals : []) + next.originals
    } catch { fail() }
  }

  private func open(_ original: Documents.Original, at selectedPage: Int, link: Documents.Link? = nil,
                    validUntil: Date? = nil) {
    guard canRead, let scope = page?.scope else { return }
    do {
      preview = try records.previewVisitDocument(original, page: selectedPage, expected: scope, link: link,
        validUntil: validUntil)
      openLink = link
    } catch { fail() }
  }

  private func turn(_ current: Documents.Preview, by delta: Int) {
    open(current.original, at: current.page + delta, link: openLink, validUntil: current.expires)
  }

  private func link(whole: Bool) {
    guard canRead, openLink == nil, let preview else { return }
    do { try records.linkVisitDocument(preview, whole: whole); resetAndReload() }
    catch { fail() }
  }

  private func unlink(_ item: Documents.Link) {
    guard canRead, let scope = page?.scope else { return }
    do { try records.unlinkVisitDocument(item, expected: scope); resetAndReload() }
    catch { fail() }
  }
}
