import Foundation

struct GalaxySSIHealthXLSX {
  struct Sheet: Identifiable {
    let id: String
    let name: String
    let path: String
  }

  struct Selection {
    let sheet: String
    let header: Int
  }

  struct SheetRow {
    let number: Int
    let cells: [Int: String]
    let formulas: Set<Int>
    let isoDates: Set<Int>
    let formulaText: [Int: String]
  }

  let sheets: [Sheet]
  let date1904: Bool
  private let parts: [String: Data]
  private let strings: [String]

  init(_ data: Data) throws {
    guard data.count <= GalaxySSIHealthTableImport.maximumBytes else { throw GalaxySSIHealthTableImport.Failure.limit }
    parts = try AgentOfficeDocumentExtractor.readXlsxParts(data)
    guard let workbook = parts["xl/workbook.xml"], let relationships = parts["xl/_rels/workbook.xml.rels"]
    else { throw GalaxySSIHealthTableImport.Failure.malformed }
    let manifest = WorkbookXML()
    try AgentOfficeDocumentExtractor.parseXML(workbook, delegate: manifest)
    let rels = RelationshipXML()
    try AgentOfficeDocumentExtractor.parseXML(relationships, delegate: rels)
    let available = parts
    sheets = manifest.sheets.compactMap { sheet in
      guard let path = rels.paths[sheet.id], available[path] != nil else { return nil }
      return Sheet(id: sheet.id, name: sheet.name, path: path)
    }
    guard !sheets.isEmpty, sheets.count <= 64, Set(sheets.map(\.id)).count == sheets.count
    else { throw GalaxySSIHealthTableImport.Failure.malformed }
    date1904 = manifest.date1904
    if let raw = parts["xl/sharedStrings.xml"] {
      let parser = StringsXML()
      try AgentOfficeDocumentExtractor.parseXML(raw, delegate: parser)
      strings = parser.values
    } else { strings = [] }
  }

  func rows(_ id: String) throws -> [SheetRow] {
    guard let sheet = sheets.first(where: { $0.id == id }), let part = parts[sheet.path]
    else { throw GalaxySSIHealthTableImport.Failure.mapping }
    let parser = SheetXML(strings: strings)
    try AgentOfficeDocumentExtractor.parseXML(part, delegate: parser)
    guard !parser.rows.isEmpty else { throw GalaxySSIHealthTableImport.Failure.malformed }
    return parser.rows
  }

  func table(_ selection: Selection) throws -> GalaxySSIHealthTableImport.Table {
    let rows = try rows(selection.sheet)
    guard let position = rows.firstIndex(where: { $0.number == selection.header }), position + 1 < rows.count,
          let sheet = sheets.first(where: { $0.id == selection.sheet }) else { throw GalaxySSIHealthTableImport.Failure.mapping }
    let header = rows[position]
    let body = rows.dropFirst(position + 1)
    let used = rows[position...].flatMap { Array($0.cells.keys) + Array($0.formulas) }
    guard let last = used.max(), last >= 1, last < 64 else { throw GalaxySSIHealthTableImport.Failure.limit }
    let columns = 0...last
    return GalaxySSIHealthTableImport.Table(
      headers: columns.map { header.formulas.contains($0) ? "" : header.cells[$0, default: ""] },
      rows: body.map { row in columns.map { row.cells[$0, default: ""] } },
      sheet: sheet.name, sheetPath: sheet.path, rowNumbers: body.map(\.number),
      formulas: body.map(\.formulas), date1904: date1904, isoDates: body.map(\.isoDates))
  }

  static func date(serial: Decimal, date1904: Bool, zone: TimeZone) -> Date? {
    let number = NSDecimalNumber(decimal: serial).doubleValue
    guard number.isFinite, number >= 0, number < 2_958_466 else { return nil }
    let day = Int(number.rounded(.down))
    if !date1904 && day == 60 { return nil }
    let offset = date1904 || day < 60 ? day : day - 1
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let origin = date1904 ? DateComponents(year: 1904, month: 1, day: 1) : DateComponents(year: 1899, month: 12, day: 31)
    guard let base = calendar.date(from: origin), let dayStart = calendar.date(byAdding: .day, value: offset, to: base)
    else { return nil }
    let seconds = min(86_399, Int(((number - Double(day)) * 86_400).rounded()))
    var wall = calendar.dateComponents([.year, .month, .day], from: dayStart)
    wall.hour = seconds / 3600
    wall.minute = (seconds / 60) % 60
    wall.second = seconds % 60
    return uniqueWallTime(wall, zone: zone)
  }

