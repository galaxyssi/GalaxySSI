import CryptoKit
import Foundation

enum GalaxySSIHealthTableImport {
  static let maximumBytes = 1_048_576
  private static let maximumRows = 500
  private static let maximumColumns = 64

  enum Failure: Error { case malformed, limit, mapping, stale }
  enum DateStyle: String, CaseIterable { case iso, localTime, day, excel }
  enum Status: String { case ready, duplicate, missing, invalid }

  struct Source: Codable, Equatable {
    let batch: UUID
    let row: Int
    let sha256: String
    var sheet: String?
    var worksheetPath: String?
    var columns: [String: Int]?
  }

  struct Batch: Codable, Identifiable {
    let id: UUID
    let name: String
    let at: Date
    let data: Data
    let inserted: Int
    var undone: Int?
  }

  struct Table {
    let headers: [String]
    let rows: [[String]]
    var sheet: String?
    var sheetPath: String?
    var rowNumbers: [Int]?
    var formulas: [Set<Int>]?
    var date1904: Bool?
  }

  struct Mapping: Equatable {
    var metric = GalaxySSIHealthMetric.bloodPressure
    var value = -1
    var date = -1
    var lower = -1
    var pulse = -1
    var notes = -1
    var confirmedUnit = false
    var dateStyle = DateStyle.iso
    var localZone = TimeZone.current
    var useFormulaCache = false
    var unitOverride: String?

    var sourceColumns: [String: Int] {
      var result = ["value": value, "measured_at": date, "notes": notes]
      if metric == .bloodPressure { result["diastolic"] = lower; result["pulse"] = pulse }
      return result.filter { $0.value >= 0 }
    }
  }

  struct Row: Identifiable {
    let id: Int
    let status: Status
    let reading: GalaxySSIHealthReading?
    let rawValue: String
    let rawDate: String
  }

  static func parse(_ data: Data, json: Bool) throws -> Table {
    guard !data.isEmpty, data.count <= maximumBytes else { throw Failure.limit }
    if json { return try parseJSON(data) }
    return try parseCSV(data)
  }

