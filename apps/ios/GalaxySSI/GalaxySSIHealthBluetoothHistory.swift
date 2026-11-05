import SwiftUI

struct GalaxySSIHealthBluetoothHistory {
  struct Device: Identifiable {
    let id: UUID
    let name: String?
    let ordinal: Int
    let latest: GalaxySSIHealthReading
  }

  let devices: [Device]
  private let readingsByDevice: [UUID: [GalaxySSIHealthReading]]

  @MainActor
  init?(visibleArchive archive: GalaxySSIHealthRecords.Archive) {
    guard archive.derivesOverview == true else { return nil }
    self.init(current: archive.current)
  }

  func readings(for device: UUID) -> [GalaxySSIHealthReading] {
    (readingsByDevice[device] ?? []).sorted { Self.earlier($1, $0) }
  }

  private static func earlier(_ left: GalaxySSIHealthReading, _ right: GalaxySSIHealthReading) -> Bool {
    (left.measuredAt, left.id.uuidString) < (right.measuredAt, right.id.uuidString)
  }

  init(current: [GalaxySSIHealthReading]) {
    var grouped: [UUID: [GalaxySSIHealthReading]] = [:]
    for reading in current where !reading.deleted && reading.metric == .bloodPressure {
      guard let receipt = reading.bluetoothReceipt else { continue }
      grouped[receipt.device, default: []].append(reading)
    }
    readingsByDevice = grouped
    let ids = grouped.keys.sorted { $0.uuidString < $1.uuidString }
    devices = ids.enumerated().compactMap { index, id in
      guard let records = grouped[id], let latest = records.max(by: Self.earlier) else { return nil }
      let name = records.lazy.compactMap { reading -> (Date, String)? in
        guard let receipt = reading.bluetoothReceipt,
              let name = receipt.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return (receipt.receivedAt, name)
      }.max { $0 < $1 }?.1
      return Device(id: id, name: name, ordinal: index + 1, latest: latest)
    }.sorted {
      ($0.latest.measuredAt, $0.id.uuidString) > ($1.latest.measuredAt, $1.id.uuidString)
    }
  }
}

