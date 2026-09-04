import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(Vision)
import Vision
#endif

struct AgentIOSWebMediaOCRRequest: Equatable {
  var contentURI: String
  var sourceKind: String
  var scriptHint: String
  var maxSourceBytes: Int64
  var timeoutMillis: Int64
}

struct AgentIOSWebMediaOCRLine: Equatable {
  var text: String
  var left: Int
  var top: Int
  var right: Int
  var bottom: Int
  var languageTag: String
  var blockIndex: Int
  var lineIndex: Int
}

struct AgentIOSWebMediaOCRBlock: Equatable {
  var text: String
  var left: Int
  var top: Int
  var right: Int
  var bottom: Int
  var lineCount: Int
}

struct AgentIOSWebMediaOCRResult: Equatable {
  var text: String
  var lines: [AgentIOSWebMediaOCRLine]
  var blocks: [AgentIOSWebMediaOCRBlock]
  var width: Int
  var height: Int
  var languageTags: [String]
  var layoutMode: String
  var qualityScore: Double
  var warnings: [String]
}

enum AgentIOSWebMediaOCRError: Error, Equatable {
  case invalidSourceKind
  case invalidScriptHint
  case invalidSourceSize
  case unsupportedOCRContent
  case ocrUnavailable
  case ocrFailed(String)
  case ocrEmptyResult
  case ocrResultTooLarge
  case invalidOCRResult
}

protocol AgentIOSWebMediaOCRRecognizing {
  var implementationId: String { get }
  var availability: AgentNativeToolAvailability { get }
  func recognize(
    content: AgentIOSWebMediaContent,
    request: AgentIOSWebMediaOCRRequest
  ) throws -> AgentIOSWebMediaOCRResult
}

protocol AgentIOSWebMediaOCRProcessing {
  var implementationId: String { get }
  var contentReaderImplementationId: String { get }
  var availability: AgentNativeToolAvailability { get }
  func invoke(input: AgentMcpJSONObject, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
}

struct AgentIOSWebMediaOCRPipeline: AgentIOSWebMediaOCRProcessing {
  var contentReader: AgentIOSWebMediaContentReading
  var recognizer: AgentIOSWebMediaOCRRecognizing
  var nowMillis: () -> Int64

  var implementationId: String {
    recognizer.implementationId
  }

  var contentReaderImplementationId: String {
    contentReader.implementationId
  }

  var availability: AgentNativeToolAvailability {
    recognizer.availability
  }

  init(
    contentReader: AgentIOSWebMediaContentReading = AgentIOSFileWebMediaContentReader(),
    recognizer: AgentIOSWebMediaOCRRecognizing = AgentIOSVisionTextOCRRecognizer(),
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    self.contentReader = contentReader
    self.recognizer = recognizer
    self.nowMillis = nowMillis
  }

  func invoke(input: AgentMcpJSONObject, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    do {
      let request = try ocrRequest(input, invocation: invocation)
      let content = try contentReader.read(contentURI: request.contentURI, maxBytes: request.maxSourceBytes)
      let result = try recognizer.recognize(content: content, request: request)
        .normalizedOCRLayout(scriptHint: request.scriptHint)
        .bounded()
      var output = result.output(
        contentURI: request.contentURI,
        sourceKind: request.sourceKind,
        scriptHint: request.scriptHint,
        observedAtEpochMillis: nowMillis()
      )
      output["content_uri"] = output["content_uri"] ?? .string(request.contentURI)
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: "OCR completed for selected content",
        metadata: [
          "implementation": .string("galaxyssi.ios.web_media_ocr_pipeline"),
          "platform": .string("ios_phone"),
          "bounded": .bool(true),
          "ocr_implementation": .string(recognizer.implementationId),
          "content_reader_implementation": .string(contentReader.implementationId),
          "source_scope": .string("selected_or_captured_file_url"),
          "result_policy": .string("bounded-v1")
        ]
      )
    } catch let error as AgentIOSWebMediaContentReadError {
      return contentReadFailure(error)
    } catch let error as AgentIOSWebMediaOCRError {
      return ocrFailure(error)
    } catch {
      return failure("ocr_failed", error.localizedDescription, retryable: true)
    }
  }

