import Foundation
import UniformTypeIdentifiers

enum GalaxySSIHealthStructuredOriginal {
  static let extensions: Set<String> = ["csv", "json", "xlsx"]
  static let workbookType = UTType(filenameExtension: "xlsx") ?? .spreadsheet
  static var contentTypes: [UTType] { [.commaSeparatedText, .json, workbookType] }

  struct Sheet: Identifiable, Sendable {
    let id: String
    let name: String
  }
  struct Preview: Sendable {
    let sheets: [Sheet]
    let sheetID: String
    let sample: GalaxySSIHealthTableSourceSample
  }

  static func read(_ data: Data, fileExtension: String, sheetID: String = "",
                   jsonHeaders: [String] = ["Key", "Value"]) throws -> Preview {
    guard !data.isEmpty, data.count <= GalaxySSIHealthTableImport.maximumBytes,
          extensions.contains(fileExtension), jsonHeaders.count == 2 else { throw GalaxySSIHealthTableImport.Failure.limit }
    try Task.checkCancellation()
    if fileExtension == "xlsx" {
      let workbook = try GalaxySSIHealthXLSX(data)
      let sheets = workbook.sheets.map { Sheet(id: $0.id, name: $0.name) }
      guard let first = sheets.first else { throw GalaxySSIHealthTableImport.Failure.malformed }
      let selected = sheetID.isEmpty ? first.id : sheetID
      let rows = try workbook.previewRows(selected)
      return Preview(sheets: sheets, sheetID: selected,
        sample: .init(sheetRows: rows, rowLimit: 20, cellLimit: 512))
    }
    let rows: [[String]], headers: [String]
    if fileExtension == "csv" {
      rows = try GalaxySSIHealthTableImport.csvRecords(data, sampleOnly: true)
      headers = Array(repeating: "", count: min(16_384, rows.map(\.count).max() ?? 1))
    } else {
      // Foundation owns JSON syntax validation. The delimiter scan below only
      // selects already-valid raw fragments, preserving numeric lexemes and order.
      _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
      guard var text = String(data: data, encoding: .utf8) else { throw GalaxySSIHealthTableImport.Failure.malformed }
      if text.first == "\u{feff}" { text.removeFirst() }
      text = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.first == "{" {
        rows = try fragments(String(text.dropFirst().dropLast()), delimiter: 44, limit: 21).map { field in
          let pair = try fragments(field, delimiter: 58, limit: 2)
          guard pair.count == 2 else { throw GalaxySSIHealthTableImport.Failure.malformed }
          let key = try JSONDecoder().decode(String.self, from: Data(pair[0].utf8))
          return [key, pair[1]]
        }
        headers = jsonHeaders
      } else if text.first == "[" {
        rows = try fragments(String(text.dropFirst().dropLast()), delimiter: 44, limit: 21).map { [$0] }
        headers = [jsonHeaders.last ?? "Value"]
      } else { rows = [[text]]; headers = [jsonHeaders.last ?? "Value"] }
    }
    try Task.checkCancellation()
    let sample = GalaxySSIHealthTableSourceSample(.init(headers: headers, rows: rows), rowLimit: 20, cellLimit: 512)
    return Preview(sheets: [], sheetID: "", sample: sample)
  }

  private static func fragments(_ text: String, delimiter: UInt8, limit: Int) throws -> [String] {
    let bytes = Array(text.utf8)
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
    var result: [String] = [], start = 0, depth = 0, quoted = false, escaped = false
    for (index, byte) in bytes.enumerated() {
      if index.isMultiple(of: 4096) { try Task.checkCancellation() }
      if quoted {
        if escaped { escaped = false }
        else if byte == 92 { escaped = true }
        else if byte == 34 { quoted = false }
      } else if byte == 34 { quoted = true }
      else if byte == 123 || byte == 91 { depth += 1 }
      else if byte == 125 || byte == 93 { depth -= 1 }
      else if byte == delimiter, depth == 0, result.count < limit - 1 {
        result.append(String(decoding: bytes[start..<index], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        start = index + 1
      } else if byte == delimiter, depth == 0, result.count == limit - 1, delimiter == 44 {
        result.append(String(decoding: bytes[start..<index], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        return result
      }
    }
    result.append(String(decoding: bytes[start...], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    return result
  }
}