@MainActor
struct GalaxySSIHealthBluetoothHistorySection: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  @State private var history: GalaxySSIHealthBluetoothHistory?
  @SceneStorage("galaxyssi.health.bluetooth-history.expanded") private var expanded = false
  @SceneStorage("galaxyssi.health.bluetooth-history.page") private var page = 0
  @State private var visible = false
  @State private var failed = false
  @State private var selection: Selection?
  @State private var readingLimit = 30
  @State private var selectedReadings: [GalaxySSIHealthReading] = []
  @State private var deletion: GalaxySSIHealthMetricDeletion.Preview?
  @State private var confirmingDeletion = false
  @State private var deletionNotice: String?

  private struct Selection: Identifiable { let id: UUID }

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      if scene == .active && expanded {
        if failed {
          Text(t("failed", "Saved Bluetooth history is unavailable."))
          Button(t("retry", "Reload"), action: reload)
        } else if let history {
          if selection == nil, let deletionNotice { Text(deletionNotice).foregroundColor(.secondary) }
          if history.devices.isEmpty { Text(t("empty", "No saved Bluetooth measurements.")) }
          let start = min(max(0, page), max(0, (history.devices.count - 1) / 30)) * 30
          ForEach(history.devices.dropFirst(start).prefix(30)) { device in
            Button {
              readingLimit = 30
              deletionNotice = nil
              selectedReadings = history.readings(for: device.id)
              selection = Selection(id: device.id)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(title(device)).foregroundColor(.primary)
                summary(device.latest).foregroundColor(.secondary)
              }
            }
          }
          if history.devices.count > 30 {
            HStack {
              Button(t("previous", "Previous")) { page = max(0, start / 30 - 1) }.disabled(start == 0)
              Spacer()
              Button(t("next", "Next")) { page = start / 30 + 1 }.disabled(start + 30 >= history.devices.count)
            }
            .buttonStyle(.borderless)
          }
        } else {
          Text(t("permission", "Enable the local measurement summary in Health Privacy to see Bluetooth history."))
        }
      }
    } label: {
      Label(t("title", "Saved Bluetooth Devices"), systemImage: "clock.arrow.circlepath")
    }
    .onAppear { visible = true; reload() }
    .onDisappear { visible = false; clear() }
    .onChange(of: expanded) { if $0 { reload() } else { clear() } }
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .sheet(item: $selection, onDismiss: clearDetail) { selected in
      NavigationView {
        if scene == .active, let device = history?.devices.first(where: { $0.id == selected.id }) {
          List {
            deletionControls(device)
            ForEach(selectedReadings.prefix(readingLimit)) { reading in
              summary(reading)
            }
            if selectedReadings.count > readingLimit {
              Button(t("more", "Show more records")) { readingLimit += 30 }
            }
          }
          .navigationTitle(title(device))
          .navigationBarTitleDisplayMode(.inline)
          .alert(t("erase_confirm", "Permanently delete this device's local history?"),
                 isPresented: $confirmingDeletion) {
            Button(t("erase", "Delete local history"), role: .destructive) { erase(device.id) }
            Button(t("cancel", "Cancel"), role: .cancel) { deletion = nil }
          }
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("close", "Close")) { selection = nil }
          } }
        }
      }
      .navigationViewStyle(.stack)
    }
  }

  @ViewBuilder
  private func deletionControls(_ device: GalaxySSIHealthBluetoothHistory.Device) -> some View {
    if let deletionNotice { Text(deletionNotice).foregroundColor(.secondary) }
    if let deletion, deletion.bluetoothDevice == device.id {
      Section(t("erase_review", "Review local history deletion")) {
        Text(title(device)).font(.headline)
        Text(String(format: t("erase_count", "Stored measurements: %lld"), Int64(deletion.scope.count)))
        if let earliest = deletion.scope.earliest, let latest = deletion.scope.latest {
          Text(String(format: t("erase_dates", "%@ to %@"), earliest.formatted(date: .abbreviated, time: .omitted),
                      latest.formatted(date: .abbreviated, time: .omitted)))
        }
        Text(t("erase_boundary", "Only this device's local measurements and linked drafts are removed. Other devices, pairing, original files, exports and backups are unchanged."))
          .foregroundColor(.secondary)
        Button(t("erase", "Delete local history"), role: .destructive) { confirmingDeletion = true }
        Button(t("cancel", "Cancel")) { self.deletion = nil }
      }
    } else {
      Button(t("erase_review", "Review local history deletion"), role: .destructive) { prepareDeletion(device.id) }
    }
  }

  private func prepareDeletion(_ device: UUID) {
    guard scene == .active, selection?.id == device else { return }
    deletionNotice = nil
    do {
      let preview = try records.previewBluetoothHistoryDeletion(device: device)
      if preview.scope.isEmpty { deletionNotice = t("empty", "No saved Bluetooth measurements.") }
      else { deletion = preview }
    } catch GalaxySSIHealthRecords.Failure.permission { clear() }
    catch { deletionNotice = t("erase_failed", "Could not delete this device's local history.") }
  }

  private func erase(_ device: UUID) {
    guard scene == .active, selection?.id == device, let deletion, deletion.bluetoothDevice == device else { return }
    self.deletion = nil
    do {
      try records.deleteMetricHistory(deletion)
      deletionNotice = t("erase_done", "This device's local history was deleted.")
    } catch GalaxySSIHealthRecords.Failure.permission { clear() }
    catch GalaxySSIHealthRecords.Failure.stale {
      deletionNotice = t("erase_changed", "This device's history or access changed. Review it again.")
    } catch { deletionNotice = t("erase_failed", "Could not delete this device's local history.") }
  }

  private func reload() {
    guard visible, expanded, scene == .active else { clear(); return }
    do {
      guard let current = try GalaxySSIHealthBluetoothHistory(visibleArchive: records.load()) else { clear(); return }
      history = current
      if let selection {
        selectedReadings = current.readings(for: selection.id)
        if selectedReadings.isEmpty { self.selection = nil; clearDetail() }
      }
      failed = false
    } catch { clear(); failed = true }
  }

  private func clear() {
    history = nil; selection = nil; failed = false; deletionNotice = nil
    clearDetail()
  }

  private func clearDetail() {
    selectedReadings = []; readingLimit = 30; deletion = nil; confirmingDeletion = false
  }

  private func title(_ device: GalaxySSIHealthBluetoothHistory.Device) -> String {
    (device.name ?? t("unnamed", "Unnamed Bluetooth device")) + " · " + String(device.ordinal)
  }

  private func summary(_ reading: GalaxySSIHealthReading) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if let high = reading.value, let low = reading.diastolic {
        Text(high.formatted() + "/" + low.formatted() + " " + reading.unit)
      }
      Text(t("measured", "Measurement time") + ": " + reading.measuredAt.formatted(date: .abbreviated, time: .shortened))
      if let receipt = reading.bluetoothReceipt {
        Text(t("received", "Receipt time") + ": " + receipt.receivedAt.formatted(date: .abbreviated, time: .shortened))
      }
      Text(String(format: t("revision", "Revision %lld"), Int64(reading.revision)))
    }
    .font(.subheadline)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.bluetooth_history." + key, fallback: fallback, language: language)
  }
}