  private func ocrRequest(
    _ input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) throws -> AgentIOSWebMediaOCRRequest {
    let contentURI = string(input, "content_uri", limit: 4_096)
    let sourceKind = string(input, "source_kind", limit: 32)
    guard ["image", "screenshot", "camera", "document"].contains(sourceKind) else {
      throw AgentIOSWebMediaOCRError.invalidSourceKind
    }
    let scriptHint = string(input, "script_hint", limit: 32).nilIfEmpty ?? "auto"
    guard ["auto", "latin", "chinese", "japanese", "korean", "devanagari"].contains(scriptHint) else {
      throw AgentIOSWebMediaOCRError.invalidScriptHint
    }
    let maxSourceBytes = input["max_source_bytes"]?.intValue ?? AgentIOSWebMediaNativeToolCatalog.maxOcrSourceBytes
    guard maxSourceBytes >= 1, maxSourceBytes <= AgentIOSWebMediaNativeToolCatalog.maxOcrSourceBytes else {
      throw AgentIOSWebMediaOCRError.invalidSourceSize
    }
    let requestedTimeout = input["timeout_ms"]?.intValue ?? AgentIOSWebMediaNativeToolCatalog.maxToolTimeoutMillis
    let remaining = invocation.remainingTimeMillis
    let timeoutMillis = max(1, min(requestedTimeout, remaining, AgentIOSWebMediaNativeToolCatalog.maxToolTimeoutMillis))
    return AgentIOSWebMediaOCRRequest(
      contentURI: contentURI,
      sourceKind: sourceKind,
      scriptHint: scriptHint,
      maxSourceBytes: maxSourceBytes,
      timeoutMillis: timeoutMillis
    )
  }

  private func contentReadFailure(_ error: AgentIOSWebMediaContentReadError) -> AgentNativeToolExecutionResult {
    switch error {
    case .contentURIRequired:
      return failure("content_uri_required", "A user-authorized file:// URI is required")
    case .unsupportedContentScheme:
      return failure("unsupported_content_uri", "iOS OCR currently requires a selected file:// content URI")
    case .invalidContentURI:
      return failure("invalid_content_uri", "OCR content URI is invalid")
    case .contentUnavailable(let message):
      return failure(
        "content_uri_unavailable",
        message.isEmpty ? "Selected OCR content cannot be opened" : message,
        retryable: true
      )
    case .contentTooLarge(let actualBytes, let maxBytes):
      return failure(
        "invalid_ocr_source_size",
        "Selected OCR content exceeds its bounded size",
        details: [
          "content_length_bytes": .int(actualBytes),
          "max_source_bytes": .int(maxBytes)
        ]
      )
    }
  }

  private func ocrFailure(_ error: AgentIOSWebMediaOCRError) -> AgentNativeToolExecutionResult {
    switch error {
    case .invalidSourceKind:
      return failure("invalid_source_kind", "OCR source_kind is invalid")
    case .invalidScriptHint:
      return failure("invalid_script_hint", "OCR script_hint is invalid")
    case .invalidSourceSize:
      return failure("invalid_ocr_source_size", "Selected OCR content exceeds its bounded size")
    case .unsupportedOCRContent:
      return failure("unsupported_ocr_content", "Selected content is not a decodable image")
    case .ocrUnavailable:
      return failure("ocr_unavailable", "Vision text recognition is unavailable on this platform", retryable: true)
    case .ocrFailed(let message):
      return failure("ocr_failed", message.isEmpty ? "Vision OCR failed" : message, retryable: true)
    case .ocrEmptyResult:
      return failure("ocr_empty_result", "OCR did not produce readable text", retryable: true)
    case .ocrResultTooLarge:
      return failure("ocr_result_too_large", "OCR result exceeded the bounded output limit")
    case .invalidOCRResult:
      return failure("invalid_ocr_result", "OCR implementation returned invalid bounded output")
    }
  }

  private func failure(
    _ code: String,
    _ message: String,
    retryable: Bool = false,
    details: AgentMcpJSONObject = [:]
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(code: code, message: message, retryable: retryable, details: details)
  }

