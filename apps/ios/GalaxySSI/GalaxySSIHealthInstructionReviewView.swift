import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthInstructionReviewView: View {
  typealias Review = GalaxySSIHealthInstruction
  typealias Documents = GalaxySSIHealthEncounterDocument
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var store: GalaxySSIStore
  let records: GalaxySSIHealthRecords
  let concern: UUID
  let metric: GalaxySSIHealthMetric
  let visit: UUID

  @State private var page: Review.Page?
  @State private var rows: [Review.Item] = []
  @State private var expires: Date?
  @State private var documents: Documents.Page?
  @State private var sourceRows: [Documents.Item] = []
  @State private var source: Documents.Item?
  @State private var sourcePage = 1
  @State private var reading: Review.Reading?
  @State private var selected = Set<Int>()
  @State private var recognition: Task<Void, Never>?
  @State private var recognitionID = UUID()
  @State private var history: Review.History?
  @State private var receipts: [Review.Receipt] = []
  @State private var editor: Review.Draft?
  @State private var deleting = false
  @State private var confirming = false
  @State private var mutating = false
  @State private var failed = false
  @State private var reload = UUID()

  var body: some View {
    NavigationView {
      Group {
        if !canRead { Color.clear }
        else if let editor, let history {
          GalaxySSIHealthInstructionEditor(draft: Binding(get: { self.editor ?? editor }, set: { self.editor = $0 }),
            source: history.item.entry.source, language: language) { save($0, history: history) }
        } else if let history { detail(history) }
        else if let source { sourceReview(source) }
        else if documents != nil { sourceList }
        else { instructionList }
      }
      .navigationTitle(t("title", "Instruction drafts"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if editor != nil || history != nil || source != nil || documents != nil {
            Button(t("back", "Back"), action: back)
          } else { Button(t("done", "Done")) { dismiss() } }
        }
      }
    }
    .navigationViewStyle(.stack)
    .task(id: reload) { if canRead { load() } }
    .task(id: expiry) {
      guard let deadline = expiry else { return }
      let seconds = min(Review.readingLifetime, max(0, deadline.timeIntervalSinceNow))
      do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
      if !Task.isCancelled, expiry == deadline { fail() }
    }
    .onChange(of: scene) { if $0 == .active { reset() } else { clear() } }
    .onChange(of: store.profile.identityFingerprint) { _ in reset() }
    .onDisappear { clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in fail() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reset() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { update in
      if !mutating, update.object as? String == records.owner { reset() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { update in
      if !mutating, update.object as? String == records.owner { reset() }
    }
  }

  private var instructionList: some View {
    List {
      if let page {
        Button { loadSources() } label: { Label(t("add", "New draft from a document"), systemImage: "doc.text.viewfinder") }
        if rows.isEmpty { Text(t("empty", "No instruction drafts")).foregroundColor(.secondary) }
        ForEach(rows) { item in
          Button { open(item.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(title(item.entry)).foregroundColor(.primary)
              Text(item.originalAvailable ? reviewStatus(item.entry.draft) : t("missing", "Original unavailable"))
                .font(.footnote).foregroundColor(.secondary)
            }
          }
        }
        if page.next != nil { Button(t("more", "Show more")) { load(append: true) } }
      }
      if failed {
        Text(t("unavailable", "The document or visit changed, or access is unavailable.")).foregroundColor(.secondary)
        Button(t("reload", "Reload"), action: reset)
      }
    }
  }

  private var sourceList: some View {
    List {
      if sourceRows.isEmpty { Text(t("no_sources", "No linked visit documents")).foregroundColor(.secondary) }
      ForEach(sourceRows) { item in
        Button {
          source = item
          sourcePage = item.link.page ?? 1
          recognize(item)
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(item.original?.name ?? t("missing", "Original unavailable")).foregroundColor(.primary)
            if let page = item.link.page { Text(pageLabel(page, item.link.pageCount)).font(.footnote).foregroundColor(.secondary) }
          }
        }.disabled(item.original == nil)
      }
      if documents?.next != nil { Button(t("more", "Show more")) { loadSources(append: true) } }
    }
  }

  private func sourceReview(_ item: Documents.Item) -> some View {
    List {
      Section(item.original?.name ?? t("missing", "Original unavailable")) {
        if item.link.page == nil, item.link.pageCount > 1 {
          Stepper(pageLabel(sourcePage, item.link.pageCount), value: $sourcePage, in: 1...item.link.pageCount)
            .onChange(of: sourcePage) { _ in recognize(item) }
        } else { Text(pageLabel(sourcePage, item.link.pageCount)) }
        if recognition != nil { ProgressView(t("reading", "Reading source")) }
        if let reading, let image = reading.result.preview {
          GalaxySSIHealthInstructionPagePreview(image: image,
            highlights: reading.result.regions.filter { selected.contains($0.id) }.compactMap(\.highlight))
            .accessibilityLabel(pageLabel(reading.page, item.link.pageCount))
        }
        if item.original?.kind == .pdf, reading?.result.method == .native {
          Button(t("force_ocr", "Use on-device OCR")) { recognize(item, forceOCR: true) }
        }
      }
      if let reading {
        Section(t("select_lines", "Select the original lines")) {
          ForEach(reading.result.regions) { region in
            Toggle(region.text, isOn: Binding(get: { selected.contains(region.id) }, set: { enabled in
              if enabled { selected.insert(region.id) } else { selected.remove(region.id) }
            })).disabled(!selected.contains(region.id) && selected.count >= 200)
          }
        }
        Button(t("create", "Create draft from selected text")) { confirming = true }
          .disabled(selected.isEmpty)
      }
    }
    .confirmationDialog(t("create_confirm", "Save this quotation as a draft?"),
      isPresented: $confirming, titleVisibility: .visible) {
        Button(t("create_draft", "Create draft"), action: create)
      }
  }

  private func detail(_ current: Review.History) -> some View {
    let entry = current.item.entry
    return List {
      Section {
        Text(title(entry)).font(.headline)
        Text(reviewStatus(entry.draft))
        Text(t("notice", "User transcription only. This is not clinician verification or a treatment plan."))
          .font(.footnote).foregroundColor(.secondary)
        if let name = current.item.originalName { Label(name, systemImage: "doc") }
        else { Label(t("missing", "Original unavailable"), systemImage: "exclamationmark.triangle") }
      }
      GalaxySSIHealthInstructionQuote(source: entry.source, language: language)
      Section(t("fields", "Fields")) { fields(entry.draft) }
      Section(t("history", "Review history")) {
        ForEach(receipts) { receipt in
          DisclosureGroup(String(format: t("revision", "Revision %lld"), Int64(receipt.entry.revision))) {
            Text(receipt.entry.updatedAt, style: .date).foregroundColor(.secondary)
            fields(receipt.entry.draft)
          }
        }
        if current.next != nil { Button(t("more", "Show more")) { open(entry.id, append: true) } }
      }
      Button(t("edit", "Review fields")) { editor = entry.draft }.disabled(!current.item.originalAvailable)
      Button(t("delete", "Delete draft"), role: .destructive) { deleting = true }
    }
    .confirmationDialog(t("delete_confirm", "Delete this draft and its review history?"), isPresented: $deleting,
      titleVisibility: .visible) { Button(t("delete", "Delete draft"), role: .destructive) { remove(current) } }
  }

  @ViewBuilder private func fields(_ draft: Review.Draft) -> some View {
    ForEach(draft.kind.fields) { field in
      VStack(alignment: .leading, spacing: 4) {
        Text(Review.fieldTitle(field, language))
        let value = draft.value(field)
        if !value.text.isEmpty { Text(value.text).textSelection(.enabled) }
        Text(Review.reviewTitle(value.review, language)).font(.footnote).foregroundColor(.secondary)
      }
    }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }
  private var expiry: Date? { [expires, history?.expires, reading?.expires].compactMap { $0 }.min() }
  private func t(_ key: String, _ fallback: String) -> String { Review.text(key, fallback, language) }
  private func pageLabel(_ page: Int, _ count: Int) -> String {
    String(format: t("page", "Page %lld of %lld"), Int64(page), Int64(count))
  }
  private func title(_ entry: Review.Entry) -> String {
    entry.draft.value(.name).text.isEmpty ? Review.kindTitle(entry.draft.kind, language) : entry.draft.value(.name).text
  }
  private func reviewStatus(_ draft: Review.Draft) -> String {
    draft.reviewed ? t("reviewed", "User reviewed") : t("pending", "Review pending")
  }

  private func clearRecognition() {
    recognition?.cancel(); recognition = nil; recognitionID = UUID(); reading = nil; selected = []; confirming = false
  }
  private func clear() {
    clearRecognition()
    page = nil; rows = []; expires = nil; documents = nil; sourceRows = []; source = nil
    history = nil; receipts = []; editor = nil; deleting = false; failed = false
  }
  private func reset() { clear(); reload = UUID() }
  private func fail() { clear(); failed = true }
  private func back() {
    if editor != nil { editor = nil }
    else if history != nil { history = nil; receipts = [] }
    else if source != nil { clearRecognition(); source = nil }
    else { documents = nil; sourceRows = [] }
  }

  private func load(append: Bool = false) {
    guard canRead else { return }
    do {
      let next = try records.visitInstructions(concern: concern, metric: metric, visit: visit,
        before: append ? page?.next : nil, expected: append ? page?.scope : nil)
      page = next; rows = (append ? rows : []) + next.items
      if !append { expires = Date().addingTimeInterval(Review.readingLifetime) }
    } catch { fail() }
  }
  private func loadSources(append: Bool = false) {
    guard canRead, let page else { return }
    do {
      let next = try records.visitDocumentPage(concern: concern, metric: metric, visit: visit,
        before: append ? documents?.next : nil, expected: page.scope)
      documents = next; sourceRows = (append ? sourceRows : []) + next.items
    } catch { fail() }
  }
  private func recognize(_ item: Documents.Item, forceOCR: Bool = false) {
    clearRecognition()
    guard canRead, let scope = documents?.scope else { return }
    let request = recognitionID, selectedPage = sourcePage
    recognition = Task {
      do {
        let output = try await records.readVisitInstructionSource(item.link, page: selectedPage, expected: scope, forceOCR: forceOCR)
        guard !Task.isCancelled, canRead, recognitionID == request else { return }
        reading = output; recognition = nil
      } catch {
        if !Task.isCancelled, recognitionID == request { fail() }
      }
    }
  }
  private func open(_ id: UUID, append: Bool = false) {
    guard canRead, let scope = page?.scope else { return }
    do {
      let next = try records.visitInstructionHistory(id: id, expected: scope, before: append ? history?.next : nil,
        validUntil: append ? history?.expires : expires)
      history = next; receipts = (append ? receipts : []) + next.receipts
    } catch { fail() }
  }
  private func create() {
    guard canRead, let reading else { return }
    mutate { try records.createVisitInstruction(from: reading, selected: selected, operation: UUID()).entry.id }
  }
  private func save(_ draft: Review.Draft, history: Review.History) {
    guard canRead else { return }
    mutate { try records.updateVisitInstruction(draft, history: history, operation: UUID()).entry.id }
  }
  private func remove(_ history: Review.History) {
    guard canRead else { return }
    mutate { try records.deleteVisitInstruction(history); return nil }
  }
  private func mutate(_ update: () throws -> UUID?) {
    mutating = true
    defer { mutating = false }
    do {
      let id = try update()
      clear(); load()
      if let id { open(id) }
    } catch { fail() }
  }
}
