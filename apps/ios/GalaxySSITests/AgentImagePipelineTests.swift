import UIKit
import XCTest
@testable import GalaxySSI

final class AgentImagePipelineTests: XCTestCase {
  func testMixedVisionInputsKeepSourceIndicesWithoutGeneratingReferenceSheet() throws {
    let bytes = try XCTUnwrap(testImage().jpegData(compressionQuality: 0.8))
    let old = try CloudImagePayload(displayName: "old.jpg", mimeType: "image/jpeg", data: bytes,
      historicalSourceTurnId: "prior")
    let new = try CloudImagePayload(displayName: "new.jpg", mimeType: "image/jpeg", data: bytes)
    var messages: [[String: Any]] = [["role": "user", "content": "Compare these images"]]
    CloudVisionPayloadEncoder.attachOpenAI(to: &messages, images: [old, new])
    XCTAssertEqual(messages.count, 2)
    let reference = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
    let latest = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
    XCTAssertTrue((reference.first?["text"] as? String)?.contains("image index: 0") == true)
    XCTAssertEqual(latest.count, 3)
    XCTAssertEqual(latest.first?["text"] as? String, "Compare these images")
    XCTAssertEqual(latest.last?["text"] as? String, "Source image index: 1.")
  }

  func testHistoricalImageStaysSeparateFromLatestUserMessageAcrossProviders() throws {
    let image = try CloudImagePayload(displayName: "old.png", mimeType: "image/png", data: Data([1, 2, 3]),
      historicalSourceTurnId: "earlier-turn")
    var openAI: [[String: Any]] = [["role": "user", "content": "Translate this word"]]
    var anthropic = openAI
    var gemini: [[String: Any]] = [["role": "user", "parts": [["text": "Translate this word"]]]]
    CloudVisionPayloadEncoder.attachOpenAI(to: &openAI, images: [image])
    CloudVisionPayloadEncoder.attachAnthropic(to: &anthropic, images: [image])
    CloudVisionPayloadEncoder.attachGemini(to: &gemini, images: [image])
    for (messages, key) in [(openAI, "content"), (anthropic, "content"), (gemini, "parts")] {
      XCTAssertEqual(messages.count, 2)
      let parts = try XCTUnwrap(messages.first?[key] as? [[String: Any]])
      let label = try XCTUnwrap(parts.first?["text"] as? String)
      XCTAssertTrue(label.contains("source turn: earlier-turn"))
      XCTAssertTrue(label.contains("not a new upload"))
      XCTAssertEqual(parts.count, 2)
    }
    XCTAssertEqual(openAI.last?["content"] as? String, "Translate this word")
    XCTAssertEqual(anthropic.last?["content"] as? String, "Translate this word")
    XCTAssertEqual((gemini.last?["parts"] as? [[String: String]])?.first?["text"], "Translate this word")
  }

