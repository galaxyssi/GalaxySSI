import SwiftUI

struct GalaxySSIHealthBluetoothHistory {
  struct Device: Identifiable {
    let id: UUID
    let name: String?
    let ordinal: Int
    let readings: [GalaxySSIHealthReading]
    var latest: GalaxySSIHealthReading? { readings.first }
  }

  let devices: [Device]

  init(current: [GalaxySSIHealthReading]) {
    var grouped: [UUID: [GalaxySSIHealthReading]] = [:]
    for reading in current where !reading.deleted && reading.metric == .bloodPressure {
      guard let receipt = reading.bluetoothReceipt else { continue }
      grouped[receipt.device, default: []].append(reading)
    }
    let ids = grouped.keys.sorted { $0.uuidString < $1.uuidString }
    devices = ids.enumerated().compactMap { index, id in
      guard let records = grouped[id] else { return nil }
      let name = records.compactMap(\.bluetoothReceipt).sorted { $0.receivedAt > $1.receivedAt }
        .lazy.compactMap { $0.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
      let sorted = records.sorted {
        ($0.measuredAt, $0.id.uuidString) > ($1.measuredAt, $1.id.uuidString)
      }
      return Device(id: id, name: name, ordinal: index + 1, readings: sorted)
    }.sorted {
      ($0.latest?.measuredAt ?? .distantPast, $0.id.uuidString) >
        ($1.latest?.measuredAt ?? .distantPast, $1.id.uuidString)
    }
  }
}

@MainActor
struct GalaxySSIHealthBluetoothHistoryView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  @State private var history: GalaxySSIHealthBluetoothHistory?
  @State private var page = 0
  @State private var failed = false
  @State private var selection: Selection?
  @State private var readingLimit = 30

  private struct Selection: Identifiable { let id: UUID }

  var body: some View {
    List {
      if scene == .active {
        if failed {
          Text(t("failed", "Saved Bluetooth history is unavailable."))
          Button(t("retry", "Reload"), action: reload)
        } else if let history {
          if history.devices.isEmpty { Text(t("empty", "No saved Bluetooth measurements.")) }
          let start = min(page * 30, max(0, (history.devices.count - 1) / 30 * 30))
          ForEach(history.devices.dropFirst(start).prefix(30)) { device in
            Button {
              readingLimit = 30
              selection = Selection(id: device.id)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(title(device)).foregroundColor(.primary)
                if let latest = device.latest { summary(latest).foregroundColor(.secondary) }
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
    }
    .navigationTitle(t("title", "Saved Bluetooth Devices"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear(perform: clear)
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .sheet(item: $selection) { selected in
      NavigationView {
        if scene == .active, let device = history?.devices.first(where: { $0.id == selected.id }) {
          List {
            ForEach(device.readings.prefix(readingLimit)) { reading in
              summary(reading)
            }
            if device.readings.count > readingLimit {
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
    guard scene == .active else { clear(); return }
    do {
      let archive = try records.load()
      guard archive.derivesOverview == true else { clear(); return }
      history = GalaxySSIHealthBluetoothHistory(current: archive.current)
      if let selection, history?.devices.contains(where: { $0.id == selection.id }) != true {
        self.selection = nil
      }
      failed = false
    } catch { clear(); failed = true }
  }

  private func clear() {
    history = nil; selection = nil; page = 0; readingLimit = 30; failed = false
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