  private func string(_ input: AgentMcpJSONObject, _ key: String, limit: Int) -> String {
    String((input[key]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}

struct AgentIOSVisionTextOCRRecognizer: AgentIOSWebMediaOCRRecognizing {
  var implementationId = "vision.text_recognition"

  var availability: AgentNativeToolAvailability {
    #if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics) && os(iOS)
    return .available
    #else
    return AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Vision OCR is available only in the iOS app target."
    )
    #endif
  }

  func recognize(
    content: AgentIOSWebMediaContent,
    request: AgentIOSWebMediaOCRRequest
  ) throws -> AgentIOSWebMediaOCRResult {
    #if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics) && os(iOS)
    guard !content.data.isEmpty, Int64(content.data.count) <= request.maxSourceBytes else {
      throw AgentIOSWebMediaOCRError.invalidSourceSize
    }
    guard let imageSource = CGImageSourceCreateWithData(content.data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
      throw AgentIOSWebMediaOCRError.unsupportedOCRContent
    }
    let textRequest = VNRecognizeTextRequest()
    textRequest.recognitionLevel = .accurate
    textRequest.usesLanguageCorrection = true
    textRequest.recognitionLanguages = recognitionLanguages(scriptHint: request.scriptHint)
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
    do {
      try handler.perform([textRequest])
    } catch {
      throw AgentIOSWebMediaOCRError.ocrFailed(error.localizedDescription)
    }
    let observations = textRequest.results ?? []
    let width = max(0, image.width)
    let height = max(0, image.height)
    var confidences: [Double] = []
    let lines: [AgentIOSWebMediaOCRLine] = observations.enumerated().compactMap { index, observation in
      guard let candidate = observation.topCandidates(1).first else {
        return nil
      }
      let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        return nil
      }
      confidences.append(Double(candidate.confidence))
      let box = pixelBounds(observation.boundingBox, width: width, height: height)
      return AgentIOSWebMediaOCRLine(
        text: text,
        left: box.left,
        top: box.top,
        right: box.right,
        bottom: box.bottom,
        languageTag: languageTag(scriptHint: request.scriptHint),
        blockIndex: index,
        lineIndex: 0
      )
    }
    let text = lines.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      throw AgentIOSWebMediaOCRError.ocrEmptyResult
    }
    return AgentIOSWebMediaOCRResult(
      text: text,
      lines: lines,
      blocks: lines.map { line in
        AgentIOSWebMediaOCRBlock(
          text: line.text,
          left: line.left,
          top: line.top,
          right: line.right,
          bottom: line.bottom,
          lineCount: 1
        )
      },
      width: width,
      height: height,
      languageTags: Array(Set(lines.map(\.languageTag)).filter { !$0.isEmpty }).sorted(),
      layoutMode: "vision_text_observations",
      qualityScore: confidences.isEmpty ? 0.0 : min(1.0, max(0.0, confidences.reduce(0.0, +) / Double(confidences.count))),
      warnings: []
    )
    #else
    throw AgentIOSWebMediaOCRError.ocrUnavailable
    #endif
  }

  private func recognitionLanguages(scriptHint: String) -> [String] {
    switch scriptHint {
    case "latin":
      return ["en-US"]
    case "chinese":
      return ["zh-Hans", "zh-Hant"]
    case "japanese":
      return ["ja-JP"]
    case "korean":
      return ["ko-KR"]
    case "devanagari":
      return ["hi-IN"]
    default:
      return ["en-US", "zh-Hans"]
    }
  }

  private func languageTag(scriptHint: String) -> String {
    switch scriptHint {
    case "chinese":
      return "zh"
    case "japanese":
      return "ja"
    case "korean":
      return "ko"
    case "devanagari":
      return "hi"
    default:
      return "en"
    }
  }

  private func pixelBounds(_ normalized: CGRect, width: Int, height: Int) -> (left: Int, top: Int, right: Int, bottom: Int) {
    let safeWidth = max(0, width)
    let safeHeight = max(0, height)
    let left = Int((normalized.minX * CGFloat(safeWidth)).rounded(.down))
    let right = Int((normalized.maxX * CGFloat(safeWidth)).rounded(.up))
    let top = Int(((1.0 - normalized.maxY) * CGFloat(safeHeight)).rounded(.down))
    let bottom = Int(((1.0 - normalized.minY) * CGFloat(safeHeight)).rounded(.up))
    return (
      left: max(0, min(left, safeWidth)),
      top: max(0, min(top, safeHeight)),
      right: max(0, min(max(right, left), safeWidth)),
      bottom: max(0, min(max(bottom, top), safeHeight))
    )
  }
}

private extension AgentIOSWebMediaOCRResult {
  func normalizedOCRLayout(scriptHint: String) -> AgentIOSWebMediaOCRResult {
    let script = AgentOcrScript.fromWireValue(scriptHint) ?? .auto
    let merged = AgentOcrLayoutAnalyzer.merge(
      candidates: [
        AgentOcrCandidate(
          script: script,
          fallbackText: text,
          lines: lines.map(\.ocrLine)
        )
      ],
      width: width,
      height: height
    )
    return AgentIOSWebMediaOCRResult(
      text: merged.text,
      lines: merged.lines.map(AgentIOSWebMediaOCRLine.init),
      blocks: merged.blocks.map(AgentIOSWebMediaOCRBlock.init),
      width: width,
      height: height,
      languageTags: merged.languageTags,
      layoutMode: merged.layoutMode,
      qualityScore: merged.qualityScore,
      warnings: merged.warnings
    )
  }

