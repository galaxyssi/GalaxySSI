import XCTest
@testable import GalaxySSI

final class GalaxySSIScreenAssistantAvailabilityTests: XCTestCase {
  func testCaptureAndForegroundChangesDoNotChangeSavedPreference() throws {
    let preference = AppDisplaySettings(screenAssistantEnabled: true)
    func state(_ capture: GalaxySSIScreenAssistantCapture, foreground: Bool = true) -> GalaxySSIScreenAssistantAvailability {
      .resolve(enabled: preference.screenAssistantEnabled, foreground: foreground, capture: capture)
    }
    XCTAssertEqual(state(.noWindow), .waitingForWindow)
    XCTAssertEqual(state(.clear), .available)
    XCTAssertEqual(state(.captured), .screenCaptured)
    XCTAssertEqual(state(.captured, foreground: false), .inactive)
    XCTAssertEqual(state(.clear), .available)
    let reopened = try JSONDecoder().decode(AppDisplaySettings.self, from: JSONEncoder().encode(preference))
    XCTAssertTrue(reopened.screenAssistantEnabled)
  }

  func testLauncherNeedsAvailableForegroundAgentHomeWithoutPicker() {
    XCTAssertTrue(GalaxySSIScreenAssistantAvailability.available.showsLauncher(onAgentHome: true, sourcePickerPresented: false))
    XCTAssertFalse(GalaxySSIScreenAssistantAvailability.available.showsLauncher(onAgentHome: false, sourcePickerPresented: false))
    XCTAssertFalse(GalaxySSIScreenAssistantAvailability.available.showsLauncher(onAgentHome: true, sourcePickerPresented: true))
    XCTAssertFalse(GalaxySSIScreenAssistantAvailability.screenCaptured.showsLauncher(onAgentHome: true, sourcePickerPresented: false))
    XCTAssertEqual(GalaxySSIScreenAssistantAvailability.resolve(enabled: false, foreground: true, capture: .clear), .disabled)
  }
}
