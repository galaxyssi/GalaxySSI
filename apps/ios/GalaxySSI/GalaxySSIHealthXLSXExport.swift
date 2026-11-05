import Foundation

enum GalaxySSIHealthXLSXExport {
  private static let maximumSheetBytes = 16 * 1024 * 1024
  private static let literalEscape = try? NSRegularExpression(pattern: "_([xX][0-9a-fA-F]{4}_)")

  static func encode(headers: [String], rows: [[String]]) throws -> Data {
    guard (1...26).contains(headers.count), !rows.isEmpty else { throw CocoaError(.fileWriteUnknown) }
    let opening = #"<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>"#
    let closing = "</sheetData></worksheet>"
    var worksheet = opening
    var length = opening.utf8.count + closing.utf8.count
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    for (index, row) in ([headers] + rows).enumerated() {
      guard row.count == headers.count else { throw CocoaError(.fileWriteUnknown) }
      let number = index + 1
      var line = "<row r=\"\(number)\">"
      for (column, value) in row.enumerated() {
        let reference = String(letters[column]) + String(number)
        line += "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">"
        line += xmlText(value)
        line += "</t></is></c>"
      }
      line += "</row>"
      length += line.utf8.count
      guard length <= maximumSheetBytes else { throw CocoaError(.fileWriteOutOfSpace) }
      worksheet.append(line)
    }
    worksheet.append(closing)
    return AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: [
      entry("[Content_Types].xml", types),
      entry("_rels/.rels", rootRelationships),
      entry("xl/workbook.xml", workbook),
      entry("xl/_rels/workbook.xml.rels", workbookRelationships),
      entry("xl/worksheets/sheet1.xml", worksheet)
    ])
  }

  private static func entry(_ path: String, _ text: String) -> AgentRuntimeProjectArchiveEntry {
    .init(path: path, data: Data(text.utf8))
  }

  private static func xmlText(_ raw: String) -> String {
    let escaped = literalEscape?.stringByReplacingMatches(in: raw,
      range: NSRange(raw.startIndex..<raw.endIndex, in: raw), withTemplate: "_x005F_$1") ?? raw
    var result = ""
    for scalar in escaped.unicodeScalars {
      switch scalar.value {
      case 38: result += "&amp;"
      case 60: result += "&lt;"
      case 62: result += "&gt;"
      case 13: result += "&#13;"
      case 0...8, 11...12, 14...31, 0xfffe...0xffff:
        result += String(format: "_x%04X_", scalar.value)
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  static func decodeCellEscapes(_ raw: String) -> String {
    guard raw.contains("_") else { return raw }
    let input = Array(raw.utf16)
    var output: [UInt16] = []
    output.reserveCapacity(input.count)
    var offset = 0
    while offset < input.count {
      if offset + 6 < input.count, input[offset] == 95, input[offset + 1] == 120, input[offset + 6] == 95,
         input[(offset + 2)..<(offset + 6)].allSatisfy({ (48...57).contains($0) ||
           (65...70).contains($0) || (97...102).contains($0) }),
         let value = UInt16(String(decoding: input[(offset + 2)..<(offset + 6)], as: UTF16.self), radix: 16) {
        output.append(value)
        offset += 7
      } else {
        output.append(input[offset])
        offset += 1
      }
    }
    return String(decoding: output, as: UTF16.self)
  }

  private static let types = """
  <?xml version="1.0" encoding="UTF-8"?>
  <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  </Types>
  """

  private static let rootRelationships = """
  <?xml version="1.0" encoding="UTF-8"?>
  <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  </Relationships>
  """

  private static let workbook = """
  <?xml version="1.0" encoding="UTF-8"?>
  <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <sheets><sheet name="Measurements" sheetId="1" r:id="rId1"/></sheets>
  </workbook>
  """

  private static let workbookRelationships = """
  <?xml version="1.0" encoding="UTF-8"?>
  <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  </Relationships>
  """
}
