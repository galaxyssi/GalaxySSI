import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthCareVisitView: View {
  typealias Visit = GalaxySSIHealthCareVisit

  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let id: UUID
  let metric: GalaxySSIHealthMetric
  @State private var sections: Set<Visit.Section> = [.measurements, .context, .actions, .questions]
  @State private var preview: Visit.Preview?
  @State private var selection: Set<String> = []
  @State private var source: Source?
  @State private var share: Share?
  @State private var confirming = false
  @State private var changed = false

  private struct Source: Identifiable {
    let reading: GalaxySSIHealthReading
    let item: Visit.Item
    var id: UUID { reading.id }
  }

  private struct Share: Identifiable {
    let id = UUID()
    let text: String
  }

  var body: some View {
    List {
      if canRead {
        if let preview {
          Text(preview.introduction)
          ForEach(Visit.Section.allCases) { section in
            let items = preview.items.filter { $0.section == section }
            if !items.isEmpty {
              Section(section.title(language)) {
                ForEach(items) { item in
                  VStack(alignment: .leading, spacing: 8) {
                    Toggle(item.title, isOn: membership(item.id, in: $selection))
                    Text(item.text).foregroundColor(.secondary)
                    if item.record != nil {
                      Button { openSource(item, preview: preview) } label: {
                        Label(t("open_source", "Open source revision"), systemImage: "doc.text.magnifyingglass")
                      }.buttonStyle(.borderless)
                    }
                  }.padding(.vertical, 4)
                }
              }
            }
          }
          Text(preview.limitations).foregroundColor(.secondary)
          Button(t("share", "Share selected text")) { confirming = true }.disabled(selection.isEmpty)
          Button(t("change_sections", "Change sections")) { clear() }
        } else {
          Section(t("sections", "Sections")) {
            ForEach(Visit.Section.allCases) { section in
              Toggle(section.title(language), isOn: membership(section, in: $sections))
            }
          }
          Button(t("preview", "Preview summary")) { load() }.disabled(sections.isEmpty)
        }
        if changed {
          Text(t("changed", "The preview expired or its source changed. Create a new preview."))
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(t("title", "Prepare for a visit"))
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(t("confirm", "Share health information?"), isPresented: $confirming, titleVisibility: .visible) {
      Button(t("share", "Share selected text"), action: confirmShare)
    } message: {
      Text(t("disclosure", "Only the selected text will be handed to the iOS share sheet."))
    }
    .sheet(item: $share) { value in GalaxySSIHealthCareVisitShareSheet(text: value.text) }
    .sheet(item: $source) { value in
      NavigationView {
        List {
          if canRead {
            Text(value.item.text)
            if !value.reading.notes.isBlank { Text(value.reading.notes) }
          }
        }
        .navigationTitle(value.item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button(t("close", "Close")) { source = nil } }
        }
      }.navigationViewStyle(.stack)
    }
    .onChange(of: scene) { if $0 == .background { clear() } }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onChange(of: language) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { event in
      guard event.object as? String == records.owner, let preview else { return }
      do { try validate(preview) } catch { clear(invalidated: true) }
    }
    .task(id: preview?.created) {
      guard let created = preview?.created else { return }
      let seconds = min(600, max(0, created.addingTimeInterval(600).timeIntervalSinceNow))
      do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
      if !Task.isCancelled, preview?.created == created { clear(invalidated: true) }
    }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func t(_ key: String, _ fallback: String) -> String { Visit.text(key, fallback, language) }

  private func membership<T: Hashable>(_ value: T, in values: Binding<Set<T>>) -> Binding<Bool> {
    Binding(get: { values.wrappedValue.contains(value) }, set: { enabled in
      if enabled { values.wrappedValue.insert(value) } else { values.wrappedValue.remove(value) }
    })
  }

  private func clear(invalidated: Bool = false) {
    preview = nil; selection = []; source = nil; share = nil; confirming = false; changed = invalidated
  }

  private func load() {
    guard canRead else { return }
    do {
      let value = try records.localCareVisitPreview(id: id, metric: metric, sections: sections, language: language)
      selection = Set(value.items.map(\.id))
      changed = false
      preview = value
    } catch { clear(invalidated: true) }
  }

  private func validate(_ preview: Visit.Preview) throws {
    guard canRead else { throw GalaxySSIHealthRecords.Failure.permission }
    let now = Date()
    let current = try records.localCareVisitPreview(id: id, metric: metric, sections: preview.sections,
      language: language, now: now)
    try preview.revalidate(current, at: now)
  }

  private func openSource(_ item: Visit.Item, preview: Visit.Preview) {
    guard let reference = item.record else { return }
    do {
      try validate(preview)
      source = .init(reading: try records.localCareVisitSource(reference, metric: metric), item: item)
    } catch { clear(invalidated: true) }
  }

  private func confirmShare() {
    guard let preview else { return }
    do {
      try validate(preview)
      let text = try preview.text(for: selection)
      clear()
      share = .init(text: text)
    } catch { clear(invalidated: true) }
  }
}

private struct GalaxySSIHealthCareVisitShareSheet: UIViewControllerRepresentable {
  let text: String
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [text], applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
