import Foundation

enum GalaxySSIHealthOverviewGuidance {
  enum SleepBand: String { case adultUnspecified, months0_3, months4_12, years1_2, years3_5, years6_12, years13_17, years18_60, years61_64, years65Plus }
  struct Age: Equatable { let years: Int; let months: Int }
  struct Reference {
    let lines: [String]
    let detail: String
    let source: String
    let url: URL
  }
  static func age(birth: Date?, on day: Date, calendar: Calendar) -> Age? {
    var civil = Calendar(identifier: .gregorian); civil.timeZone = calendar.timeZone
    guard let birth, birth.timeIntervalSinceReferenceDate.isFinite, day.timeIntervalSinceReferenceDate.isFinite,
          civil.startOfDay(for: birth) <= civil.startOfDay(for: day) else { return nil }
    let age = civil.dateComponents([.year, .month], from: civil.startOfDay(for: birth), to: civil.startOfDay(for: day))
    guard let years = age.year, let months = age.month, years >= 0 else { return nil }
    return .init(years: years, months: months)
  }
  static func adult(_ age: Age?) -> Bool { age.map { $0.years >= 18 } ?? true }
  static func sleep(_ age: Age?) -> SleepBand {
    guard let age else { return .adultUnspecified }
    switch age.years {
    case 0: return age.months <= 3 ? .months0_3 : .months4_12
    case 1...2: return .years1_2
    case 3...5: return .years3_5
    case 6...12: return .years6_12
    case 13...17: return .years13_17
    case 18...60: return .years18_60
    case 61...64: return .years61_64
    default: return .years65Plus
    }
  }
  static func reference(metric: GalaxySSIHealthMetric, age: Age?, language: String) -> Reference? {
    switch metric {
    case .bloodPressure where adult(age):
      return .init(lines: [text("bp_home", "Adult home average: systolic >=135 or diastolic >=85 mmHg", language),
        text("bp_office", "Adult clinic: systolic >=140 or diastolic >=90 mmHg", language)],
        detail: text("bp_detail", "Evaluation thresholds, not personal targets. A single reading is not a diagnosis.", language),
        source: text("bp_source", "Source: 2025 Chinese primary care hypertension guideline", language),
        url: URL(string: "https://cs.medjournals.cn/article/doi/full/10.3760/cma.j.cn112148-20250401-00234")!)
    case .restingHeartRate where adult(age):
      return .init(lines: [text("resting", "Typical adult resting range: 60-100 bpm", language)],
        detail: text("resting_detail", "For adults at rest. Training, illness and medicines may affect heart rate.", language),
        source: text("resting_source", "Source: American Heart Association", language),
        url: URL(string: "https://www.heart.org/en/health-topics/high-blood-pressure/the-facts-about-high-blood-pressure/all-about-heart-rate-pulse")!)
    case .sleepDuration:
      let band = sleep(age), fallback: String
      switch band {
      case .adultUnspecified: fallback = "Daily sleep: 18-60 yr >=7 h; 61-64 yr 7-9 h; 65+ yr 7-8 h"
      case .months0_3: fallback = "Daily sleep (0-3 months): 14-17 h"
      case .months4_12: fallback = "Daily sleep (4-12 months): 12-16 h including naps"
      case .years1_2: fallback = "Daily sleep (1-2 yr): 11-14 h including naps"
      case .years3_5: fallback = "Daily sleep (3-5 yr): 10-13 h including naps"
      case .years6_12: fallback = "Daily sleep (6-12 yr): 9-12 h"
      case .years13_17: fallback = "Daily sleep (13-17 yr): 8-10 h"
      case .years18_60: fallback = "Daily sleep (18-60 yr): >=7 h"
      case .years61_64: fallback = "Daily sleep (61-64 yr): 7-9 h"
      case .years65Plus: fallback = "Daily sleep (65+ yr): 7-8 h"
      }
      return .init(lines: [text("sleep." + band.rawValue, fallback, language)],
        detail: text("sleep_detail", "Needs vary by age; quality also matters. Unknown birth date shows adult bands as general reference.", language),
        source: text("sleep_source", "Source: CDC - About Sleep", language), url: URL(string: "https://www.cdc.gov/sleep/about/")!)
    default: return nil
    }
  }
  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.guidance." + key, fallback: fallback, language: language)
  }
}

extension GalaxySSIHealthRecords {
  func overviewBirthDate(expected: Archive) throws -> Date? {
    let current = try load()
    guard let permission = expected.profileAnalysisPermission, current.profileAnalysisPermission == permission else { return nil }
    return try loadProfile().birthDate
  }
}
