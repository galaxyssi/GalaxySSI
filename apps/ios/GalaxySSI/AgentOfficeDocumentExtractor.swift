import Foundation

enum AgentOfficeDocumentExtractionError: LocalizedError, Equatable {
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let detail):
      return detail
    }
  }
}

enum AgentOfficeDocumentExtractor {
  static func extractXlsx(_ bytes: Data) throws -> String {
    let entries = try readEntries(bytes) { name in
      name == "xl/sharedStrings.xml" ||
        (name.hasPrefix("xl/worksheets/sheet") && name.hasSuffix(".xml"))
    }
    let sharedStrings: [String]
    if let xml = entries["xl/sharedStrings.xml"] {
      let parser = SharedStringsXMLParser()
      try parseXML(xml, delegate: parser)
      sharedStrings = parser.values
    } else {
      sharedStrings = []
    }
    let sheets = entries
      .filter { $0.key.hasPrefix("xl/worksheets/sheet") && $0.key.hasSuffix(".xml") }
      .sorted { first, second in naturalIndex(first.key, marker: "sheet") < naturalIndex(second.key, marker: "sheet") }
    guard !sheets.isEmpty else {
      throw AgentOfficeDocumentExtractionError.invalid("XLSX contains no readable worksheets")
    }

    var sections: [String] = []
    for (index, sheet) in sheets.enumerated() {
      let parser = WorksheetXMLParser(sharedStrings: sharedStrings)
      try parseXML(sheet.value, delegate: parser)
      let body = (["[Sheet \(index + 1)]"] + parser.rowLines).joined(separator: "\n")
      sections.append(body)
      try requireOutputLimit(sections.joined(separator: "\n\n"), message: "XLSX text exceeds the extraction limit")
    }
    return sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func extractPptx(_ bytes: Data) throws -> String {
    let slides = try readEntries(bytes) { name in
      name.hasPrefix("ppt/slides/slide") && name.hasSuffix(".xml")
    }.sorted { first, second in naturalIndex(first.key, marker: "slide") < naturalIndex(second.key, marker: "slide") }
    guard !slides.isEmpty else {
      throw AgentOfficeDocumentExtractionError.invalid("PPTX contains no readable slides")
    }

    var sections: [String] = []
    for (index, slide) in slides.enumerated() {
      let parser = SlideXMLParser()
      try parseXML(slide.value, delegate: parser)
      var lines = ["[Slide \(index + 1)]"]
      if parser.paragraphs.isEmpty {
        let fallback = normalizeOfficeText(parser.allText)
        if !fallback.isEmpty {
          lines.append(fallback)
        }
      } else {
        lines.append(contentsOf: parser.paragraphs)
      }
      sections.append(lines.joined(separator: "\n"))
      try requireOutputLimit(sections.joined(separator: "\n\n"), message: "PPTX text exceeds the extraction limit")
    }
    return sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func extractDocx(_ bytes: Data) throws -> String {
    let entries = try readEntries(bytes) { name in
      name == "word/document.xml" ||
        (name.hasPrefix("word/header") && name.hasSuffix(".xml")) ||
        (name.hasPrefix("word/footer") && name.hasSuffix(".xml")) ||
        name == "word/footnotes.xml" ||
        name == "word/endnotes.xml"
    }
    let ordered = entries.sorted { first, second in
      if first.key == "word/document.xml" { return true }
      if second.key == "word/document.xml" { return false }
      return first.key < second.key
    }
    guard !ordered.isEmpty else {
      throw AgentOfficeDocumentExtractionError.invalid("DOCX contains no readable document text")
    }

    var sections: [String] = []
    for entry in ordered {
      let parser = WordDocumentXMLParser()
      try parseXML(entry.value, delegate: parser)
      let body = parser.paragraphs.isEmpty
        ? normalizeOfficeText(parser.allText)
        : parser.paragraphs.joined(separator: "\n")
      if !body.isEmpty {
        sections.append(body)
        try requireOutputLimit(sections.joined(separator: "\n\n"), message: "DOCX text exceeds the extraction limit")
      }
    }
    let output = sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !output.isEmpty else {
      throw AgentOfficeDocumentExtractionError.invalid("DOCX contains no readable document text")
    }
    return output
  }

  private struct ZipEntry {
    var path: String
    var directory: Bool
    var method: UInt16
    var compressedBytes: Int64
    var uncompressedBytes: Int64
    var dataOffset: Int
    var dataLength: Int
  }

  private static func readEntries(_ data: Data, include: (String) -> Bool) throws -> [String: Data] {
    let entries = try inspectZipData(data)
    var selected: [String: Data] = [:]
    var selectedBytes: Int64 = 0
    var expandedBytes: Int64 = 0
    for entry in entries {
      expandedBytes = try checkedAdd(
        expandedBytes,
        entry.uncompressedBytes,
        message: "Office archive expands beyond the safety limit"
      )
      guard expandedBytes <= maxExpandedArchiveBytes else {
        throw AgentOfficeDocumentExtractionError.invalid("Office archive expands beyond the safety limit")
      }
      guard !entry.directory, include(entry.path) else {
        continue
      }
      selectedBytes = try checkedAdd(
        selectedBytes,
        entry.uncompressedBytes,
        message: "Office XML exceeds the extraction limit"
      )
      guard selectedBytes <= maxSelectedXMLBytes else {
        throw AgentOfficeDocumentExtractionError.invalid("Office XML exceeds the extraction limit")
      }
      guard selected[entry.path] == nil else {
        throw AgentOfficeDocumentExtractionError.invalid("Office archive contains a duplicate entry")
      }
      selected[entry.path] = try entryData(entry, from: data)
    }
    return selected
  }

  private static func inspectZipData(_ data: Data) throws -> [ZipEntry] {
    let eocd = try endOfCentralDirectoryOffset(data)
    let diskNumber = try data.officeUInt16LE(at: eocd + 4)
    let centralDisk = try data.officeUInt16LE(at: eocd + 6)
    let diskEntries = try data.officeUInt16LE(at: eocd + 8)
    let entryCount = try data.officeUInt16LE(at: eocd + 10)
    let centralSize = Int(try data.officeUInt32LE(at: eocd + 12))
    let centralOffset = Int(try data.officeUInt32LE(at: eocd + 16))
    guard diskNumber == 0, centralDisk == 0, diskEntries == entryCount else {
      throw AgentOfficeDocumentExtractionError.invalid("Multi-disk Office archives are not supported")
    }
    guard entryCount <= maxZipEntries else {
      throw AgentOfficeDocumentExtractionError.invalid("Office archive contains too many entries")
    }
    guard rangeFits(start: centralOffset, length: centralSize, in: data) else {
      throw AgentOfficeDocumentExtractionError.invalid("Office archive central directory is invalid")
    }

    var entries: [ZipEntry] = []
    var offset = centralOffset
    for _ in 0..<Int(entryCount) {
      guard rangeFits(start: offset, length: 46, in: data),
            try data.officeUInt32LE(at: offset) == 0x02014b50 else {
        throw AgentOfficeDocumentExtractionError.invalid("Office archive central directory entry is invalid")
      }
      let flags = try data.officeUInt16LE(at: offset + 8)
      let method = try data.officeUInt16LE(at: offset + 10)
      let compressedBytes = Int64(try data.officeUInt32LE(at: offset + 20))
      let uncompressedBytes = Int64(try data.officeUInt32LE(at: offset + 24))
      let nameLength = Int(try data.officeUInt16LE(at: offset + 28))
      let extraLength = Int(try data.officeUInt16LE(at: offset + 30))
      let commentLength = Int(try data.officeUInt16LE(at: offset + 32))
      let localOffset = Int(try data.officeUInt32LE(at: offset + 42))
      let nameStart = offset + 46
      guard rangeFits(start: nameStart, length: nameLength, in: data),
            let rawName = String(data: data.subdata(in: nameStart..<(nameStart + nameLength)), encoding: .utf8) else {
        throw AgentOfficeDocumentExtractionError.invalid("Office archive entry name is invalid")
      }
      let path = try safeArchivePath(rawName)
      guard flags & 0x0001 == 0 else {
        throw AgentOfficeDocumentExtractionError.invalid("Encrypted Office archive entries are not supported")
      }
      guard method == 0 || method == 8 else {
        throw AgentOfficeDocumentExtractionError.invalid("Office ZIP compression method is not supported on iOS yet")
      }
      let nextOffset = nameStart + nameLength + extraLength + commentLength
      guard nextOffset <= centralOffset + centralSize else {
        throw AgentOfficeDocumentExtractionError.invalid("Office archive central directory entry is out of bounds")
      }
      let local = try localEntryDataOffset(localOffset, compressedBytes: compressedBytes, in: data)
      entries.append(ZipEntry(
        path: path,
        directory: path.hasSuffix("/"),
        method: method,
        compressedBytes: compressedBytes,
        uncompressedBytes: uncompressedBytes,
        dataOffset: local.offset,
        dataLength: local.length
      ))
      offset = nextOffset
    }
    return entries
  }

  private static func entryData(_ entry: ZipEntry, from data: Data) throws -> Data {
    guard entry.uncompressedBytes <= maxSelectedXMLBytes,
          rangeFits(start: entry.dataOffset, length: entry.dataLength, in: data) else {
      throw AgentOfficeDocumentExtractionError.invalid("Office XML exceeds the extraction limit")
    }
    let compressed = data.subdata(in: entry.dataOffset..<(entry.dataOffset + entry.dataLength))
    let content: Data
    switch entry.method {
    case 0:
      content = compressed
    case 8:
      content = try AgentMcpPackageInstaller.inflateDeflate(
        compressed,
        expectedBytes: entry.uncompressedBytes,
        maxBytes: Int(maxSelectedXMLBytes)
      )
    default:
      throw AgentOfficeDocumentExtractionError.invalid("Office ZIP compression method is not supported on iOS yet")
    }
    guard Int64(content.count) == entry.uncompressedBytes else {
      throw AgentOfficeDocumentExtractionError.invalid("Office archive entry size changed during extraction")
    }
    return content
  }

  private static func localEntryDataOffset(
    _ localOffset: Int,
    compressedBytes: Int64,
    in data: Data
  ) throws -> (offset: Int, length: Int) {
    guard rangeFits(start: localOffset, length: 30, in: data),
          try data.officeUInt32LE(at: localOffset) == 0x04034b50 else {
      throw AgentOfficeDocumentExtractionError.invalid("Office archive local entry is invalid")
    }
    let nameLength = Int(try data.officeUInt16LE(at: localOffset + 26))
    let extraLength = Int(try data.officeUInt16LE(at: localOffset + 28))
    let dataOffset = localOffset + 30 + nameLength + extraLength
    let dataLength = Int(compressedBytes)
    guard compressedBytes >= 0, rangeFits(start: dataOffset, length: dataLength, in: data) else {
      throw AgentOfficeDocumentExtractionError.invalid("Office archive local entry is out of bounds")
    }
    return (dataOffset, dataLength)
  }

  private static func endOfCentralDirectoryOffset(_ data: Data) throws -> Int {
    guard data.count >= 22 else {
      throw AgentOfficeDocumentExtractionError.invalid("Office archive central directory was not found")
    }
    let lowerBound = max(0, data.count - 65_557)
    var offset = data.count - 22
    while offset >= lowerBound {
      if (try? data.officeUInt32LE(at: offset)) == 0x06054b50 {
        return offset
      }
      offset -= 1
    }
    throw AgentOfficeDocumentExtractionError.invalid("Office archive central directory was not found")
  }

  private static func safeArchivePath(_ raw: String) throws -> String {
    let normalized = raw.replacingOccurrences(of: "\\", with: "/")
    let parts = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !normalized.hasPrefix("/"), !parts.contains("..") else {
      throw AgentOfficeDocumentExtractionError.invalid("Office archive contains an unsafe entry")
    }
    return normalized
  }

  private static func parseXML(_ data: Data, delegate: XMLParserDelegate) throws {
    guard let xml = String(data: data, encoding: .utf8) else {
      throw AgentOfficeDocumentExtractionError.invalid("Office XML is not valid UTF-8")
    }
    guard xml.range(of: "<!DOCTYPE", options: [.caseInsensitive]) == nil else {
      throw AgentOfficeDocumentExtractionError.invalid("Office XML document types are not allowed")
    }
    let parser = XMLParser(data: Data(xml.utf8))
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse() else {
      throw AgentOfficeDocumentExtractionError.invalid(parser.parserError?.localizedDescription ?? "Office XML is invalid")
    }
  }

  private static func naturalIndex(_ name: String, marker: String) -> Int {
    let pattern = "\(marker)(\\d+)"
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return Int.max
    }
    let range = NSRange(name.startIndex..<name.endIndex, in: name)
    guard let match = expression.firstMatch(in: name, range: range),
          let numberRange = Range(match.range(at: 1), in: name),
          let value = Int(name[numberRange]) else {
      return Int.max
    }
    return value
  }

  private static func checkedAdd(_ first: Int64, _ second: Int64, message: String) throws -> Int64 {
    guard second >= 0, first <= Int64.max - second else {
      throw AgentOfficeDocumentExtractionError.invalid(message)
    }
    return first + second
  }

  private static func requireOutputLimit(_ value: String, message: String) throws {
    guard value.count <= maxOutputCharacters else {
      throw AgentOfficeDocumentExtractionError.invalid(message)
    }
  }

  private static func rangeFits(start: Int, length: Int, in data: Data) -> Bool {
    start >= 0 && length >= 0 && start <= data.count && length <= data.count - start
  }

  private static let maxZipEntries = UInt16(2_000)
  private static let maxSelectedXMLBytes: Int64 = 24 * 1_024 * 1_024
  private static let maxExpandedArchiveBytes: Int64 = 96 * 1_024 * 1_024
  private static let maxOutputCharacters = 500_000
}

private final class SharedStringsXMLParser: NSObject, XMLParserDelegate {
  private(set) var values: [String] = []
  private var current = ""
  private var inSharedItem = false
  private var capturingText = false

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch localName(elementName, qName) {
    case "si":
      inSharedItem = true
      current = ""
    case "t" where inSharedItem:
      capturingText = true
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if capturingText {
      current += string
    }
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    switch localName(elementName, qName) {
    case "t":
      capturingText = false
    case "si":
      values.append(normalizeOfficeText(current))
      inSharedItem = false
    default:
      break
    }
  }
}

private final class WorksheetXMLParser: NSObject, XMLParserDelegate {
  private struct Cell {
    var reference: String
    var type: String
    var rawValue = ""
    var inlineText = ""
    var formula = ""
  }

