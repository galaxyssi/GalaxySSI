@preconcurrency import CoreBluetooth
import CryptoKit
import Foundation
import SwiftUI

struct GalaxySSIHealthBluetoothPacket: Codable, Equatable {
  let systolic: Decimal
  let diastolic: Decimal
  let pulse: Decimal?
  let kilopascals: Bool
  let deviceClock: String?
  let slot: Int?
  let status: Int?
  let fingerprint: String

  static func decode(_ data: Data) -> Self? {
    let bytes = Array(data)
    guard let flags = bytes.first, flags & 0xe0 == 0 else { return nil }
    let clock = flags & 2 != 0, pulse = flags & 4 != 0, slot = flags & 8 != 0, status = flags & 16 != 0
    guard bytes.count == 7 + (clock ? 7 : 0) + (pulse ? 2 : 0) + (slot ? 1 : 0) + (status ? 2 : 0) else { return nil }
    var offset = 1
    func byte() -> Int { defer { offset += 1 }; return Int(bytes[offset]) }
    func word() -> Int { let low = byte(); return low | (byte() << 8) }
    guard let upper = sfloat(word()), let lower = sfloat(word()), upper > lower, lower > 0 else { return nil }
    _ = word()
    var timestamp: String?
    if clock {
      let year = word(), month = byte(), day = byte(), hour = byte(), minute = byte(), second = byte()
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
      let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
      if (1970...9999).contains(year), parts.isValidDate(in: calendar) {
        timestamp = String(format: "%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
      }
    }
    let heartRate = pulse ? sfloat(word()).flatMap { $0 > 0 ? $0 : nil } : nil
    let user = slot ? byte() : nil
    let measurementStatus = status ? word() : nil
    return Self(systolic: upper, diastolic: lower, pulse: heartRate, kilopascals: flags & 1 != 0,
                deviceClock: timestamp, slot: user, status: measurementStatus,
                fingerprint: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
  }

  private static func sfloat(_ word: Int) -> Decimal? {
    guard !(0x07fe...0x0802).contains(word) else { return nil }
    let mantissa = word & 0xfff
    let exponent = word >> 12
    var value = Decimal(mantissa >= 0x800 ? mantissa - 0x1000 : mantissa)
    let power = exponent >= 8 ? exponent - 16 : exponent
    for _ in 0..<abs(power) { if power < 0 { value /= 10 } else { value *= 10 } }
    return value
  }
}

struct GalaxySSIHealthBluetoothReceipt: Codable, Equatable {
  let device: UUID
  let receivedAt: Date
  let packet: GalaxySSIHealthBluetoothPacket

  func isReplay(of previous: Self) -> Bool {
    guard device == previous.device else { return false }
    if let clock = packet.deviceClock, let previousClock = previous.packet.deviceClock {
      return clock == previousClock && packet.slot == previous.packet.slot
    }
    return packet.fingerprint == previous.packet.fingerprint &&
      abs(receivedAt.timeIntervalSince(previous.receivedAt)) < 60
  }

  func reading(conditions: String) -> GalaxySSIHealthReading {
    let factor = packet.kilopascals ? (Decimal(string: "7.500616827", locale: Locale(identifier: "en_US_POSIX")) ?? 1) : 1
    return GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: receivedAt, value: packet.systolic * factor,
                                   diastolic: packet.diastolic * factor, pulse: packet.pulse,
                                   conditions: conditions, bluetoothReceipt: self)
  }
}

@MainActor
final class GalaxySSIHealthBluetoothSession: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  enum State { case idle, starting, scanning, choosing, connecting, listening, failed }
  struct Device: Identifiable {
    let id: UUID
    let name: String
  }

  @Published private(set) var state = State.idle
  @Published private(set) var devices: [Device] = []
  @Published private(set) var reading: GalaxySSIHealthBluetoothReceipt?
  private static let serviceID = CBUUID(string: "1810")
  private static let measurementID = CBUUID(string: "2A35")
  private var central: CBCentralManager?
  private var candidates: [UUID: CBPeripheral] = [:]
  private var selected: CBPeripheral?
  private var characteristic: CBCharacteristic?
  private var timeout: Task<Void, Never>?

  func start() {
    stop()
    state = .starting
    central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    expire(after: 30)
  }

  func connect(_ id: UUID) {
    guard let central, state == .scanning || state == .choosing, let peripheral = candidates[id] else { return }
    central.stopScan()
    selected = peripheral
    state = .connecting
    central.connect(peripheral)
    expire(after: 20)
  }

  func stop() {
    timeout?.cancel()
    timeout = nil
    central?.stopScan()
    if let selected { central?.cancelPeripheralConnection(selected) }
    selected?.delegate = nil
    central?.delegate = nil
    central = nil
    selected = nil
    characteristic = nil
    candidates = [:]
    devices = []
    reading = nil
    state = .idle
  }

  func clearReading() { reading = nil }

  private func fail() { stop(); state = .failed }

