import Foundation

enum GalaxySSIHealthCareProfileScope {
  typealias Field = GalaxySSIHealthProfile.AnalysisField

  struct Selection: Codable, Equatable {
    var fields: Set<Field> = []
    var entries: Set<UUID> = []

    var isEmpty: Bool { fields.isEmpty && entries.isEmpty }
  }

  struct Link: Codable, Equatable {
    let selection: Selection
    let versions: [String: String]

    init(_ selection: Selection, profile: GalaxySSIHealthProfile) throws {
      guard !selection.isEmpty, selection.entries.count <= 30,
            Set(profile.background.map(\.id)).count == profile.background.count
      else { throw GalaxySSIHealthRecords.Failure.invalid }
      self.selection = selection
      var versions: [String: String] = [:]
      for field in selection.fields {
        versions["field:" + field.rawValue] = profile.analysisVersion(field)?.uuidString ?? "unavailable"
      }
      let entries = Dictionary(uniqueKeysWithValues: profile.background.map { ($0.id, $0) })
      for id in selection.entries {
        versions["entry:" + id.uuidString] = entries[id].flatMap { profile.backgroundVersion($0) }?.uuidString ?? "unavailable"
      }
      self.versions = versions
    }

    func isCurrent(_ profile: GalaxySSIHealthProfile) -> Bool {
      (try? Link(selection, profile: profile)) == self
    }

    func snapshot(_ profile: GalaxySSIHealthProfile, measuredAt: Date) throws -> AgentMcpJSONObject {
      guard isCurrent(profile) else { throw GalaxySSIHealthRecords.Failure.stale }
      var utc = Calendar(identifier: .gregorian)
      utc.timeZone = TimeZone(secondsFromGMT: 0)!
      let date = utc.startOfDay(for: measuredAt)
      var local = Calendar(identifier: .gregorian)
      local.timeZone = .current
      var fields: AgentMcpJSONObject = [:]
      for field in selection.fields {
        let value = profile.analysisValue(field)
        let key = field == .birthDate ? "age_at_measurement" : field.rawValue
        let result: AgentMcpJSONValue
        switch value {
        case .date(let birth):
          let day = utc.date(from: local.dateComponents([.year, .month, .day], from: birth))
          if let day, day <= date, let years = utc.dateComponents([.year], from: day, to: date).year {
            result = .int(Int64(years))
          } else { result = .null }
        case .sex(let sex): result = .string(sex.rawValue)
        case .height(let height, let unit):
          result = .object(["value": .string(NSDecimalNumber(decimal: height).stringValue), "unit": .string(unit.rawValue)])
        case .context(let context): result = .string(context)
        case nil: result = .null
        }
        fields[key] = .object(["state": .string(result == .null ? "unknown" : "known"), "value": result])
      }
      let entries = profile.background.filter { selection.entries.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
      return [
        "source": .string("saved_self_reported_profile"), "scope": .string("explicitly_selected_fields_and_entries"),
        "fields": .object(fields), "entries": .array(entries.map {
          .object(["kind": .string($0.kind.rawValue), "title": .string($0.title), "notes": .string($0.notes)])
        }),
        "unavailable_selected_entries": .int(Int64(selection.entries.count - entries.count)),
        "complete_medical_history": .bool(false), "unselected_means_absent": .bool(false),
        "drafts_included": .bool(false), "current_symptoms_assessed": .bool(false)
      ]
    }
  }
}
