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

  private struct Selection: Identifiable { let id: UUID }

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      if scene == .active && expanded {
        if failed {
          Text(t("failed", "Saved Bluetooth history is unavailable."))
          Button(t("retry", "Reload"), action: reload)
        } else if let history {
          if history.devices.isEmpty { Text(t("empty", "No saved Bluetooth measurements.")) }
          let start = min(max(0, page), max(0, (history.devices.count - 1) / 30)) * 30
          ForEach(history.devices.dropFirst(start).prefix(30)) { device in
            Button {
              readingLimit = 30
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
    .sheet(item: $selection, onDismiss: { selectedReadings = [] }) { selected in
      NavigationView {
        if scene == .active, let device = history?.devices.first(where: { $0.id == selected.id }) {
          List {
            ForEach(selectedReadings.prefix(readingLimit)) { reading in
              summary(reading)
            }
            if selectedReadings.count > readingLimit {
              Button(t("more", "Show more records")) { readingLimit += 30 }
            }
          }
          .navigationTitle(title(device))
          .navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("close", "Close")) { selection = nil }
          } }
        }
      }
      .navigationViewStyle(.stack)
    }
  }

  private func reload() {
    guard visible, expanded, scene == .active else { clear(); return }
    do {
      guard let current = try GalaxySSIHealthBluetoothHistory(visibleArchive: records.load()) else { clear(); return }
      history = current
      if let selection {
        selectedReadings = current.readings(for: selection.id)
        if selectedReadings.isEmpty { self.selection = nil }
      }
      failed = false
    } catch { clear(); failed = true }
  }

  private func clear() {
    history = nil; selection = nil; selectedReadings = []; readingLimit = 30; failed = false
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
