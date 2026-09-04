import XCTest
@testable import GalaxySSI

final class AgentSkillCommandParserTests: XCTestCase {
  func testAgentSkillCommandParserMatchesAndroidSaveAndUpgradeCommands() {
    XCTAssertFalse(AgentSkillCommandParser.isSaveCommand("Search today's news"))
    XCTAssertFalse(AgentSkillCommandParser.isSaveCommand("Remember this preference"))
    XCTAssertTrue(AgentSkillCommandParser.isSaveCommand("Save this as a Skill"))
    XCTAssertTrue(AgentSkillCommandParser.isSaveCommand("\u{4fdd}\u{5b58}\u{6210} Skill"))
    XCTAssertTrue(AgentSkillCommandParser.isSaveCommand(
      "\u{4fdd}\u{5b58}\u{6210}skill,\u{4ee5}\u{540e}\u{6211}\u{8bf4}\u{67e5}\u{4ec0}\u{4e48}\u{5b57}\u{7b14}\u{987a}\u{7b14}\u{753b}\u{5c31}\u{8c03}\u{7528}\u{8fd9}\u{4e2a}skill"
    ))
    XCTAssertTrue(AgentSkillCommandParser.isSaveCommand(
      "\u{628a}\u{8fd9}\u{4e2a}\u{4fdd}\u{5b58}\u{4e3a} Skill\u{ff0c}\u{4ee5}\u{540e}\u{7ee7}\u{7eed}\u{4f7f}\u{7528}"
    ))
    XCTAssertFalse(AgentSkillCommandParser.isSaveCommand("\u{4e0d}\u{8981}\u{4fdd}\u{5b58}\u{6210} Skill"))
    XCTAssertTrue(AgentSkillCommandParser.isUpgradeCommand("Upgrade this Skill"))
    XCTAssertTrue(AgentSkillCommandParser.isUpgradeCommand("\u{5347}\u{7ea7}\u{8fd9}\u{4e2a} Skill"))
  }
}
