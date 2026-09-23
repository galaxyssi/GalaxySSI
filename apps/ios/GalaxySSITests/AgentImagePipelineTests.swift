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
    XCTAssertEqual(cloud.originalData, attachment.data)
    XCTAssertEqual(cloud.mimeType, inline.mimeType)
    XCTAssertTrue(inline.lossless)
  }

  func testImageAnnotationDrawsCompactInkOnOriginalCanvas() throws {
    let plan = try CloudImageAnnotationPlan.parse(annotationArguments(), imageCount: 1)
    let source = testImage()
    let rendered = try CloudImageAnnotationRenderer.render(source: source, plan: plan)

    XCTAssertEqual(rendered.size, source.size)
    XCTAssertNotEqual(rendered.pngData(), source.pngData())
    XCTAssertEqual(plan.marks.count, 2)
    XCTAssertEqual(plan.marks[1].correction, "4")
  }

  func testImageAnnotationRejectsInvalidCoordinatesAndMissingCorrection() {
    var arguments = annotationArguments()
    var marks = arguments["marks"]?.arrayValue ?? []
    var first = marks[0].objectValue ?? [:]
    first["right"] = .double(1.2)
    marks[0] = .object(first)
    arguments["marks"] = .array(marks)
    XCTAssertThrowsError(try CloudImageAnnotationPlan.parse(arguments, imageCount: 1))

    arguments = annotationArguments()
    marks = arguments["marks"]?.arrayValue ?? []
    var second = marks[1].objectValue ?? [:]
    second["correction"] = .string("")
    marks[1] = .object(second)
    arguments["marks"] = .array(marks)
    XCTAssertThrowsError(try CloudImageAnnotationPlan.parse(arguments, imageCount: 1))
  }

  func testImageAnnotationToolIsRequestScopedAndReturnsOneCard() throws {
    let data = try XCTUnwrap(testImage().pngData())
    let image = try CloudImagePayload(displayName: "worksheet.png", mimeType: "image/png", data: data)
    let context = CloudConversationToolExecutionContext(
      requestId: "annotation-test-\(UUID().uuidString)",
      conversationId: "conversation",
      turnId: "turn",
      images: [image]
    )

    let result = try CloudImageAnnotationSession.execute(arguments: annotationArguments(), context: context)
    XCTAssertTrue(result.contains(#""image_saved":true"#))
    let suffix = CloudImageAnnotationSession.artifactSuffix(requestId: context.requestId)
    let blocks = AgentRichContentCodec.decode(
      suffix.replacingOccurrences(of: "```galaxyssi-rich", with: "")
        .replacingOccurrences(of: "```", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    )
    XCTAssertEqual(blocks.count, 1)
    XCTAssertEqual(blocks.first?.type, .image)
    XCTAssertTrue(CloudImageAnnotationSession.artifactSuffix(requestId: context.requestId).isEmpty)
  }

  func testImageAnnotationSchemaIsOnlyAdvertisedForImageTurns() {
    let withoutImages = CloudModelStreamToolSchemas.openAITools()
    let withImages = CloudModelStreamToolSchemas.openAITools(includeImageAnnotation: true)
    func names(_ tools: [[String: Any]]) -> [String] {
      tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
    }

    XCTAssertFalse(names(withoutImages).contains(CloudImageAnnotationPlan.toolName))
    XCTAssertTrue(names(withImages).contains(CloudImageAnnotationPlan.toolName))
  }

  private func annotationArguments() -> AgentMcpJSONObject {
    [
      "image_index": .int(0),
      "marks": .array([
        .object([
          "left": .double(0.20), "top": .double(0.20),
          "right": .double(0.40), "bottom": .double(0.40),
          "verdict": .string("correct"), "note": .string("Correct answer"),
          "correction": .string("")
        ]),
        .object([
          "left": .double(0.55), "top": .double(0.55),
          "right": .double(0.75), "bottom": .double(0.75),
          "verdict": .string("incorrect"), "note": .string("Recalculate"),
          "correction": .string("4")
        ])
      ])
    ]
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
