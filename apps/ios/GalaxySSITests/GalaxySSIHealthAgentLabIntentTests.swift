import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthAgentLabIntentTests: XCTestCase {
  func testPersonalReportRequestsAreLocalBeforeProviderRouting() {
    for value in ["show my latest lab results", "open my saved blood test report", "my latest lab abnormal results"] {
      XCTAssertNotNil(GalaxySSIHealthAgentLab.intent(value, following: false, language: "en"), value)
    }
    XCTAssertEqual(GalaxySSIHealthAgentLab.intent("my latest lab abnormal results", following: false, language: "en"), .abnormal)
  }
  func testUnqualifiedResultsAndFollowUpsRequireALocalReportInThisChat() {
    for value in ["all results", "abnormal values", "add note about fasting sample", "remind me to recheck next week"] {
      XCTAssertNil(GalaxySSIHealthAgentLab.intent(value, following: false, language: "en"), value)
      XCTAssertNotNil(GalaxySSIHealthAgentLab.intent(value, following: true, language: "en"), value)
    }
  }
  func testOtherPeopleGeneralEducationAndNegationDoNotOpenPersonalRecords() {
    for value in ["show my father lab results", "show her blood test report", "why are my lab values high",
      "do not show my lab results", "cancel recheck reminder", "write a template for my lab report"] {
      XCTAssertNil(GalaxySSIHealthAgentLab.intent(value, following: true, language: "en"), value)
    }
  }
  func testLocalizedNavigationLabelsAlsoMatchLocalIntent() {
    let all = GalaxySSIHealthAgentLab.text("question_all", "show my lab results", LanguagePolicySettings.zhCN)
    let abnormal = GalaxySSIHealthAgentLab.text("question_abnormal", "show my abnormal lab results", LanguagePolicySettings.zhCN)
    XCTAssertEqual(GalaxySSIHealthAgentLab.intent(all, following: false, language: "en"), .results)
    XCTAssertEqual(GalaxySSIHealthAgentLab.intent(abnormal, following: false, language: "en"), .abnormal)
  }
  func testTranscriptMarkerMustBeAnOriginalHostCreatedReply() {
    let turn = "00000000-0000-4000-8000-000000000001"
    var message = ChatMessage(contactId: "hermes", content: "Open saved lab results", isMine: false,
      deliveryTrace: [.init(stage: GalaxySSIHealthAgentLab.stage)], conversationId: "synthetic-chat", turnId: turn,
      remoteMessageId: GalaxySSIHealthAgentLab.marker + "results:" + turn)
    XCTAssertEqual(GalaxySSIHealthAgentLab.mode(message), .results)
    message.deliveryTrace = [.init(stage: "received")]
    XCTAssertNil(GalaxySSIHealthAgentLab.mode(message))
    message.deliveryTrace = [.init(stage: GalaxySSIHealthAgentLab.stage)]; message.isMine = true
    XCTAssertNil(GalaxySSIHealthAgentLab.mode(message))
    message.isMine = false; message.sourceConversationId = "copied-chat"
    XCTAssertNil(GalaxySSIHealthAgentLab.mode(message))
    message.sourceConversationId = ""; message.remoteMessageId = GalaxySSIHealthAgentLab.marker + "results:other-turn"
    XCTAssertNil(GalaxySSIHealthAgentLab.mode(message))
  }
  func testSuggestedDatesUseCalendarRatherThanFixedMonthSeconds() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9))!
    let next = GalaxySSIHealthAgentLab.suggestedDay("recheck next month", now: start, calendar: calendar)
    XCTAssertEqual(next, calendar.date(byAdding: .month, value: 1, to: start))
    XCTAssertNil(GalaxySSIHealthAgentLab.suggestedDay("sometime", now: start, calendar: calendar))
  }
  func testLegacyReminderDecodesWithoutInventingLabPermission() throws {
    let reminder = GalaxySSIHealthCareFollowUp.Reminder(id: UUID(), actionID: "synthetic-action", concernID: UUID(),
      metric: .glucose, requestedAt: Date(timeIntervalSince1970: 1))
    XCTAssertNil(try JSONDecoder().decode(GalaxySSIHealthCareFollowUp.Reminder.self,
      from: JSONEncoder().encode(reminder)).labReview)
  }
}