  static func isoDate(_ raw: String, zone: TimeZone, dateOnlyMinute: Int?) -> Date? {
    guard raw.utf8.count <= 40 else { return nil }
    let fields = raw.split(separator: "T", omittingEmptySubsequences: false)
    guard fields.count == 1 || fields.count == 2 else { return nil }
    let day = fields[0].split(separator: "-", omittingEmptySubsequences: false)
    guard day.count == 3, let year = digits(day[0], width: 4), year > 0,
          let month = digits(day[1], width: 2), let date = digits(day[2], width: 2) else { return nil }
    var parts = DateComponents(year: year, month: month, day: date)
    if fields.count == 1 {
      guard let minute = dateOnlyMinute, (0..<1440).contains(minute) else { return nil }
      parts.hour = minute / 60
      parts.minute = minute % 60
      parts.second = 0
      return uniqueWallTime(parts, zone: zone)
    }
    var clock = fields[1]
    var resolvedZone = zone
    if clock.last == "Z" {
      clock = clock.dropLast()
      resolvedZone = TimeZone(secondsFromGMT: 0) ?? zone
    } else if let offset = clock.firstIndex(where: { $0 == "+" || $0 == "-" }) {
      let suffix = clock[clock.index(after: offset)...].split(separator: ":", omittingEmptySubsequences: false)
      guard suffix.count == 2, let hours = digits(suffix[0], width: 2),
            let minutes = digits(suffix[1], width: 2), minutes < 60,
            hours < 18 || (hours == 18 && minutes == 0),
            let fixed = TimeZone(secondsFromGMT: (clock[offset] == "-" ? -1 : 1) * (hours * 3600 + minutes * 60))
      else { return nil }
      resolvedZone = fixed
      clock = clock[..<offset]
    }
    let time = clock.split(separator: ":", omittingEmptySubsequences: false)
    guard time.count == 2 || time.count == 3, let hour = digits(time[0], width: 2), hour < 24,
          let minute = digits(time[1], width: 2), minute < 60 else { return nil }
    var seconds = 0
    var fraction = 0.0
    if time.count == 3 {
      let second = time[2].split(separator: ".", omittingEmptySubsequences: false)
      guard second.count == 1 || second.count == 2, let integer = digits(second[0], width: 2), integer < 60
      else { return nil }
      seconds = integer
      if second.count == 2 {
        let count = second[1].utf8.count
        guard (1...9).contains(count), let value = digits(second[1], width: count) else { return nil }
        fraction = Double(value) / pow(10, Double(count))
      }
    }
    parts.hour = hour
    parts.minute = minute
    parts.second = seconds
    return uniqueWallTime(parts, zone: resolvedZone)?.addingTimeInterval(fraction)
  }

  private static func digits(_ value: Substring, width: Int) -> Int? {
    guard value.utf8.count == width, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
    return Int(value)
  }

  private static func uniqueWallTime(_ parts: DateComponents, zone: TimeZone) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    guard parts.isValidDate(in: calendar), let tentative = calendar.date(from: parts) else { return nil }
    let beforeDay = calendar.startOfDay(for: tentative).addingTimeInterval(-1)
    let first = calendar.nextDate(after: beforeDay, matching: parts, matchingPolicy: .strict, repeatedTimePolicy: .first)
    let last = calendar.nextDate(after: beforeDay, matching: parts, matchingPolicy: .strict, repeatedTimePolicy: .last)
    return first == last ? first : nil
  }
}

private func tag(_ name: String) -> Substring { name.split(separator: ":").last ?? name[...] }

private final class WorkbookXML: NSObject, XMLParserDelegate {
  var sheets: [(id: String, name: String)] = []
  var date1904 = false
  func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
              qualifiedName: String?, attributes attrs: [String: String]) {
    if tag(name) == "workbookPr" { date1904 = ["true", "1"].contains(attrs["date1904"] ?? "") }
    if tag(name) == "sheet", let id = attrs.first(where: { $0.key.hasSuffix(":id") })?.value, let name = attrs["name"] {
      guard sheets.count < 64 else { parser.abortParsing(); return }
      sheets.append((id, String(name.prefix(120))))
    }
  }
}