  func testOrientationSheetRotatesAsymmetricPixelsInClockwiseOrder() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let fixture = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).pngData { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 96, height: 48))
      UIColor.blue.setFill()
      context.fill(CGRect(x: 0, y: 48, width: 96, height: 48))
    }
    let source = try CloudImagePayload(displayName: "split.png", mimeType: "image/png", data: fixture)
    let sheet = try XCTUnwrap(CloudVisionOrientationSheet.make(for: [source]))
    let image = try XCTUnwrap(UIImage(data: sheet.data)?.cgImage)
    let cell = image.width / 2
    func redDominates(cellX: Int, cellY: Int, x: Int, y: Int) throws -> Bool {
      let point = CGRect(x: cellX * cell + x, y: cellY * cell + y, width: 1, height: 1)
      let pixel = try XCTUnwrap(image.cropping(to: point))
      var rgba = [UInt8](repeating: 0, count: 4)
      return try rgba.withUnsafeMutableBytes { buffer in
        let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
          bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return buffer[0] > buffer[2]
      }
    }
    let quarter = cell / 4, middle = cell / 2, far = cell * 3 / 4
    XCTAssertTrue(try redDominates(cellX: 0, cellY: 0, x: middle, y: quarter))
    XCTAssertTrue(try redDominates(cellX: 1, cellY: 0, x: far, y: middle))
    XCTAssertTrue(try redDominates(cellX: 0, cellY: 1, x: middle, y: far))
    XCTAssertTrue(try redDominates(cellX: 1, cellY: 1, x: quarter, y: middle))
    XCTAssertFalse(try redDominates(cellX: 1, cellY: 0, x: quarter, y: middle))
  }

  func testOrientationReferencePreservesOriginalInAllCloudFormats() throws {
    let source = try XCTUnwrap(testImage().jpegData(compressionQuality: 0.8))
    let image = try CloudImagePayload(displayName: "fixture.jpg", mimeType: "image/jpeg", data: source)
    let sheet = try XCTUnwrap(CloudVisionOrientationSheet.make(for: [image]))
    XCTAssertLessThanOrEqual(sheet.data.count, CloudImagePayload.maximumBytes)
    XCTAssertNotEqual(sheet.data, source)
    let decoded = try XCTUnwrap(UIImage(data: sheet.data))
    XCTAssertEqual(decoded.size.width, decoded.size.height)
    XCTAssertNil(CloudVisionOrientationSheet.make(for: []))
    XCTAssertNil(CloudVisionOrientationSheet.make(for: [image, image]))
    let invalid = try CloudImagePayload(displayName: "invalid.jpg", mimeType: "image/jpeg", data: Data([1]))
    XCTAssertNil(CloudVisionOrientationSheet.make(for: [invalid]))

    var openAI: [[String: Any]] = [["role": "user", "content": "Read"]]
    var anthropic = openAI
    var gemini: [[String: Any]] = [["role": "user", "parts": [["text": "Read"]]]]
    CloudVisionPayloadEncoder.attachOpenAI(to: &openAI, images: [image])
    CloudVisionPayloadEncoder.attachAnthropic(to: &anthropic, images: [image])
    CloudVisionPayloadEncoder.attachGemini(to: &gemini, images: [image])
    let openAIParts = try XCTUnwrap(openAI.first?["content"] as? [[String: Any]])
    let anthropicParts = try XCTUnwrap(anthropic.first?["content"] as? [[String: Any]])
    let geminiParts = try XCTUnwrap(gemini.first?["parts"] as? [[String: Any]])
    for parts in [openAIParts, anthropicParts, geminiParts] {
      XCTAssertEqual(parts.count, 5)
      XCTAssertEqual(parts[2]["text"] as? String, "Source image index: 0.")
      XCTAssertEqual(parts[3]["text"] as? String, CloudVisionOrientationSheet.guidance)
    }
    XCTAssertEqual((openAIParts[1]["image_url"] as? [String: String])?["url"], "data:image/jpeg;base64," + image.base64)
    XCTAssertEqual((anthropicParts[1]["source"] as? [String: String])?["data"], image.base64)
    XCTAssertEqual((geminiParts[1]["inline_data"] as? [String: String])?["data"], image.base64)
  }

  func testSourceImageIndicesMatchOriginalOrderInEveryCloudFormat() throws {
    let images = try [1, 2].map { value in
      try CloudImagePayload(displayName: "fixture.png", mimeType: "image/png", data: Data([UInt8(value)]))
    }
    var openAI: [[String: Any]] = [["role": "user", "content": "Mark the second image"]]
    var anthropic = openAI
    var gemini: [[String: Any]] = [["role": "user", "parts": [["text": "Mark the second image"]]]]
    CloudVisionPayloadEncoder.attachOpenAI(to: &openAI, images: images)
    CloudVisionPayloadEncoder.attachAnthropic(to: &anthropic, images: images)
    CloudVisionPayloadEncoder.attachGemini(to: &gemini, images: images)
    for (messages, key) in [(openAI, "content"), (anthropic, "content"), (gemini, "parts")] {
      let parts = try XCTUnwrap(messages.first?[key] as? [[String: Any]])
      XCTAssertEqual(parts.count, 5)
      XCTAssertEqual(parts[2]["text"] as? String, "Source image index: 0.")
      XCTAssertEqual(parts[4]["text"] as? String, "Source image index: 1.")
    }
    XCTAssertTrue(CloudImageAnnotationPlan.instruction(imageCount: 2).contains("cannot be annotated"))
    XCTAssertTrue(CloudImageAnnotationPlan.instruction(imageCount: 0).isEmpty)
  }

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