  private func expire(after seconds: UInt64) {
    timeout?.cancel()
    timeout = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) }
      catch { return }
      guard let self, !Task.isCancelled else { return }
      if self.state == .scanning && !self.devices.isEmpty {
        self.central?.stopScan()
        self.state = .choosing
      } else { self.fail() }
    }
  }

  func centralManagerDidUpdateState(_ manager: CBCentralManager) {
    guard manager === central else { return }
    if manager.state == .poweredOn && state == .starting {
      state = .scanning
      manager.scanForPeripherals(withServices: [Self.serviceID])
      expire(after: 20)
    } else if manager.state != .poweredOn && manager.state != .unknown && manager.state != .resetting {
      fail()
    }
  }

  func centralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral,
                      advertisementData: [String: Any], rssi RSSI: NSNumber) {
    guard manager === central, state == .scanning, devices.count < 20, candidates[peripheral.identifier] == nil,
          (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.contains(Self.serviceID) == true
    else { return }
    candidates[peripheral.identifier] = peripheral
    devices.append(Device(id: peripheral.identifier, name: String((peripheral.name ?? "").prefix(100))))
  }

  func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard manager === central, peripheral === selected, state == .connecting else { return }
    peripheral.delegate = self
    peripheral.discoverServices([Self.serviceID])
  }

  func centralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    if manager === central && peripheral === selected { fail() }
  }

  func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    guard manager === central, peripheral === selected else { return }
    let captured = reading
    if let captured { stop(); reading = captured } else { fail() }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard peripheral === selected, state == .connecting else { return }
    guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID })
    else { fail(); return }
    peripheral.discoverCharacteristics([Self.measurementID], for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard peripheral === selected, state == .connecting else { return }
    guard error == nil, service.uuid == Self.serviceID,
          let measurement = service.characteristics?.first(where: { $0.uuid == Self.measurementID && $0.properties.contains(.indicate) })
    else { fail(); return }
    characteristic = measurement
    peripheral.setNotifyValue(true, for: measurement)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    guard peripheral === selected, characteristic === self.characteristic else { return }
    guard error == nil, characteristic.isNotifying else { fail(); return }
    timeout?.cancel()
    state = .listening
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard peripheral === selected, characteristic === self.characteristic, characteristic.isNotifying, state == .listening,
          error == nil, reading == nil, let data = characteristic.value,
          let packet = GalaxySSIHealthBluetoothPacket.decode(data) else { return }
    reading = .init(device: peripheral.identifier, receivedAt: Date(), packet: packet)
  }
}

@MainActor
struct GalaxySSIHealthBluetoothView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @StateObject private var session = GalaxySSIHealthBluetoothSession()
  @State private var conditions = ""
  @State private var mine = false
  @State private var outcome: Outcome?
  let records: GalaxySSIHealthRecords

  private enum Outcome { case saved, duplicate, failed }

  var body: some View {
    Form {
      if scene == .active {
        Section(t("device", "Blood pressure monitor")) {
          Text(status)
          if session.state == .idle || session.state == .failed {
            Button(t("scan", "Scan for monitors")) { clear(); session.start() }
          } else {
            Button(t("disconnect", "Stop and disconnect"), role: .destructive) { session.stop(); clear() }
          }
          if session.state == .scanning || session.state == .choosing {
            ForEach(session.devices) { device in
              Button(device.name.isEmpty ? device.id.uuidString : device.name) { session.connect(device.id) }
            }
          }
        }
        if let receipt = session.reading {
          Section(t("review", "Confirm received measurement")) {
            let packet = receipt.packet
            Text("\(packet.systolic.formatted()) / \(packet.diastolic.formatted()) \(packet.kilopascals ? "kPa" : "mmHg")")
            if let pulse = packet.pulse { Text(pulse.formatted() + " bpm") }
            if let deviceClock = packet.deviceClock {
              Text(t("clock", "Device clock (unverified)") + ": " + deviceClock).foregroundColor(.secondary)
            }
            if let slot = packet.slot {
              Text(t("slot", "Device user slot") + ": " + String(slot)).foregroundColor(.secondary)
            }
            if let status = packet.status, status != 0 {
              Text(t("status", "Monitor reported a status flag") + ": " + String(status))
                .foregroundColor(.secondary)
            }
            Text(t("receipt", "Received at") + ": " + receipt.receivedAt.formatted()).foregroundColor(.secondary)
            TextField(t("conditions", "Conditions"), text: $conditions)
            Toggle(t("mine", "This is my measurement"), isOn: $mine)
            Button(t("save", "Save measurement")) { save(receipt) }.disabled(!mine)
            Button(t("discard", "Discard reading"), role: .destructive) { session.clearReading(); clear() }
          }
        }
        if let outcome {
          switch outcome {
          case .saved: Text(t("saved", "Measurement saved"))
          case .duplicate: Text(t("duplicate", "This measurement was already received or recorded."))
          case .failed: Text(t("save_failed", "Could not save the measurement."))
          }
        }
      }
    }
    .navigationTitle(t("title", "Bluetooth Blood Pressure"))
    .navigationBarTitleDisplayMode(.inline)
    .onDisappear { session.stop(); clear() }
    .onChange(of: scene) { if $0 != .active { session.stop(); clear() } }
  }

  private var status: String {
    switch session.state {
    case .idle: return t("idle", "Not connected")
    case .starting, .scanning: return t("scanning", "Looking for blood pressure monitors")
    case .choosing: return t("choose", "Select a monitor")
    case .connecting: return t("connecting", "Checking the monitor")
    case .listening: return t("listening", "Ready to receive a measurement")
    case .failed: return t("failed", "Monitor unavailable. Check Bluetooth access and try again.")
    }
  }

  private func save(_ receipt: GalaxySSIHealthBluetoothReceipt) {
    guard mine, scene == .active, session.reading == receipt else { return }
    do {
      try records.write(receipt.reading(conditions: conditions))
      session.clearReading()
      clear()
      outcome = .saved
    } catch GalaxySSIHealthRecords.Failure.duplicate {
      session.clearReading()
      clear()
      outcome = .duplicate
    } catch { outcome = .failed }
  }

  private func clear() { conditions = ""; mine = false; outcome = nil }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.bluetooth." + key, fallback: fallback, language: language)
  }
}