  static func preview(_ table: Table, mapping: Mapping, current: [GalaxySSIHealthReading]) throws -> [Row] {
    let isPressure = mapping.metric == .bloodPressure
    let required = isPressure ? [mapping.value, mapping.date, mapping.lower] : [mapping.value, mapping.date]
    let optional = (isPressure ? [mapping.pulse, mapping.notes] : [mapping.notes]).filter { $0 >= 0 }
    let used = required + optional
    guard mapping.confirmedUnit, mapping.dateStyle != .excel || table.date1904 != nil,
          Set(used).count == used.count,
          used.allSatisfy({ table.headers.indices.contains($0) }) else { throw Failure.mapping }
    let iso = ISO8601DateFormatter()
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let local = DateFormatter()
    local.locale = Locale(identifier: "en_US_POSIX")
    local.calendar = Calendar(identifier: .gregorian)
    local.timeZone = mapping.localZone
    local.isLenient = false
    local.dateFormat = mapping.dateStyle == .day ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm:ss"
    let now = Date()
    var accepted = current.filter { $0.metric == mapping.metric }
    return table.rows.enumerated().map { index, values in
      func cell(_ column: Int) -> String { values.indices.contains(column) ? values[column] : "" }
      func token(_ column: Int) -> String { cell(column).trimmingCharacters(in: .whitespacesAndNewlines) }
      let rawValue = token(mapping.value), rawDate = token(mapping.date)
      func row(_ status: Status, _ reading: GalaxySSIHealthReading? = nil) -> Row {
        Row(id: table.rowNumbers?[index] ?? index + 1, status: status, reading: reading, rawValue: rawValue, rawDate: rawDate)
      }
      if !mapping.useFormulaCache, let formulas = table.formulas?[index],
         used.contains(where: { formulas.contains($0) }) { return row(.invalid) }
      guard required.allSatisfy({ !token($0).isEmpty }) else { return row(.missing) }
      let time: Date?
      if mapping.dateStyle == .iso {
        time = fractional.date(from: rawDate) ?? iso.date(from: rawDate)
      } else if mapping.dateStyle == .excel, let serial = number(rawDate), let date1904 = table.date1904 {
        time = GalaxySSIHealthXLSX.date(serial: serial, date1904: date1904, zone: mapping.localZone)
      } else if mapping.dateStyle != .excel, let parsed = local.date(from: rawDate), local.string(from: parsed) == rawDate {
        time = parsed
      } else { time = nil }
      let reported = GalaxySSIHealthReportedResult.parse(rawValue, metric: mapping.metric)
      let value = reported == nil ? number(rawValue) : nil
      guard value != nil || reported != nil, let time, time <= now else { return row(.invalid) }
      let lower = isPressure ? number(token(mapping.lower)) : nil
      let pulseText = isPressure ? token(mapping.pulse) : ""
      let pulse = number(pulseText)
      guard pulseText.isEmpty || pulse != nil else { return row(.invalid) }
      let reading = GalaxySSIHealthReading(metric: mapping.metric, measuredAt: time, value: value,
        diastolic: lower, pulse: pulse, notes: cell(mapping.notes), reported: reported, reportedNotation: rawValue,
        unitOverride: reported?.kind == .qualitative ? "" : mapping.unitOverride)
      guard reading.isValid else { return row(.invalid) }
      guard !accepted.contains(where: { $0.sameMeasurement(as: reading) }) else { return row(.duplicate, reading) }
      accepted.append(reading)
      return row(.ready, reading)
    }
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func number(_ text: String) -> Decimal? {
    guard text.utf8.count <= 64,
          text.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$"#, options: .regularExpression) != nil
    else { return nil }
    return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
  }

  private static func parseCSV(_ data: Data) throws -> Table {
    guard String(data: data, encoding: .utf8) != nil else { throw Failure.malformed }
    let bytes = Array(data)
    var index = bytes.starts(with: [239, 187, 191]) ? 3 : 0
    var rows: [[String]] = [], row: [String] = [], field: [UInt8] = []
    var quoted = false, closed = false
    func endField() throws {
      guard row.count < maximumColumns, field.count <= 8_192 else { throw Failure.limit }
      row.append(String(decoding: field, as: UTF8.self))
      field.removeAll(keepingCapacity: true)
      closed = false
    }
    func endRow() throws {
      try endField()
      if row.contains(where: { !$0.isEmpty }) {
        guard rows.count < maximumRows + 1 else { throw Failure.limit }
        rows.append(row)
      }
      row.removeAll(keepingCapacity: true)
    }
    while index < bytes.count {
      let byte = bytes[index]
      index += 1
      if quoted {
        if byte == 34 {
          if index < bytes.count, bytes[index] == 34 { field.append(34); index += 1 }
          else { quoted = false; closed = true }
        } else { field.append(byte) }
      } else if byte == 44 {
        try endField()
      } else if byte == 13 || byte == 10 {
        if byte == 13, index < bytes.count, bytes[index] == 10 { index += 1 }
        try endRow()
      } else if !closed, byte == 34, field.isEmpty {
        quoted = true
      } else if !closed, byte != 34 {
        field.append(byte)
      } else { throw Failure.malformed }
      if field.count > 8_192 { throw Failure.limit }
    }
    guard !quoted else { throw Failure.malformed }
    if !row.isEmpty || !field.isEmpty || closed { try endRow() }
    guard let header = rows.first, header.count >= 2, rows.count > 1,
          rows.dropFirst().allSatisfy({ $0.count <= header.count }) else { throw Failure.malformed }
    return Table(headers: header, rows: Array(rows.dropFirst()))
  }

  private struct JSONRow: Decodable {
    let cells: [String: Cell]
    init(from decoder: Decoder) throws {
      cells = try decoder.singleValueContainer().decode([String: Cell].self)
    }
  }

  private struct JSONEnvelope: Decodable { let measurements: [JSONRow] }

  private struct Cell: Decodable {
    let text: String
    init(from decoder: Decoder) throws {
      let value = try decoder.singleValueContainer()
      if value.decodeNil() { text = "" }
      else if let string = try? value.decode(String.self) { text = string }
      else if let decimal = try? value.decode(Decimal.self), !decimal.isNaN {
        text = NSDecimalNumber(decimal: decimal).description(withLocale: Locale(identifier: "en_US_POSIX"))
      } else if let boolean = try? value.decode(Bool.self) { text = boolean ? "true" : "false" }
      else { throw Failure.malformed }
      guard text.utf8.count <= 8_192 else { throw Failure.limit }
    }
  }

  private static func parseJSON(_ data: Data) throws -> Table {
    let decoder = JSONDecoder()
    let rows: [JSONRow]
    if let array = try? decoder.decode([JSONRow].self, from: data) { rows = array }
    else { rows = try decoder.decode(JSONEnvelope.self, from: data).measurements }
    guard !rows.isEmpty, rows.count <= maximumRows else { throw Failure.limit }
    var columns = Set<String>()
    for row in rows {
      columns.formUnion(row.cells.keys)
      guard columns.count <= maximumColumns else { throw Failure.limit }
    }
    let headers = columns.sorted()
    guard headers.count >= 2 else { throw Failure.malformed }
    return Table(headers: headers, rows: rows.map { row in headers.map { row.cells[$0]?.text ?? "" } })
  }
}