  private enum CaptureTarget {
    case value
    case formula
    case inlineText
  }

  private let sharedStrings: [String]
  private(set) var rowLines: [String] = []
  private var rowValues: [String] = []
  private var currentCell: Cell?
  private var captureTarget: CaptureTarget?

  init(sharedStrings: [String]) {
    self.sharedStrings = sharedStrings
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch localName(elementName, qName) {
    case "row":
      rowValues = []
    case "c":
      currentCell = Cell(
        reference: attributeDict["r"]?.isEmpty == false ? attributeDict["r"] ?? "cell" : "cell",
        type: attributeDict["t"] ?? ""
      )
    case "v" where currentCell != nil:
      captureTarget = .value
    case "f" where currentCell != nil:
      captureTarget = .formula
    case "t" where currentCell != nil:
      captureTarget = .inlineText
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard let captureTarget else {
      return
    }
    switch captureTarget {
    case .value:
      currentCell?.rawValue += string
    case .formula:
      currentCell?.formula += string
    case .inlineText:
      currentCell?.inlineText += string
    }
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    switch localName(elementName, qName) {
    case "v", "f", "t":
      captureTarget = nil
    case "c":
      appendCurrentCell()
      currentCell = nil
    case "row":
      if !rowValues.isEmpty {
        rowLines.append(rowValues.joined(separator: " | "))
      }
      rowValues = []
    default:
      break
    }
  }

  private func appendCurrentCell() {
    guard let cell = currentCell else {
      return
    }
    let raw = normalizeOfficeText(cell.rawValue)
    let inline = normalizeOfficeText(cell.inlineText)
    let formula = normalizeOfficeText(cell.formula)
    let value: String
    if cell.type == "s" {
      value = Int(raw).flatMap { sharedStrings.indices.contains($0) ? sharedStrings[$0] : nil } ?? ""
    } else if cell.type == "inlineStr" || cell.type == "str" {
      value = inline.isEmpty ? raw : inline
    } else if !raw.isEmpty {
      value = raw
    } else if !formula.isEmpty {
      value = "=\(formula)"
    } else {
      value = inline
    }
    let normalized = normalizeOfficeText(value)
    if !normalized.isEmpty {
      rowValues.append("\(cell.reference)=\(normalized)")
    }
  }
}

private final class SlideXMLParser: NSObject, XMLParserDelegate {
  private(set) var paragraphs: [String] = []
  private(set) var allText = ""
  private var paragraphDepth = 0
  private var currentParagraph = ""
  private var capturingText = false

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch localName(elementName, qName) {
    case "p":
      if paragraphDepth == 0 {
        currentParagraph = ""
      }
      paragraphDepth += 1
    case "t":
      capturingText = true
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if capturingText {
      allText += string
      if paragraphDepth > 0 {
        currentParagraph += string
      }
    }
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    switch localName(elementName, qName) {
    case "t":
      capturingText = false
    case "p" where paragraphDepth > 0:
      paragraphDepth -= 1
      if paragraphDepth == 0 {
        let paragraph = normalizeOfficeText(currentParagraph)
        if !paragraph.isEmpty {
          paragraphs.append(paragraph)
        }
        currentParagraph = ""
      }
    default:
      break
    }
  }
}

private final class WordDocumentXMLParser: NSObject, XMLParserDelegate {
  private(set) var paragraphs: [String] = []
  private(set) var allText = ""
  private var paragraphDepth = 0
  private var currentParagraph = ""
  private var capturingText = false

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch localName(elementName, qName) {
    case "p":
      if paragraphDepth == 0 {
        currentParagraph = ""
      }
      paragraphDepth += 1
    case "t":
      capturingText = true
    case "tab" where paragraphDepth > 0:
      currentParagraph += "\t"
      allText += "\t"
    case "br" where paragraphDepth > 0:
      currentParagraph += "\n"
      allText += "\n"
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if capturingText {
      allText += string
      if paragraphDepth > 0 {
        currentParagraph += string
      }
    }
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    switch localName(elementName, qName) {
    case "t":
      capturingText = false
    case "p" where paragraphDepth > 0:
      paragraphDepth -= 1
      if paragraphDepth == 0 {
        let paragraph = normalizeOfficeText(currentParagraph)
        if !paragraph.isEmpty {
          paragraphs.append(paragraph)
        }
        currentParagraph = ""
      }
    default:
      break
    }
  }
}

private func localName(_ elementName: String, _ qualifiedName: String?) -> String {
  let raw = qualifiedName?.isEmpty == false ? qualifiedName! : elementName
  return raw.split(separator: ":").last.map(String.init) ?? raw
}

private func normalizeOfficeText(_ value: String) -> String {
  value
    .replacingOccurrences(of: "\u{0000}", with: " ")
    .replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ", options: .regularExpression)
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

private extension Data {
  func officeUInt16LE(at offset: Int) throws -> UInt16 {
    guard AgentOfficeDocumentExtractor.rangeFitsForOfficeData(start: offset, length: 2, in: self) else {
      throw AgentOfficeDocumentExtractionError.invalid("Office archive is truncated")
    }
    return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
  }

  func officeUInt32LE(at offset: Int) throws -> UInt32 {
    guard AgentOfficeDocumentExtractor.rangeFitsForOfficeData(start: offset, length: 4, in: self) else {
      throw AgentOfficeDocumentExtractionError.invalid("Office archive is truncated")
    }
    return UInt32(self[offset]) |
      (UInt32(self[offset + 1]) << 8) |
      (UInt32(self[offset + 2]) << 16) |
      (UInt32(self[offset + 3]) << 24)
  }
}

private extension AgentOfficeDocumentExtractor {
  static func rangeFitsForOfficeData(start: Int, length: Int, in data: Data) -> Bool {
    start >= 0 && length >= 0 && start <= data.count && length <= data.count - start
  }
}
