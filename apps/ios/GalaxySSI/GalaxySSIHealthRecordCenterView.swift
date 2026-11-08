import SwiftUI

struct GalaxySSIHealthRecordCenterSnapshot {
  struct Pending: Identifiable {
    let original: GalaxySSIHealthOriginalStore.Original?
    let sourceID: UUID
    let sha256: String
    let items: [GalaxySSIHealthReportReview.Item]
    var id: String { sourceID.uuidString + ":" + sha256 }
  }
  let confirmed: [GalaxySSIHealthReading]
  let pending: [Pending]
  let draft: GalaxySSIHealthDraft?

  init(archive: GalaxySSIHealthRecords.Archive, originals: [GalaxySSIHealthOriginalStore.Original]) {
    confirmed = archive.current
    draft = archive.draft
    let grouped = Dictionary(grouping: archive.reportReview ?? []) {
      $0.source.original.uuidString + ":" + $0.source.sha256
    }
    pending = grouped.keys.sorted().compactMap { key in
      guard let items = grouped[key], let source = items.first?.source else { return nil }
      let original = originals.first { $0.id == source.original && $0.sha256 == source.sha256 }
      return Pending(original: original, sourceID: source.original, sha256: source.sha256, items: items)
    }
  }
}

@MainActor
struct GalaxySSIHealthRecordCenterView<Devices: View>: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let devices: () -> Devices
  let addManual: (GalaxySSIHealthMetric?) -> Void
  let edit: (GalaxySSIHealthReading) -> Void
  @State private var snapshot: GalaxySSIHealthRecordCenterSnapshot?
  @State private var failed = false
  @State private var pendingLimit = 3
  @State private var recentLimit = 3
  private var originals: GalaxySSIHealthOriginalStore {
    GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets)
  }

  var body: some View {
    List {
      if scene == .active {
        Section(t("record_center.entry", "Record health data")) {
          NavigationLink {
            GalaxySSIHealthPhotoCaptureView(records: records, originals: originals)
          } label: { Label(t("record_center.photos", "Capture health photos"), systemImage: "camera") }
          Button { addManual(nil) } label: {
            Label(t("manual", "Record measurement"), systemImage: "square.and.pencil")
          }
          NavigationLink {
            GalaxySSIHealthImportView(store: originals, records: records)
          } label: { Label(t("record_center.files", "Import files"), systemImage: "folder") }
          NavigationLink(destination: devices) {
            Label(t("sources", "Devices & Data Sources"), systemImage: "externaldrive.connected.to.line.below")
          }
        }
        if failed {
          Text(t("unavailable", "Health records could not be accessed."))
          Button(t("retry", "Reload records"), action: reload)
        }
        if let snapshot {
          Section(t("record_center.pending", "Pending review")) {
            if snapshot.draft != nil {
              Button { addManual(nil) } label: { Label(t("resume_draft", "Resume draft"), systemImage: "doc.text") }
            }
            if snapshot.pending.isEmpty, snapshot.draft == nil {
              Text(t("record_center.no_pending", "No pending reviews")).foregroundColor(.secondary)
            }
            ForEach(snapshot.pending.prefix(pendingLimit)) { group in
              if let original = group.original {
                NavigationLink {
                  GalaxySSIHealthReportBatchView(records: records, store: originals, original: original)
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(original.name)
                    Text(String(format: t("record_center.review_count", "%lld reviewed drafts"), Int64(group.items.count)))
                      .font(.caption).foregroundColor(.secondary)
                  }
                }
              } else {
                Label(t("record_center.source_missing", "Review source unavailable or changed"), systemImage: "exclamationmark.triangle")
                  .foregroundColor(.secondary)
              }
            }
            if snapshot.pending.count > pendingLimit {
              Button(t("record_center.all_pending", "Show all pending reviews")) { pendingLimit += 30 }
            }
            NavigationLink {
              GalaxySSIHealthTableImportView(records: records)
            } label: { Label(t("record_center.tables", "Table review and import history"), systemImage: "tablecells") }
          }
          Section(t("recent", "Recent measurements")) {
            if snapshot.confirmed.isEmpty {
              Text(t("first_use.title", "No confirmed measurements yet")).foregroundColor(.secondary)
            }
            ForEach(snapshot.confirmed.prefix(recentLimit)) { reading in
              Button { edit(reading) } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(reading.metric.title(language: language))
                  Text((reading.value?.formatted() ?? "") + " " + reading.unit).foregroundColor(.secondary)
                  Text(reading.measuredAt, format: .dateTime).font(.caption).foregroundColor(.secondary)
                }
              }.disabled(snapshot.draft != nil)
            }
            if snapshot.confirmed.count > recentLimit {
              Button(t("more", "Show more")) { recentLimit += 30 }
            }
          }
        }
        NavigationLink {
          GalaxySSIHealthOriginalsView(store: originals)
        } label: { Label(t("originals.title", "Health Originals"), systemImage: "doc.on.doc") }
        NavigationLink {
          GalaxySSIHealthMetricCatalogView(records: records, add: { addManual($0) }, edit: edit)
        } label: { Label(t("catalog.title", "Measurement Catalog"), systemImage: "list.bullet.rectangle") }
      }
    }
    .navigationTitle(t("record_center.title", "Health Record Center"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) { if $0 == .active { reload() } else { snapshot = nil; failed = false } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { notification in
      if notification.object as? String == records.owner { reload() }
    }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      snapshot = GalaxySSIHealthRecordCenterSnapshot(archive: try records.load(), originals: try originals.list().originals)
      failed = false
    } catch { snapshot = nil; failed = true }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health." + key, fallback: fallback, language: language)
  }
}
