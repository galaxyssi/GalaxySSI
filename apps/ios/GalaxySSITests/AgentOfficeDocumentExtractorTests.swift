import XCTest
@testable import GalaxySSI

final class AgentOfficeDocumentExtractorTests: XCTestCase {
  func testXlsxExtractsSharedInlineFormulaAndNumericCells() throws {
    let archive = deflatedOfficeZip(
      (
        "xl/sharedStrings.xml",
        """
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <si><t>Name</t></si><si><t>GalaxySSI</t></si>
        </sst>
        """
      ),
      (
        "xl/worksheets/sheet1.xml",
        """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
          <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="inlineStr"><is><t>Status</t></is></c></row>
          <row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2"><v>42</v></c><c r="C2"><f>SUM(B2:B2)</f></c></row>
        </sheetData></worksheet>
        """
      )
    )

    let text = try AgentOfficeDocumentExtractor.extractXlsx(archive)

    XCTAssertTrue(text.contains("A1=Name"))
    XCTAssertTrue(text.contains("B1=Status"))
    XCTAssertTrue(text.contains("A2=GalaxySSI"))
    XCTAssertTrue(text.contains("B2=42"))
    XCTAssertTrue(text.contains("C2==SUM(B2:B2)"))
  }

  func testPptxExtractsTextPerSlideInNaturalOrder() throws {
    let archive = deflatedOfficeZip(
      ("ppt/slides/slide10.xml", slide("Last slide")),
      ("ppt/slides/slide2.xml", slide("Second slide"))
    )

    let text = try AgentOfficeDocumentExtractor.extractPptx(archive)

    let secondSlide = try XCTUnwrap(text.range(of: "Second slide")?.lowerBound)
    let lastSlide = try XCTUnwrap(text.range(of: "Last slide")?.lowerBound)
    XCTAssertLessThan(secondSlide, lastSlide)
    XCTAssertTrue(text.contains("[Slide 1]"))
    XCTAssertTrue(text.contains("[Slide 2]"))
  }

  func testOfficeArchiveRejectsUnsafeEntries() {
    let archive = deflatedOfficeZip(
      ("../xl/worksheets/sheet1.xml", "<worksheet />")
    )

    XCTAssertThrowsError(try AgentOfficeDocumentExtractor.extractXlsx(archive))
  }

  func testOfficeExtractorRejectsMissingReadableParts() {
    XCTAssertThrowsError(try AgentOfficeDocumentExtractor.extractXlsx(deflatedOfficeZip(("xl/workbook.xml", "<workbook />"))))
    XCTAssertThrowsError(try AgentOfficeDocumentExtractor.extractPptx(deflatedOfficeZip(("ppt/presentation.xml", "<p:presentation />"))))
  }

  private func slide(_ value: String) -> String {
    """
    <p:sld xmlns:p="urn:p" xmlns:a="urn:a"><p:cSld><a:p><a:r><a:t>\(value)</a:t></a:r></a:p></p:cSld></p:sld>
    """
  }

  private func deflatedOfficeZip(_ files: (String, String)...) -> Data {
    var output = Data()
    var centralRecords: [(name: String, body: Data, compressed: Data, localOffset: Int)] = []
    for file in files {
      let nameBytes = Data(file.0.utf8)
      let body = Data(file.1.utf8)
      let compressed = rawDeflateStoredBlocks(body)
      let localOffset = output.count
      appendUInt32LE(0x04034b50, to: &output)
      appendUInt16LE(20, to: &output)
      appendUInt16LE(0x0800, to: &output)
      appendUInt16LE(8, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt32LE(0, to: &output)
      appendUInt32LE(UInt32(compressed.count), to: &output)
      appendUInt32LE(UInt32(body.count), to: &output)
      appendUInt16LE(UInt16(nameBytes.count), to: &output)
      appendUInt16LE(0, to: &output)
      output.append(nameBytes)
      output.append(compressed)
      centralRecords.append((file.0, body, compressed, localOffset))
    }

    let centralStart = output.count
    for record in centralRecords {
      let nameBytes = Data(record.name.utf8)
      appendUInt32LE(0x02014b50, to: &output)
      appendUInt16LE(20, to: &output)
      appendUInt16LE(20, to: &output)
      appendUInt16LE(0x0800, to: &output)
      appendUInt16LE(8, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt32LE(0, to: &output)
      appendUInt32LE(UInt32(record.compressed.count), to: &output)
      appendUInt32LE(UInt32(record.body.count), to: &output)
      appendUInt16LE(UInt16(nameBytes.count), to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt16LE(0, to: &output)
      appendUInt32LE(0, to: &output)
      appendUInt32LE(UInt32(record.localOffset), to: &output)
      output.append(nameBytes)
    }

    appendUInt32LE(0x06054b50, to: &output)
    appendUInt16LE(0, to: &output)
    appendUInt16LE(0, to: &output)
    appendUInt16LE(UInt16(centralRecords.count), to: &output)
    appendUInt16LE(UInt16(centralRecords.count), to: &output)
    appendUInt32LE(UInt32(output.count - centralStart), to: &output)
    appendUInt32LE(UInt32(centralStart), to: &output)
    appendUInt16LE(0, to: &output)
    return output
  }

  private func rawDeflateStoredBlocks(_ data: Data) -> Data {
    var output = Data()
    var offset = 0
    repeat {
      let count = min(data.count - offset, 0xffff)
      output.append(offset + count == data.count ? 0x01 : 0x00)
      appendUInt16LE(UInt16(count), to: &output)
      appendUInt16LE(~UInt16(count), to: &output)
      output.append(data.subdata(in: offset..<(offset + count)))
      offset += count
    } while offset < data.count
    return output
  }

  private func appendUInt16LE(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0x00ff))
    data.append(UInt8((value >> 8) & 0x00ff))
  }

  private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0x000000ff))
    data.append(UInt8((value >> 8) & 0x000000ff))
    data.append(UInt8((value >> 16) & 0x000000ff))
    data.append(UInt8((value >> 24) & 0x000000ff))
  }
}
