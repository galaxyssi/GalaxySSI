import UIKit
import XCTest
@testable import GalaxySSI

final class AgentImagePipelineTests: XCTestCase {
  func testSmallImageKeepsOriginalBytesAndRecordsProbe() throws {
    let data = try XCTUnwrap(testImage().pngData())
    let attachment = GalaxySSIDraftAttachment(
      displayName: "original.png",
      mimeType: "image/png",
      data: data
    )
    let (timing, tracer, root) = makeTiming()
    defer { try? FileManager.default.removeItem(at: root) }

    let encoded = try XCTUnwrap(AgentImagePipeline.encodeForTransport(
      attachment,
      taskId: "small-image",
      timing: timing
    ))

    XCTAssertEqual(encoded.data, data)
    XCTAssertEqual(encoded.mimeType, "image/png")
    XCTAssertTrue(encoded.lossless)
    XCTAssertEqual(encoded.transportName(originalName: attachment.displayName), "original.png")
    XCTAssertEqual(tracer.summary()["phone_runtime_image_prepare_ms"]?.count, 1)
    XCTAssertEqual(tracer.summary()["phone_runtime_image_original_probe_ms"]?.count, 1)
  }

  func testOversizedImageDecodesAndEncodesWithinBudget() throws {
    var data = try XCTUnwrap(testImage().pngData())
    data.append(Data(repeating: 0, count: AgentImagePipeline.targetTransportBytes + 1))
    let attachment = GalaxySSIDraftAttachment(
      displayName: "oversized.png",
      mimeType: "image/png",
      data: data
    )
    let (timing, tracer, root) = makeTiming()
    defer { try? FileManager.default.removeItem(at: root) }

    let encoded = try XCTUnwrap(AgentImagePipeline.encodeForTransport(
      attachment,
      taskId: "large-image",
      timing: timing
    ))

    XCTAssertLessThanOrEqual(encoded.data.count, AgentImagePipeline.targetTransportBytes)
    XCTAssertEqual(encoded.mimeType, "image/jpeg")
    XCTAssertFalse(encoded.lossless)
    XCTAssertEqual(encoded.transportName(originalName: attachment.displayName), "oversized.jpg")
    [
      "phone_runtime_image_prepare_ms",
      "phone_runtime_image_original_probe_ms",
      "phone_runtime_image_decode_ms",
      "phone_runtime_image_encode_ms"
    ].forEach { key in
      XCTAssertEqual(tracer.summary()[key]?.count, 1, key)
      XCTAssertEqual(tracer.summary()[key]?.unsuccessful, 0, key)
    }
  }

  func testCloudAndInlineEncodersShareTransportPolicy() throws {
    let data = try XCTUnwrap(testImage().jpegData(compressionQuality: 0.9))
    let attachment = GalaxySSIDraftAttachment(
      displayName: "shared.jpg",
      mimeType: "image/jpeg",
      data: data
    )

    let cloud = try XCTUnwrap(CloudImagePayloadFactory.prepare([attachment]).first)
    let inline = try XCTUnwrap(AgentMediaAttachmentTransportEncoder.inlinePayload(
      for: attachment,
      profile: nil,
      remainingBytes: CloudImagePayload.maximumBytes
    ))

    XCTAssertEqual(cloud.data, inline.data)
    XCTAssertEqual(cloud.mimeType, inline.mimeType)
    XCTAssertTrue(inline.lossless)
  }

  private func testImage() -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240), format: format).image { context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
      UIColor.systemBlue.setFill()
      context.fill(CGRect(x: 80, y: 60, width: 160, height: 120))
    }
  }

  private func makeTiming() -> (AgentRuntimeTiming, AgentLatencyTracer, URL) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentImagePipelineTests-\(UUID().uuidString)", isDirectory: true)
    var tick: Int64 = 0
    let tracer = AgentLatencyTracer(
      journal: AgentLatencyJournal(fileURL: root.appendingPathComponent("image.jsonl")),
      monotonicNs: { tick += 1_000_000; return tick },
      wallClockMs: { 1 },
      clockId: "1234567890abcdef1234567890abcdef"
    )
    return (AgentRuntimeTiming(tracer: tracer), tracer, root)
  }
}