  func bounded() throws -> AgentIOSWebMediaOCRResult {
    guard width >= 0,
          height >= 0,
          qualityScore.isFinite,
          qualityScore >= 0.0,
          qualityScore <= 1.0,
          layoutMode.count <= 64 else {
      throw AgentIOSWebMediaOCRError.invalidOCRResult
    }
    guard text.count <= Int(AgentIOSWebMediaNativeToolCatalog.maxContentCharacters),
          lines.count <= 500,
          blocks.count <= 200,
          lines.allSatisfy({ $0.isBounded }),
          blocks.allSatisfy({ $0.isBounded }),
          languageTags.allSatisfy({ $0.count <= 64 }),
          warnings.allSatisfy({ $0.count <= 128 }) else {
      throw AgentIOSWebMediaOCRError.ocrResultTooLarge
    }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentIOSWebMediaOCRError.ocrEmptyResult
    }
    return AgentIOSWebMediaOCRResult(
      text: text,
      lines: Array(lines.prefix(500)),
      blocks: Array(blocks.prefix(200)),
      width: width,
      height: height,
      languageTags: Array(languageTags.prefix(64)),
      layoutMode: layoutMode,
      qualityScore: qualityScore,
      warnings: Array(warnings.prefix(16))
    )
  }

  func output(
    contentURI: String,
    sourceKind: String,
    scriptHint: String,
    observedAtEpochMillis: Int64
  ) -> AgentMcpJSONObject {
    [
      "text": .string(text),
      "lines": .array(lines.map(\.jsonValue)),
      "blocks": .array(blocks.map(\.jsonValue)),
      "width": .int(Int64(width)),
      "height": .int(Int64(height)),
      "language_tags": .array(languageTags.map(AgentMcpJSONValue.string)),
      "layout_mode": .string(layoutMode),
      "quality_score": .double(qualityScore),
      "warnings": .array(warnings.map(AgentMcpJSONValue.string)),
      "content_uri": .string(contentURI),
      "source_kind": .string(sourceKind),
      "script_hint": .string(scriptHint),
      "observed_at_epoch_ms": .int(observedAtEpochMillis),
      "source": .object([
        "content_uri": .string(contentURI),
        "source_kind": .string(sourceKind)
      ])
    ]
  }
}

private extension AgentIOSWebMediaOCRLine {
  init(_ line: AgentOcrLine) {
    self.init(
      text: line.text,
      left: line.left,
      top: line.top,
      right: line.right,
      bottom: line.bottom,
      languageTag: line.languageTag,
      blockIndex: line.blockIndex,
      lineIndex: line.lineIndex
    )
  }

  var ocrLine: AgentOcrLine {
    AgentOcrLine(
      text: text,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      languageTag: languageTag,
      blockIndex: blockIndex,
      lineIndex: lineIndex
    )
  }

  var isBounded: Bool {
    !text.isEmpty &&
      text.count <= 4_096 &&
      left >= 0 &&
      top >= 0 &&
      right >= left &&
      bottom >= top &&
      languageTag.count <= 64 &&
      blockIndex >= 0 &&
      lineIndex >= 0
  }

  var jsonValue: AgentMcpJSONValue {
    .object([
      "text": .string(text),
      "left": .int(Int64(left)),
      "top": .int(Int64(top)),
      "right": .int(Int64(right)),
      "bottom": .int(Int64(bottom)),
      "language_tag": .string(languageTag),
      "block_index": .int(Int64(blockIndex)),
      "line_index": .int(Int64(lineIndex))
    ])
  }
}

private extension AgentIOSWebMediaOCRBlock {
  init(_ block: AgentOcrBlock) {
    self.init(
      text: block.text,
      left: block.left,
      top: block.top,
      right: block.right,
      bottom: block.bottom,
      lineCount: block.lineCount
    )
  }

  var isBounded: Bool {
    !text.isEmpty &&
      text.count <= 16_384 &&
      left >= 0 &&
      top >= 0 &&
      right >= left &&
      bottom >= top &&
      lineCount >= 1
  }

  var jsonValue: AgentMcpJSONValue {
    .object([
      "text": .string(text),
      "left": .int(Int64(left)),
      "top": .int(Int64(top)),
      "right": .int(Int64(right)),
      "bottom": .int(Int64(bottom)),
      "line_count": .int(Int64(lineCount))
    ])
  }
}
