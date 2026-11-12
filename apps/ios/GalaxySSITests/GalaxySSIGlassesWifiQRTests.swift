import Foundation
import UIKit
import Vision
import XCTest
@testable import GalaxySSI

final class GalaxySSIGlassesWifiQRTests: XCTestCase {
  func testWirePreservesExactSSIDAndPassphraseWithoutRawNonASCII() throws {
    let ssid = " \u{6D4B}\u{8BD5}\u{1F4F6};\"\\ "
    let passphrase = " abcd\\\";123 "
    let wire = try XCTUnwrap(GalaxySSIGlassesWifiQR.payload(ssid: ssid, password: passphrase))
    XCTAssertTrue(wire.utf8.allSatisfy { $0 < 128 })
    let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(wire.utf8)) as? [String: String])
    XCTAssertEqual(value, ["type": "galaxyssi_wifi_v1", "ssid": ssid, "passphrase": passphrase])
  }

  func testWPA2AndSSIDBoundsMatchTheGlassesContract() {
    XCTAssertNotNil(GalaxySSIGlassesWifiQR.payload(ssid: String(repeating: "\u{1F4F6}", count: 8),
      password: String(repeating: "a", count: 63)))
    XCTAssertNotNil(GalaxySSIGlassesWifiQR.payload(ssid: "Hidden network", password: "abcd1234"))
    for ssid in ["", "  ", "test\n", String(repeating: "x", count: 33), String(repeating: "\u{1F4F6}", count: 9)] {
      XCTAssertNil(GalaxySSIGlassesWifiQR.payload(ssid: ssid, password: "abcd1234"))
    }
    for password in ["", "1234567", String(repeating: "a", count: 64), "test\nword", "test\u{00E9}word"] {
      XCTAssertNil(GalaxySSIGlassesWifiQR.payload(ssid: "Network", password: password))
    }
  }

  @MainActor func testRenderedCodeDecodesToGlassesPayload() throws {
    let payload = try XCTUnwrap(GalaxySSIGlassesWifiQR.payload(ssid: "Fixture", password: "synthetic-key"))
    let qr = try XCTUnwrap(GalaxySSIQRCodeImageRenderer.image(from: payload))
    let canvas = CGSize(width: qr.size.width + 80, height: qr.size.height + 80)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let padded = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: canvas))
      qr.draw(at: CGPoint(x: 40, y: 40))
    }
    let image = try XCTUnwrap(padded.cgImage)
    let detector = VNDetectBarcodesRequest()
    detector.symbologies = [.qr]
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([detector])
    XCTAssertEqual(detector.results?.first?.payloadStringValue, payload)
  }
}
