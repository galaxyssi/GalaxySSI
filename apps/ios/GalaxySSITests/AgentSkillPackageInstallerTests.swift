import Foundation
import XCTest
@testable import GalaxySSI

final class AgentSkillPackageInstallerTests: XCTestCase {
  func testAgentSkillPackageInstallerVerifiesManifestIntegrityAndInstallsDisabled() throws {
    let runtime = AgentSkillRuntime(availableNativeToolIds: ["phone.battery"])
    let installer = AgentSkillPackageInstaller(runtime)
    let package = AgentSkillPackageExporter.export(manifest)

    let inspected = try installer.inspect(package)
    let installed = try installer.install(package)

    XCTAssertTrue(inspected.integrityVerified)
    XCTAssertEqual(inspected.signer, "GalaxySSI local export")
    XCTAssertTrue(inspected.entries.isSuperset(of: Set(["manifest.json", "integrity.json"])))
    XCTAssertEqual(installed.manifest.source, "third_party")
    XCTAssertFalse(installed.enabled)
  }

  func testAgentSkillPackageInstallerRejectsTraversalExecutableAndTamperedPackages() {
    let installer = AgentSkillPackageInstaller(AgentSkillRuntime(availableNativeToolIds: ["phone.battery"]))
    let raw = AgentSkillManifestCodec.encode(manifest)
    assertPackageError(try installer.inspect(storedPackage(("../manifest.json", raw))), contains: "Unsafe")
    assertPackageError(
      try installer.inspect(storedPackage(("manifest.json", raw), ("run.js", "alert(1)"))),
      contains: "Executable content"
    )
    assertPackageError(
      try installer.inspect(storedPackage(
        ("manifest.json", raw),
        ("integrity.json", #"{"manifest_sha256":"\#(String(repeating: "0", count: 64))"}"#)
      )),
      contains: "integrity check failed"
    )
  }

  func testAgentSkillPackageInstallerRequiresUnsignedLocalApproval() throws {
    let runtime = AgentSkillRuntime(availableNativeToolIds: ["phone.battery"])
    let installer = AgentSkillPackageInstaller(runtime)
    let unsigned = storedPackage(("manifest.json", AgentSkillManifestCodec.encode(manifest)))

    assertPackageError(try installer.install(unsigned), contains: "Unsigned")

    let installed = try installer.install(unsigned, allowUnsignedLocalPackage: true)
    XCTAssertEqual(installed.id, manifest.id)
    XCTAssertFalse(installed.enabled)
  }

  private var manifest: AgentSkillManifest {
    AgentSkillManifest(
      id: "package.test",
      name: "Package test",
      version: "1.0.0",
      summary: "Read battery status",
      instructions: "Read battery status.",
      nativeTools: ["phone.battery"],
      steps: [AgentSkillStep(id: "read", toolId: "phone.battery")],
      source: "third_party"
    )
  }

  private func assertPackageError(
    _ expression: @autoclosure () throws -> Any,
    contains expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
      let message = (error as? AgentSkillPackageError)?.message ?? String(describing: error)
      XCTAssertTrue(message.contains(expected), "Unexpected error: \(message)", file: file, line: line)
    }
  }

  private func storedPackage(_ files: (String, String)...) -> Data {
    var output = Data()
    var centralRecords: [(name: String, body: Data, crc32: UInt32, localOffset: Int)] = []
    for file in files {
      let nameBytes = Data(file.0.utf8)
      let body = Data(file.1.utf8)
      let crc = skillPackageCRC32(body)
      let localOffset = output.count
      appendSkillZipUInt32LE(0x04034b50, to: &output)
      appendSkillZipUInt16LE(20, to: &output)
      appendSkillZipUInt16LE(0x0800, to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      appendSkillZipUInt32LE(crc, to: &output)
      appendSkillZipUInt32LE(UInt32(body.count), to: &output)
      appendSkillZipUInt32LE(UInt32(body.count), to: &output)
      appendSkillZipUInt16LE(UInt16(nameBytes.count), to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      output.append(nameBytes)
      output.append(body)
      centralRecords.append((file.0, body, crc, localOffset))
    }
    let centralStart = output.count
    for record in centralRecords {
      let nameBytes = Data(record.name.utf8)
      appendSkillZipUInt32LE(0x02014b50, to: &output)
      appendSkillZipUInt16LE(20, to: &output)
      appendSkillZipUInt16LE(20, to: &output)
      appendSkillZipUInt16LE(0x0800, to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      appendSkillZipUInt32LE(record.crc32, to: &output)
      appendSkillZipUInt32LE(UInt32(record.body.count), to: &output)
      appendSkillZipUInt32LE(UInt32(record.body.count), to: &output)
      appendSkillZipUInt16LE(UInt16(nameBytes.count), to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      appendSkillZipUInt16LE(0, to: &output)
      appendSkillZipUInt32LE(0, to: &output)
      appendSkillZipUInt32LE(UInt32(record.localOffset), to: &output)
      output.append(nameBytes)
    }
    let centralSize = output.count - centralStart
    appendSkillZipUInt32LE(0x06054b50, to: &output)
    appendSkillZipUInt16LE(0, to: &output)
    appendSkillZipUInt16LE(0, to: &output)
    appendSkillZipUInt16LE(UInt16(centralRecords.count), to: &output)
    appendSkillZipUInt16LE(UInt16(centralRecords.count), to: &output)
    appendSkillZipUInt32LE(UInt32(centralSize), to: &output)
    appendSkillZipUInt32LE(UInt32(centralStart), to: &output)
    appendSkillZipUInt16LE(0, to: &output)
    return output
  }

  private func appendSkillZipUInt16LE(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0x00ff))
    data.append(UInt8((value >> 8) & 0x00ff))
  }

  private func appendSkillZipUInt32LE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0x000000ff))
    data.append(UInt8((value >> 8) & 0x000000ff))
    data.append(UInt8((value >> 16) & 0x000000ff))
    data.append(UInt8((value >> 24) & 0x000000ff))
  }

  private func skillPackageCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xff)
      crc = (crc >> 8) ^ Self.skillPackageCRC32Table[index]
    }
    return crc ^ 0xffffffff
  }

  private static let skillPackageCRC32Table: [UInt32] = {
    (0..<256).map { value -> UInt32 in
      var crc = UInt32(value)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xedb88320
        } else {
          crc >>= 1
        }
      }
      return crc
    }
  }()
}