private final class RelationshipXML: NSObject, XMLParserDelegate {
  var paths: [String: String] = [:]
  func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
              qualifiedName: String?, attributes attrs: [String: String]) {
    guard tag(name) == "Relationship", attrs["Type"]?.hasSuffix("/worksheet") == true,
          attrs["TargetMode"] != "External", let id = attrs["Id"], let target = attrs["Target"] else { return }
    let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
    let prefix = "xl/worksheets/"
    guard path.hasPrefix(prefix), path.hasSuffix(".xml"), !path.dropFirst(prefix.count).contains("/"),
          paths[id] == nil else { parser.abortParsing(); return }
    paths[id] = path
  }
}

private final class StringsXML: NSObject, XMLParserDelegate {
  var values: [String] = []
  private var current = ""
  private var collecting = false
  func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
              qualifiedName: String?, attributes: [String: String]) {
    if tag(name) == "si" { current = "" }
    if tag(name) == "t" { collecting = true }
  }
  func parser(_ parser: XMLParser, foundCharacters text: String) {
    guard collecting else { return }
    current += text
    if current.utf8.count > 8_192 { parser.abortParsing() }
  }
  func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    if tag(name) == "t" { collecting = false }
    if tag(name) == "si" {
      guard values.count < 32_000 else { parser.abortParsing(); return }
      values.append(current)
    }
  }
}

private final class SheetXML: NSObject, XMLParserDelegate {
  let strings: [String]
  var rows: [GalaxySSIHealthXLSX.SheetRow] = []
  private var row = 0
  private var column = -1
  private var cells: [Int: String] = [:]
  private var formulas = Set<Int>()
  private var isoDates = Set<Int>()
  private var formulaText: [Int: String] = [:]
  private var expression = ""
  private var collectingFormula = false
  private var text = ""
  private var type = ""
  private var collecting = false
  private var formula = false

  init(strings: [String]) { self.strings = strings }

  func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
              qualifiedName: String?, attributes attrs: [String: String]) {
    switch tag(name) {
    case "row":
      let next = attrs["r"].flatMap(Int.init) ?? row + 1
      guard next > row, next <= 1_048_576, rows.count < 501 else { parser.abortParsing(); return }
      row = next
      column = -1
      cells = [:]
      formulas = []
      isoDates = []
      formulaText = [:]
    case "c":
      let next = attrs["r"].flatMap { Self.column($0, row: row) } ?? (attrs["r"] == nil ? column + 1 : -1)
      guard next > column, next < 64 else { parser.abortParsing(); return }
      column = next
      type = attrs["t", default: "n"]
      text = ""
      formula = false
      expression = ""
    case "v": collecting = true
    case "t" where type == "inlineStr": collecting = true
    case "f": formula = true; collectingFormula = true
    default: break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters value: String) {
    if collectingFormula {
      expression += value
      if expression.utf8.count > 8_192 { parser.abortParsing() }
      return
    }
    guard collecting else { return }
    text += value
    if text.utf8.count > 8_192 { parser.abortParsing() }
  }

  func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    switch tag(name) {
    case "f": collectingFormula = false
    case "v", "t": collecting = false
    case "c":
      if type == "s" {
        guard let index = Int(text), strings.indices.contains(index) else { parser.abortParsing(); return }
        cells[column] = GalaxySSIHealthXLSXExport.decodeCellEscapes(strings[index])
      } else if type == "inlineStr" || type == "str" {
        cells[column] = GalaxySSIHealthXLSXExport.decodeCellEscapes(text)
      } else if type != "e" { cells[column] = text }
      if formula {
        formulas.insert(column)
        formulaText[column] = expression
      }
      if type == "d" { isoDates.insert(column) }
    case "row":
      if !cells.isEmpty || !formulas.isEmpty {
        rows.append(.init(number: row, cells: cells, formulas: formulas, isoDates: isoDates,
                          formulaText: formulaText))
      }
    default: break
    }
  }

  private static func column(_ reference: String, row: Int) -> Int? {
    let letters = reference.utf8.prefix { (65...90).contains($0) }
    guard (1...3).contains(letters.count), Int(reference.dropFirst(letters.count)) == row else { return nil }
    return letters.reduce(0) { $0 * 26 + Int($1 - 64) } - 1
  }
}
