import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentCronExpressionMatchesAndroidTimeZoneAndWeekdayBehavior() throws {
    let weekdayCron = try AgentCronExpression.parse("30 9 * * mon-fri")
    let shanghai = try AgentCronExpression.parseZone("Asia/Shanghai")
    let friday = cronMillis(year: 2026, month: 7, day: 24, hour: 9, minute: 31, timeZone: shanghai)
    let nextMonday = cronMillis(year: 2026, month: 7, day: 27, hour: 9, minute: 30, timeZone: shanghai)

    XCTAssertEqual(
      try weekdayCron.nextAfter(timestampMillis: friday, timeZoneIdentifier: shanghai.identifier),
      nextMonday
    )

    let dayOrWeekday = try AgentCronExpression.parse("0 12 1 * mon")
    let utc = try AgentCronExpression.parseZone("UTC")
    let monday = cronDate(year: 2026, month: 7, day: 6, hour: 12, minute: 0, timeZone: utc)
    let firstOfMonth = cronDate(year: 2026, month: 8, day: 1, hour: 12, minute: 0, timeZone: utc)

    XCTAssertTrue(dayOrWeekday.matches(date: monday, timeZone: utc))
    XCTAssertTrue(dayOrWeekday.matches(date: firstOfMonth, timeZone: utc))
  }

  func testAgentCronExpressionSupportsAliasesListsStepsAndPreviousMatches() throws {
    let cron = try AgentCronExpression.parse("*/15 8,12 * jan,mar 0,7")
    let utc = try AgentCronExpression.parseZone("UTC")
    let sunday = cronDate(year: 2026, month: 3, day: 1, hour: 12, minute: 45, timeZone: utc)
    let monday = cronDate(year: 2026, month: 3, day: 2, hour: 12, minute: 45, timeZone: utc)
    let daily = try AgentCronExpression.parse("0 9 * * *")
    let after = cronMillis(year: 2026, month: 3, day: 2, hour: 9, minute: 30, timeZone: utc)
    let expectedPrevious = cronMillis(year: 2026, month: 3, day: 2, hour: 9, minute: 0, timeZone: utc)

    XCTAssertTrue(cron.matches(date: sunday, timeZone: utc))
    XCTAssertFalse(cron.matches(date: monday, timeZone: utc))
    XCTAssertEqual(
      try daily.previousAtOrBefore(timestampMillis: after, timeZoneIdentifier: "UTC"),
      expectedPrevious
    )
    XCTAssertThrowsError(try AgentCronExpression.parse("60 * * * *"))
    XCTAssertThrowsError(try AgentCronExpression.parseZone("Not/AZone"))
  }

  private func cronDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    timeZone: TimeZone
  ) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
  }

  private func cronMillis(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    timeZone: TimeZone
  ) -> Int64 {
    Int64((cronDate(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      timeZone: timeZone
    ).timeIntervalSince1970 * 1_000).rounded())
  }
}
