import CoreGraphics
import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthPDFPreparationTests: XCTestCase {
  func testRecognitionPreparationRequiresPasswordAndExtractionPermission() throws {
    let allowed = try pdf(copying: true)
    XCTAssertThrowsError(try GalaxySSIHealthRecognitionJobs.pdfPageCount(allowed)) {
      guard case GalaxySSIHealthPDFText.Failure.locked = $0 else { return XCTFail("Expected locked") }
    }
    XCTAssertThrowsError(try GalaxySSIHealthRecognitionJobs.pdfPageCount(allowed, password: "wrong")) {
      guard case GalaxySSIHealthPDFText.Failure.incorrectPassword = $0 else { return XCTFail("Expected incorrect password") }
    }
    XCTAssertEqual(try GalaxySSIHealthRecognitionJobs.pdfPageCount(allowed, password: "reader"), 2)
    XCTAssertThrowsError(try GalaxySSIHealthRecognitionJobs.pdfPageCount(pdf(copying: false), password: "reader")) {
      guard case GalaxySSIHealthPDFText.Failure.extractionRestricted = $0 else { return XCTFail("Expected extraction restriction") }
    }
  }

  func testDisplayOnlyPreviewDoesNotGrantTextExtraction() throws {
    let data = try pdf(copying: false)
    let preview = try GalaxySSIHealthPDFText.previewPage(data, page: 1, password: "reader")
    XCTAssertEqual(preview.pages, 2)
    XCTAssertGreaterThan(preview.image.width, 0)
    XCTAssertGreaterThan(preview.image.height, 0)
    XCTAssertLessThanOrEqual(max(preview.image.width, preview.image.height), 1_600)
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.read(data, page: 1, password: "reader")) {
      guard case GalaxySSIHealthPDFText.Failure.extractionRestricted = $0 else { return XCTFail("Display must not authorize copying") }
    }
  }

  func testPreviewRejectsWrongPasswordAndInvalidPageBeforePublishingAnImage() throws {
    let data = try pdf(copying: true)
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.previewPage(data, page: 0))
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.previewPage(data, page: 0, password: "wrong"))
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.previewPage(data, page: -1, password: "reader"))
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.previewPage(data, page: 2, password: "reader"))
    XCTAssertEqual(try GalaxySSIHealthPDFText.previewPage(data, page: 0, password: "reader").pages, 2)
  }

  func testCancelledWorkerRejectsBothPreparationAndPreview() async throws {
    let data = try pdf(copying: true)
    for preview in [false, true] {
      let gate = PreparationGate()
      let worker = Task.detached {
        await gate.wait()
        if preview { return try GalaxySSIHealthPDFText.previewPage(data, page: 0, password: "reader").pages }
        return try GalaxySSIHealthRecognitionJobs.pdfPageCount(data, password: "reader")
      }
      worker.cancel()
      await gate.release()
      do { _ = try await worker.value; XCTFail("A cancelled worker must not return a PDF result") }
      catch is CancellationError {}
      catch { XCTFail("Expected cancellation, not \(error)") }
    }
  }

  private func pdf(copying: Bool) throws -> Data {
    let bytes = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: bytes as CFMutableData))
    var bounds = CGRect(x: 0, y: 0, width: 200, height: 120)
    let options: [String: Any] = [kCGPDFContextUserPassword as String: "reader",
      kCGPDFContextOwnerPassword as String: "owner", kCGPDFContextAllowsCopying as String: copying]
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, options as CFDictionary))
    for _ in 0..<2 {
      context.beginPDFPage(nil)
      context.setFillColor(gray: 1, alpha: 1)
      context.fill(bounds)
      context.setFillColor(gray: 0, alpha: 1)
      context.fill(CGRect(x: 25, y: 30, width: 80, height: 12))
      context.endPDFPage()
    }
    context.closePDF()
    return bytes as Data
  }
}

private actor PreparationGate {
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?
  func wait() async {
    if released { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func release() { released = true; continuation?.resume(); continuation = nil }
}
